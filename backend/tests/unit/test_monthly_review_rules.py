"""Pure domain tests for monthly review summaries, decisions and snapshots."""

import json
from dataclasses import FrozenInstanceError
from datetime import UTC, date, datetime

import pytest

from tefteri.domain.enums import KeyResultUpdate, ThemeDecision, TrendState
from tefteri.domain.monthly import (
    CategoryCounts,
    DecisionInput,
    DoneMilestone,
    KeyResultInput,
    MonthlyReviewInput,
    SeriesValue,
    SuggestionEligibility,
    ThemeInput,
    after_month_end,
    base_value,
    build_payload,
    build_suggestions,
    decision_effect,
    key_result_change,
    key_result_flags,
    key_result_status,
    off_plan_share,
    shared_key_results,
    trend,
)


def test_key_result_status_base_and_change_use_month_boundaries() -> None:
    start = date(2030, 3, 1)
    end = date(2030, 4, 1)
    values = (
        SeriesValue(90.0, date(2030, 2, 20), datetime(2030, 2, 20, tzinfo=UTC), 1),
        SeriesValue(110.0, date(2030, 3, 1), datetime(2030, 3, 1, tzinfo=UTC), 2),
        SeriesValue(125.0, date(2030, 3, 28), datetime(2030, 3, 28, tzinfo=UTC), 3),
        SeriesValue(130.0, date(2030, 4, 2), datetime(2030, 4, 2, tzinfo=UTC), 4),
    )
    assert key_result_status(values[0].at, start) is KeyResultUpdate.NOT_UPDATED
    assert key_result_status(None, start) is KeyResultUpdate.NOT_UPDATED
    assert base_value(100.0, values, start) == 110.0
    assert base_value(100.0, (), start) == 100.0
    assert base_value(100.0, (values[0],), start) == 90.0
    assert key_result_change(125.0, base_value(100.0, values, start)) == 15.0
    assert key_result_status(values[2].at, start) is KeyResultUpdate.UPDATED
    assert key_result_status(values[3].at, start) is KeyResultUpdate.UPDATED
    assert after_month_end(values[3].at, end)
    assert not after_month_end(values[2].at, end)


def test_empty_series_falls_back_to_start_value_without_a_timestamp() -> None:
    assert base_value(42.0, (), date(2030, 3, 1)) == 42.0
    assert key_result_status(None, date(2030, 3, 1)) is KeyResultUpdate.NOT_UPDATED


def test_shared_results_only_when_multiple_focus_themes_are_linked() -> None:
    assert shared_key_results(
        {"kr1": {"a", "b"}, "kr2": {"a", "c"}, "kr3": {"x"}},
        {"a", "b", "c"},
    ) == frozenset({"kr1", "kr2"})


def test_key_result_flags_add_no_theme_only_when_no_usable_link_is_in_focus() -> None:
    assert key_result_flags({"theme-a"}, {"theme-a"}, ("no_usable_theme",)) == ("no_usable_theme",)
    assert key_result_flags({"theme-a"}, {"theme-b"}, ()) == ("no_theme_in_focus",)
    assert key_result_flags(set(), {"theme-b"}, ("no_usable_theme",)) == (
        "no_usable_theme",
        "no_theme_in_focus",
    )


def test_off_plan_share_ignores_hidden_and_empty_total_has_no_share() -> None:
    counts = CategoryCounts(goal_aligned=2, maintenance=3, off_plan=5, hidden=100)
    assert off_plan_share(counts) == 0.5
    assert off_plan_share(CategoryCounts(hidden=9)) is None


def test_trend_compares_two_prior_months_strictly() -> None:
    assert (
        trend(
            CategoryCounts(goal_aligned=1, off_plan=9),
            (
                CategoryCounts(goal_aligned=8, off_plan=2),
                CategoryCounts(goal_aligned=7, off_plan=3),
            ),
        )
        is TrendState.RISING
    )
    assert (
        trend(
            CategoryCounts(goal_aligned=7, off_plan=3),
            (
                CategoryCounts(goal_aligned=8, off_plan=2),
                CategoryCounts(goal_aligned=7, off_plan=3),
            ),
        )
        is TrendState.NOT_RISING
    )
    assert (
        trend(
            CategoryCounts(goal_aligned=1, off_plan=9),
            (CategoryCounts(goal_aligned=8, off_plan=2), CategoryCounts()),
        )
        is TrendState.NOT_ENOUGH_HISTORY
    )
    assert (
        trend(
            CategoryCounts(maintenance=100),
            (CategoryCounts(maintenance=100), CategoryCounts(maintenance=100)),
        )
        is TrendState.NOT_RISING
    )


