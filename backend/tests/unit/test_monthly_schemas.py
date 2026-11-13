"""Every monthly API enum value stays serializable in its Pydantic schema."""

import uuid
from datetime import UTC, date, datetime

import pytest

from tefteri.api.routers.monthly import (
    FocusHistoryEntryOut,
    FocusSaveIn,
    MonthlyEntryOut,
    MonthlyKeyResultOut,
    MonthlyPlanOut,
    MonthlyReviewOut,
    ReviewStoreIn,
    SkippedSuggestionOut,
    ThemeSuggestionOut,
    TrendOut,
)
from tefteri.domain.enums import (
    CountNote,
    FocusChangeKind,
    FocusChangeSource,
    FocusEntryStatus,
    KeyResultUpdate,
    MonthlyFlagCode,
    MonthState,
    OrphanReason,
    ProjectLabel,
    SkippedSuggestionReason,
    TargetMarker,
    ThemeDecision,
    ThemeSuggestionReason,
    TrendState,
    UpdateSource,
)

_ID = uuid.uuid4()


def _entry(
    *,
    status: FocusEntryStatus = FocusEntryStatus.IN_FOCUS,
    marker: TargetMarker | None = None,
    orphan_reason: OrphanReason | None = None,
    label: ProjectLabel | None = None,
) -> dict[str, object]:
    return {
        "id": _ID,
        "project_id": _ID,
        "connection_id": _ID,
        "name": "Theme",
        "target": None,
        "counts_from": date(2030, 3, 1),
        "left_on": None,
        "status": status,
        "done": 0,
        "earlier_not_counted": 0,
        "marker": marker,
        "orphaned": (
            {"reason": orphan_reason, "at": datetime(2030, 3, 1, tzinfo=UTC)}
            if orphan_reason is not None
            else None
        ),
        "label_changed": label,
        "linked_key_results": 0,
        "last_month_done": 0,
    }


def _snapshot(
    *,
    update_status: KeyResultUpdate = KeyResultUpdate.NOT_UPDATED,
    decision: ThemeDecision = ThemeDecision.LATER,
    update_source: UpdateSource = UpdateSource.MANUAL,
    flags: tuple[MonthlyFlagCode, ...] = (),
) -> dict[str, object]:
    return {
        "schema_version": 1,
        "month": date(2030, 3, 1),
        "month_end": date(2030, 4, 1),
        "taken_at": datetime(2030, 4, 1, tzinfo=UTC),
        "themes": [
            {
                "project_id": _ID,
                "name": "Theme",
                "target": None,
                "counts_from": date(2030, 3, 1),
                "left_on": None,
                "status": FocusEntryStatus.IN_FOCUS,
                "orphaned": None,
                "label_changed": None,
                "done": 0,
                "marker": TargetMarker.NO_TARGET,
                "milestones": [],
                "earlier_not_counted": [],
                "key_result_ids": [],
            }
        ],
        "changes": [],
        "outside_focus": [],
        "categories": {
            "goal_aligned": 0,
            "maintenance": 0,
            "off_plan": 0,
            "hidden": 0,
        },
        "key_results": [
            {
                "key_result_id": _ID,
                "goal_id": _ID,
                "goal_title": "Goal",
                "metric": "Metric",
                "update_source": update_source,
                "start_value": 0,
                "base_value": 0,
                "latest_value": 0,
                "latest_at": None,
                "change": 0,
                "status": update_status,
                "entered_in_review": False,
                "after_month_end": False,
                "target": 10,
                "deadline": date(2030, 12, 31),
                "past_deadline": False,
                "retired": False,
                "theme_ids": [],
                "shared": False,
                "flags": list(flags),
            }
        ],
        "decisions": [
            {
                "project_id": _ID,
                "name": "Theme",
                "decision": decision,
                "replacement_project_id": None,
                "replacement_name": None,
            }
        ],
    }


def _key_result(*, flag: MonthlyFlagCode) -> dict[str, object]:
    return {
        "id": _ID,
        "goal_id": _ID,
        "goal_title": "Goal",
        "metric": "Metric",
        "start_value": 0,
        "current_value": 0,
        "current_at": None,
        "target": 10,
        "deadline": date(2030, 12, 31),
        "update_source": UpdateSource.MANUAL,
        "past_deadline": False,
        "theme_ids": [],
        "flags": [{"code": flag, "actions": [], "reasons": []}],
    }


