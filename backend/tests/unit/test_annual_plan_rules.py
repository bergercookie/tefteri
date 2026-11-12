"""The pure rules of the annual plan (spec 006): year state, the limit of three, seeding."""

from datetime import UTC, date, datetime

from tefteri.domain.annual_plan import (
    MAX_ACTIVE_KEY_RESULTS,
    next_free_slot,
    shift_deadline,
    suggest,
    today_in,
    year_state,
)
from tefteri.domain.classification import ProjectNode
from tefteri.domain.enums import ProjectLabel
from tefteri.domain.key_results import LinkView, ValueEntry

T = ProjectLabel.THEME


def nodes(*items: ProjectNode) -> dict[str, ProjectNode]:
    return {n.key: n for n in items}


# -- year state (FR-033) -----------------------------------------------------------------------


def test_the_year_state_comes_from_the_year_and_today() -> None:
    assert year_state(2026, date(2026, 1, 1)) == "current"
    assert year_state(2026, date(2026, 12, 31)) == "current"
    assert year_state(2025, date(2026, 6, 1)) == "past"
    assert year_state(2027, date(2026, 6, 1)) == "future"


def test_today_in_a_time_zone_sees_the_local_day() -> None:
    # 2027-01-01 00:30 UTC is still 2026-12-31 in UTC-2.
    now = datetime(2027, 1, 1, 0, 30, tzinfo=UTC)
    assert today_in("Etc/GMT+2", now) == date(2026, 12, 31)
    # And already 2027-01-01 in UTC+2.
    assert today_in("Etc/GMT-2", now) == date(2027, 1, 1)


# -- the limit of three (FR-003, R-03) ---------------------------------------------------------


def test_three_is_the_limit() -> None:
    assert MAX_ACTIVE_KEY_RESULTS == 3


def test_the_lowest_free_slot_is_chosen() -> None:
    assert next_free_slot(()) == 1
    assert next_free_slot((1,)) == 2
    assert next_free_slot((2,)) == 1
    assert next_free_slot((1, 2)) == 3


def test_a_retired_key_result_frees_its_slot() -> None:
    # Only the slots of the active key results are taken.
    assert next_free_slot((1, 3)) == 2
    assert next_free_slot((1, 2, 3)) is None


# -- deadline shift (R-10) ---------------------------------------------------------------------


def test_the_deadline_moves_into_the_new_year_with_the_same_month_and_day() -> None:
    assert shift_deadline(date(2026, 12, 31), 2027) == date(2027, 12, 31)
    assert shift_deadline(date(2026, 1, 1), 2027) == date(2027, 1, 1)


def test_29_february_becomes_28_february() -> None:
    assert shift_deadline(date(2028, 2, 29), 2029) == date(2029, 2, 28)
    assert shift_deadline(date(2028, 2, 29), 2028) == date(2028, 2, 29)


# -- seeding (FR-016, FR-017, R-10) ------------------------------------------------------------


def _kr(
    key: str,
    *,
    start: float,
    target: float,
    entries: tuple[ValueEntry, ...] = (),
    status: str = "active",
    deadline: date = date(2026, 6, 30),
    links: tuple[LinkView, ...] = (),
) -> object:
    from tefteri.domain.annual_plan import PastKeyResult

    return PastKeyResult(
        id=key,
        status=status,
        metric=f"Metric {key}",
        start_value=start,
        target=target,
        deadline=deadline,
        entries=entries,
        links=links,
    )


def _goal(key: str, krs: tuple[object, ...] = (), status: str = "active") -> object:
    from tefteri.domain.annual_plan import PastGoal

    return PastGoal(id=key, status=status, key_results=krs)  # type: ignore[arg-type]


def _suggest(goals: list[object], year: int = 2027, from_year: int = 2026, tree=None) -> list:
    return suggest(
        goals,  # type: ignore[arg-type]
        year=year,
        from_year=from_year,
        nodes=tree if tree is not None else nodes(ProjectNode("t", None, T)),
    )