@pytest.mark.parametrize(
    ("decision", "target", "replacement", "expected"),
    [
        (
            ThemeDecision.CARRY,
            3,
            None,
            "Carry this theme into next month with a target of 3 milestones.",
        ),
        (ThemeDecision.CARRY, None, None, "Carry this theme into next month with no target."),
        (ThemeDecision.DROP, None, None, "Drop this theme next month."),
        (ThemeDecision.REPLACE, None, "Talks", "Replace this theme with Talks next month."),
        (ThemeDecision.LATER, None, None, "Decide about this theme later."),
    ],
)
def test_decision_effect_is_shared_review_copy(
    decision: ThemeDecision, target: int | None, replacement: str | None, expected: str
) -> None:
    assert decision_effect(decision, target=target, replacement_name=replacement) == expected


def test_build_suggestions_carries_replaces_skips_and_reports_source_month() -> None:
    decisions = (
        DecisionInput("a", "Alpha", ThemeDecision.CARRY, target=3),
        DecisionInput(
            "b",
            "Beta",
            ThemeDecision.REPLACE,
            replacement_project_id="d",
            replacement_name="Delta",
        ),
        DecisionInput("c", "Gamma", ThemeDecision.DROP),
        DecisionInput("d", "Delta", ThemeDecision.LATER),
        DecisionInput("e", "Old", ThemeDecision.CARRY, target=2),
    )
    result = build_suggestions(
        date(2030, 4, 1),
        date(2030, 3, 1),
        decisions,
        {
            "a": SuggestionEligibility(True),
            "d": SuggestionEligibility(True),
            "e": SuggestionEligibility(False, "orphaned"),
        },
    )
    assert result.from_month == date(2030, 3, 1)
    assert result.suggestions == (
        {"project_id": "a", "name": "Alpha", "target": 3, "reason": "carry", "replaces": None},
        {
            "project_id": "d",
            "name": "Delta",
            "target": None,
            "reason": "replace",
            "replaces": {"project_id": "b", "name": "Beta"},
        },
    )
    assert result.skipped == ({"project_id": "e", "name": "Old", "reason": "orphaned"},)


def test_build_payload_is_plain_json_uses_stored_names_and_has_no_shares_or_effort() -> None:
    source = MonthlyReviewInput(
        month=date(2030, 3, 1),
        taken_at=datetime(2030, 4, 2, 8, tzinfo=UTC),
        themes=(
            ThemeInput(
                project_id="theme-a",
                name="Name at review",
                target=1,
                counts_from=date(2030, 3, 1),
                done=(DoneMilestone("m1", "Ship it", date(2030, 3, 8), "theme-a"),),
            ),
        ),
        categories=CategoryCounts(2, 3, 4, 5),
        key_results=(
            KeyResultInput(
                key_result_id="kr",
                goal_id="goal",
                goal_title="Goal title",
                metric="One measure",
                update_source="manual",
                start_value=10,
                base_value=12,
                latest_value=14,
                latest_at=datetime(2030, 3, 20, tzinfo=UTC),
                target=20,
                deadline=date(2030, 12, 31),
                theme_ids=("theme-a",),
            ),
        ),
        decisions=(
            DecisionInput("theme-a", "Stored decision name", ThemeDecision.CARRY, target=1),
        ),
    )
    payload = build_payload(source)
    assert type(payload) is dict
    encoded = json.dumps(payload)
    decoded = json.loads(encoded)
    assert decoded["themes"][0]["name"] == "Name at review"
    assert decoded["categories"] == {
        "goal_aligned": 2,
        "maintenance": 3,
        "off_plan": 4,
        "hidden": 5,
    }
    assert decoded["decisions"][0]["name"] == "Stored decision name"

    def keys(value: object) -> list[str]:
        if isinstance(value, dict):
            return list(value) + [key for child in value.values() for key in keys(child)]
        if isinstance(value, list):
            return [key for child in value for key in keys(child)]
        return []

    forbidden = ("share", "percent", "hours", "duration", "effort")
    assert not any(
        word in key.lower() for key in keys(decoded) if key != "shared" for word in forbidden
    )
    with pytest.raises(FrozenInstanceError):
        source.month = date(2030, 4, 1)  # type: ignore[misc]
    with pytest.raises(FrozenInstanceError):
        source.themes[0].name = "changed"  # type: ignore[misc]