def test_monthly_plan_enum_values_serialize() -> None:
    """Cover every enum field used by the planning response models."""
    for state in MonthState:
        for note in CountNote:
            result = MonthlyPlanOut.model_validate(
                {
                    "month": "2030-03",
                    "start": date(2030, 3, 1),
                    "end": date(2030, 4, 1),
                    "state": state,
                    "planning_year": 2030,
                    "focus_known": True,
                    "count_note": note,
                    "entries": [_entry()],
                    "key_results": [],
                    "themes_without_key_result": [],
                    "review": {"stored": False, "current_version": None, "versions": 0},
                    "earlier_format": False,
                }
            )
            assert result.model_dump(mode="json")["state"] == state.value
            assert result.model_dump(mode="json")["count_note"] == note.value
    for status in FocusEntryStatus:
        assert MonthlyEntryOut.model_validate(_entry(status=status)).model_dump(mode="json")
    for marker in TargetMarker:
        assert MonthlyEntryOut.model_validate(_entry(marker=marker)).marker is marker
    for reason in OrphanReason:
        assert MonthlyEntryOut.model_validate(_entry(orphan_reason=reason)).orphaned is not None
    for label in ProjectLabel:
        assert MonthlyEntryOut.model_validate(_entry(label=label)).label_changed is label
    for source in UpdateSource:
        key_result = MonthlyKeyResultOut.model_validate(
            {
                "id": _ID,
                "goal_id": _ID,
                "goal_title": "Goal",
                "metric": "Metric",
                "start_value": 0,
                "current_value": 0,
                "current_at": None,
                "target": 10,
                "deadline": date(2030, 12, 31),
                "update_source": source,
                "past_deadline": False,
                "theme_ids": [],
                "flags": [],
            }
        )
        assert key_result.model_dump(mode="json")["update_source"] == source.value
    for code in MonthlyFlagCode:
        key_result = MonthlyKeyResultOut.model_validate(_key_result(flag=code))
        assert key_result.model_dump(mode="json")["flags"][0]["code"] == code.value


def test_monthly_review_and_decision_enum_values_serialize() -> None:
    """Cover every trend, decision and suggestion enum value in API models."""
    for state in TrendState:
        review = MonthlyReviewOut.model_validate(
            {
                "month": "2030-03",
                "stored": False,
                "draft": True,
                "version": None,
                "current_version": None,
                "taken_at": None,
                "versions": [],
                "snapshot": _snapshot(),
                "trend": {
                    "state": state,
                    "share": None,
                    "previous": [],
                    "note": None,
                },
                "categories_note": None,
            }
        )
        assert review.model_dump(mode="json")["trend"]["state"] == state.value
    for decision in ThemeDecision:
        snapshot = _snapshot(decision=decision)
        review = MonthlyReviewOut.model_validate(
            {
                "month": "2030-03",
                "stored": False,
                "draft": True,
                "version": None,
                "current_version": None,
                "taken_at": None,
                "versions": [],
                "snapshot": snapshot,
                "trend": {"state": TrendState.NOT_ENOUGH_HISTORY, "share": None, "previous": []},
                "categories_note": None,
            }
        )
        assert review.model_dump(mode="json")["snapshot"]["decisions"][0]["decision"] == (
            decision.value
        )
        body = ReviewStoreIn.model_validate(
            {"decisions": [{"project_id": _ID, "decision": decision}]}
        )
        assert body.model_dump(mode="json")["decisions"][0]["decision"] == decision.value
    for reason in ThemeSuggestionReason:
        suggestion = ThemeSuggestionOut.model_validate(
            {
                "project_id": _ID,
                "name": "Theme",
                "target": None,
                "reason": reason,
                "replaces": None,
            }
        )
        assert suggestion.model_dump(mode="json")["reason"] == reason.value
    for skipped_reason in SkippedSuggestionReason:
        skipped = SkippedSuggestionOut.model_validate(
            {"project_id": _ID, "name": "Theme", "reason": skipped_reason}
        )
        assert skipped.model_dump(mode="json")["reason"] == skipped_reason.value


def test_history_and_request_enum_values_serialize() -> None:
    """Cover each focus change kind/source and the review update status vocabulary."""
    for kind in FocusChangeKind:
        for source in FocusChangeSource:
            item = FocusHistoryEntryOut.model_validate(
                {
                    "batch_id": _ID,
                    "kind": kind,
                    "on": date(2030, 3, 1),
                    "out_name": None,
                    "in_name": None,
                    "target_before": None,
                    "target_after": None,
                    "source": source,
                    "undone": False,
                    "can_undo": True,
                }
            )
            assert item.model_dump(mode="json")["kind"] == kind.value
            assert item.model_dump(mode="json")["source"] == source.value
    for status in KeyResultUpdate:
        snapshot = MonthlyReviewOut.model_validate(
            {
                "month": "2030-03",
                "stored": False,
                "draft": True,
                "version": None,
                "current_version": None,
                "taken_at": None,
                "versions": [],
                "snapshot": _snapshot(update_status=status),
                "trend": {
                    "state": TrendState.NOT_ENOUGH_HISTORY,
                    "share": None,
                    "previous": [],
                },
                "categories_note": None,
            }
        )
        assert snapshot.snapshot.key_results[0].status is status
    for code in MonthlyFlagCode:
        snapshot = MonthlyReviewOut.model_validate(
            {
                "month": "2030-03",
                "stored": False,
                "draft": True,
                "version": None,
                "current_version": None,
                "taken_at": None,
                "versions": [],
                "snapshot": _snapshot(flags=(code,)),
                "trend": {
                    "state": TrendState.NOT_ENOUGH_HISTORY,
                    "share": None,
                    "previous": [],
                },
                "categories_note": None,
            }
        )
        assert snapshot.snapshot.key_results[0].flags[0] is code


def test_schema_rejects_unlisted_monthly_values() -> None:
    """A new domain value cannot silently bypass a response schema."""
    with pytest.raises(ValueError):
        MonthlyEntryOut.model_validate(_entry(status="not_a_status"))  # type: ignore[arg-type]
    with pytest.raises(ValueError):
        FocusSaveIn.model_validate({"entries": [], "dry_run": "maybe"})
    with pytest.raises(ValueError):
        TrendOut.model_validate(
            {"state": "not_a_trend", "share": None, "previous": [], "note": None}
        )