def test_an_unmet_key_result_is_offered_with_the_last_value_as_start() -> None:
    out = _suggest(
        [
            _goal(
                "g",
                (_kr("k1", start=0, target=100, entries=(ValueEntry(40, date(2026, 5, 1), 1),)),),
            )
        ]
    )
    assert len(out) == 1
    (kr,) = out[0].key_results
    assert kr.start_value == 40  # the last value, not the old start
    assert kr.target == 100
    assert kr.deadline == date(2027, 6, 30)


def test_the_start_value_counts_when_the_series_is_empty() -> None:
    # start 40 of target 100 was never updated: unmet, suggested start 40.
    out = _suggest([_goal("g", (_kr("k1", start=40, target=100),))])
    (kr,) = out[0].key_results
    assert kr.start_value == 40


def test_a_met_key_result_is_not_offered_but_its_goal_is() -> None:
    out = _suggest(
        [
            _goal(
                "g",
                (
                    _kr(
                        "met", start=0, target=100, entries=(ValueEntry(100, date(2026, 5, 1), 1),)
                    ),
                    _kr(
                        "unmet", start=0, target=100, entries=(ValueEntry(20, date(2026, 5, 1), 1),)
                    ),
                ),
            )
        ]
    )
    assert len(out) == 1
    assert [k.key_result_id for k in out[0].key_results] == ["unmet"]


def test_a_goal_where_every_key_result_is_met_is_still_offered() -> None:
    out = _suggest(
        [
            _goal(
                "g",
                (_kr("met", start=0, target=100, entries=(ValueEntry(120, date(2026, 5, 1), 1),)),),
            )
        ]
    )
    assert len(out) == 1 and out[0].key_results == ()


def test_a_goal_with_no_key_result_is_offered() -> None:
    out = _suggest([_goal("g", ())])
    assert len(out) == 1 and out[0].key_results == ()


def test_retired_goals_and_key_results_are_not_offered() -> None:
    out = _suggest(
        [
            _goal("r", (_kr("k", start=0, target=100),), status="retired"),
            _goal(
                "g",
                (
                    _kr("gone", start=0, target=100, status="retired"),
                    _kr("live", start=0, target=100),
                ),
            ),
        ]
    )
    assert [g.goal_id for g in out] == ["g"]
    assert [k.key_result_id for k in out[0].key_results] == ["live"]


def test_a_link_to_a_theme_that_is_still_usable_is_offered() -> None:
    tree = nodes(ProjectNode("t", None, T))
    out = _suggest(
        [
            _goal(
                "g",
                (
                    _kr(
                        "k",
                        start=0,
                        target=100,
                        links=(LinkView(name="Open", key="t", active=True),),
                    ),
                ),
            )
        ],
        tree=tree,
    )
    (kr,) = out[0].key_results
    assert kr.theme_keys == ("t",)


def test_a_link_to_an_ignored_orphaned_or_relabelled_theme_is_not_offered() -> None:
    tree = nodes(
        ProjectNode("t", None, T),
        ProjectNode("x", None, ProjectLabel.IGNORED),
        ProjectNode("o", None, T, orphaned=True),
        ProjectNode("m", None, ProjectLabel.MILESTONE),
    )
    out = _suggest(
        [
            _goal(
                "g",
                (_kr("k", start=0, target=100),),
            )
        ],
        tree=tree,
    )
    # The key result is still offered; only its unusable link is dropped.
    assert len(out) == 1
    (kr,) = out[0].key_results
    assert kr.theme_keys == ()


def test_the_from_year_must_be_earlier_than_the_year() -> None:
    import pytest

    from tefteri.domain.key_results import ValidationError

    with pytest.raises(ValidationError):
        _suggest([_goal("g")], year=2027, from_year=2027)
    with pytest.raises(ValidationError):
        _suggest([_goal("g")], year=2027, from_year=2028)
