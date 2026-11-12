"""The pure rules of key results (spec 006): progress, met, overdue, series, validation, flags."""

from datetime import UTC, date, datetime, timedelta, timezone

from tefteri.domain.classification import ProjectNode
from tefteri.domain.enums import ProjectLabel
from tefteri.domain.key_results import (
    Flag,
    LinkView,
    ValidationError,
    ValueEntry,
    current_value,
    goal_flags,
    goal_progress,
    is_met,
    is_overdue,
    is_usable_link,
    key_result_flags,
    link_state,
    progress,
    validate,
    value_on_or_before,
)

T, M, R, X = (
    ProjectLabel.THEME,
    ProjectLabel.MILESTONE,
    ProjectLabel.MAINTENANCE,
    ProjectLabel.IGNORED,
)


def nodes(*items: ProjectNode) -> dict[str, ProjectNode]:
    return {n.key: n for n in items}


# -- progress (FR-008) -------------------------------------------------------------------------


def test_progress_rises_to_the_target() -> None:
    assert progress(120, 500, 220) == 100 / 380


def test_progress_works_in_both_directions() -> None:
    # A lower target: from 10 down to 4 is half the way.
    assert progress(10, 4, 7) == 0.5
    # A higher target: from 0 up to 50 out of 100.
    assert progress(0, 100, 50) == 0.5


def test_progress_is_not_capped_above_one() -> None:
    assert progress(0, 100, 250) == 2.5


def test_progress_is_negative_away_from_the_target() -> None:
    assert progress(120, 500, 60) == -60 / 380
    assert progress(10, 4, 12) == -1 / 3


# -- met (FR-008) ------------------------------------------------------------------------------


def test_met_when_the_target_is_reached_from_below() -> None:
    assert is_met(120, 500, 500)
    assert is_met(120, 500, 700)
    assert not is_met(120, 500, 499)


def test_met_when_the_target_is_reached_from_above() -> None:
    assert is_met(10, 4, 4)
    assert is_met(10, 4, 2)
    assert not is_met(10, 4, 5)


def test_equal_to_the_target_counts_as_met() -> None:
    assert is_met(0, 100, 100)
    assert is_met(100, 0, 0)


# -- overdue (FR-014) --------------------------------------------------------------------------


def test_overdue_after_the_deadline_when_not_met() -> None:
    assert is_overdue(deadline=date(2027, 6, 30), today=date(2027, 7, 1), met=False, active=True)


def test_a_deadline_of_today_is_not_overdue() -> None:
    assert not is_overdue(deadline=date(2027, 7, 1), today=date(2027, 7, 1), met=False, active=True)


def test_a_met_key_result_is_never_overdue() -> None:
    assert not is_overdue(deadline=date(2027, 6, 30), today=date(2027, 7, 1), met=True, active=True)


def test_a_retired_key_result_is_never_overdue() -> None:
    assert not is_overdue(
        deadline=date(2027, 6, 30), today=date(2027, 7, 1), met=False, active=False
    )


def test_no_deadline_is_never_overdue() -> None:
    assert not is_overdue(deadline=None, today=date(2027, 7, 1), met=False, active=True)


# -- the series (FR-007, FR-034) ---------------------------------------------------------------


def test_current_value_is_the_entry_with_the_latest_date() -> None:
    entries = [
        ValueEntry(value=10, on_date=date(2027, 1, 1), seq=1),
        ValueEntry(value=20, on_date=date(2027, 3, 1), seq=2),
    ]
    assert current_value(0, entries) == 20


def test_on_equal_dates_the_higher_seq_wins_and_both_are_kept() -> None:
    entries = [
        ValueEntry(value=10, on_date=date(2027, 3, 1), seq=1),
        ValueEntry(value=20, on_date=date(2027, 3, 1), seq=2),
    ]
    assert current_value(0, entries) == 20
    assert len(entries) == 2  # both are kept


def test_an_empty_series_gives_the_start_value() -> None:
    assert current_value(120, ()) == 120


def test_value_on_or_before_gives_the_last_entry_of_the_day_or_before() -> None:
    entries = [
        ValueEntry(value=10, on_date=date(2027, 1, 5), seq=1),
        ValueEntry(value=20, on_date=date(2027, 2, 5), seq=2),
        ValueEntry(value=30, on_date=date(2027, 2, 5), seq=3),
    ]
    found = value_on_or_before(0, entries, date(2027, 2, 10))
    assert found is not None and found.value == 30 and found.seq == 3
    earlier = value_on_or_before(0, entries, date(2027, 1, 31))
    assert earlier is not None and earlier.value == 10


def test_value_on_or_before_gives_none_before_the_first_value() -> None:
    entries = [ValueEntry(value=10, on_date=date(2027, 1, 5), seq=1)]
    assert value_on_or_before(0, entries, date(2027, 1, 4)) is None
    assert value_on_or_before(0, (), date(2027, 1, 4)) is None


# -- validation (FR-005) -----------------------------------------------------------------------


def _invalid(**kwargs: object) -> str:
    """Run ``validate`` and return the field it refuses."""
    full = {
        "metric": "Stars on one repository",
        "start_value": 120,
        "target": 500,
        "deadline": date(2027, 12, 31),
        "year": 2027,
    } | kwargs
    try:
        validate(**full)  # type: ignore[arg-type]
    except ValidationError as e:
        return e.field
    raise AssertionError("validate accepted an invalid key result")


def test_target_equal_to_start_is_refused() -> None:
    assert _invalid(target=120) == "target"


def test_nan_and_infinity_are_refused() -> None:
    assert _invalid(start_value=float("nan")) == "start_value"
    assert _invalid(target=float("inf")) == "target"
    assert _invalid(target=float("-inf")) == "target"


def test_text_as_a_number_is_refused() -> None:
    assert _invalid(start_value="many") == "start_value"
    assert _invalid(start_value="500") == "start_value"
    assert _invalid(target="500") == "target"


def test_a_deadline_outside_the_year_is_refused() -> None:
    assert _invalid(deadline=date(2026, 12, 31)) == "deadline"
    assert _invalid(deadline=date(2028, 1, 1)) == "deadline"


def test_a_deadline_of_31_december_and_1_january_are_valid() -> None:
    validate(
        metric="Stars",
        start_value=0,
        target=100,
        deadline=date(2027, 12, 31),
        year=2027,
    )
    validate(
        metric="Stars",
        start_value=0,
        target=100,
        deadline=date(2027, 1, 1),
        year=2027,
    )


def test_an_empty_metric_is_refused() -> None:
    assert _invalid(metric="   ") == "metric"


def test_booleans_are_not_numbers() -> None:
    assert _invalid(start_value=True) == "start_value"


# -- the usable-link rule (FR-012, R-12) -------------------------------------------------------


def test_a_stored_theme_without_an_ignored_ancestor_is_usable() -> None:
    tree = nodes(ProjectNode("t", None, T), ProjectNode("s", "t", None))
    assert is_usable_link(tree, "t")


def test_an_unclassified_project_with_a_theme_proposal_is_not_usable() -> None:
    # Top level unclassified counts as a theme proposal, but has no stored label.
    tree = nodes(ProjectNode("u", None, None))
    assert not is_usable_link(tree, "u")


def test_milestone_maintenance_and_ignored_are_not_usable() -> None:
    tree = nodes(ProjectNode("m", None, M), ProjectNode("r", None, R), ProjectNode("x", None, X))
    for key in ("m", "r", "x"):
        assert not is_usable_link(tree, key)


def test_an_orphaned_theme_is_not_usable() -> None:
    tree = nodes(ProjectNode("t", None, T, orphaned=True))
    assert not is_usable_link(tree, "t")


def test_an_ignored_ancestor_makes_a_theme_not_usable() -> None:
    tree = nodes(ProjectNode("x", None, X), ProjectNode("t", "x", T))
    assert not is_usable_link(tree, "t")


def test_a_cycle_in_the_parent_links_does_not_loop() -> None:
    tree = nodes(
        ProjectNode("a", "b", T),
        ProjectNode("b", "a", None),
    )
    assert is_usable_link(tree, "a")


# -- link states and flags (FR-014) ------------------------------------------------------------


def test_link_states() -> None:
    tree = nodes(
        ProjectNode("t", None, T),
        ProjectNode("o", None, T, orphaned=True),
        ProjectNode("x", None, X),
        ProjectNode("x_child", "x", T),
        ProjectNode("m", None, M),
        ProjectNode("u", None, None),
    )
    assert link_state(tree, "t") == ("ok", None)
    assert link_state(tree, "o") == ("orphaned", None)
    assert link_state(tree, "x") == ("ignored", None)
    assert link_state(tree, "x_child") == ("ignored", None)
    assert link_state(tree, "m") == ("relabelled", ProjectLabel.MILESTONE)
    assert link_state(tree, "u") == ("unclassified", None)


def test_a_link_to_an_unknown_project_is_orphaned() -> None:
    assert link_state({}, "gone") == ("orphaned", None)


def test_a_goal_with_no_active_key_result_is_flagged() -> None:
    flags = goal_flags(active_key_results=0)
    assert [f.code for f in flags] == ["no_key_result"]
    assert flags[0].actions == ("add_key_result",)


def test_a_goal_with_an_active_key_result_is_not_flagged() -> None:
    # Retired ones do not count: only the active number is passed in.
    assert goal_flags(active_key_results=1) == ()
    assert goal_flags(active_key_results=3) == ()


def _kr_flags(tree: dict[str, ProjectNode], links: list[LinkView], **kwargs: object) -> Flag:
    full: dict[str, object] = {
        "status": "active",
        "deadline": date(2027, 6, 30),
        "met": False,
        "today": date(2027, 1, 1),
        "nodes": tree,
        "links": links,
    } | kwargs
    flags = key_result_flags(**full)  # type: ignore[arg-type]
    assert len(flags) == 1 and flags[0].code == "no_usable_theme"
    return flags[0]


def test_no_links_gives_the_no_links_reason() -> None:
    flag = _kr_flags({}, [])
    assert flag.reasons[0].state == "no_links"
    assert flag.reasons[0].project_id is None
    assert flag.actions == ("link_theme", "create_theme")


def test_an_active_link_to_a_non_usable_theme_names_the_state() -> None:
    tree = nodes(
        ProjectNode("o", None, T, orphaned=True),
        ProjectNode("x", None, X),
        ProjectNode("m", None, M),
        ProjectNode("u", None, None),
    )
    flag = _kr_flags(tree, [LinkView(name="Open source", key="o", active=True)])
    assert flag.reasons[0].name == "Open source" and flag.reasons[0].state == "orphaned"
    flag = _kr_flags(tree, [LinkView(name="Noise", key="x", active=True)])
    assert flag.reasons[0].state == "ignored"
    flag = _kr_flags(tree, [LinkView(name="Ship", key="m", active=True)])
    assert flag.reasons[0].state == "relabelled" and flag.reasons[0].label is ProjectLabel.MILESTONE
    flag = _kr_flags(tree, [LinkView(name="Unsorted", key="u", active=True)])
    assert flag.reasons[0].state == "unclassified"


def test_an_ended_link_does_not_produce_a_reason() -> None:
    tree = nodes(ProjectNode("o", None, T, orphaned=True))
    flag = _kr_flags(tree, [LinkView(name="Old", key="o", active=False)])
    assert flag.reasons[0].state == "no_links"


def test_the_overdue_flag_with_its_action() -> None:
    tree = nodes(ProjectNode("t", None, T))
    full: dict[str, object] = {
        "status": "active",
        "deadline": date(2026, 12, 31),
        "met": False,
        "today": date(2027, 1, 1),
        "nodes": tree,
        "links": [LinkView(name="Open source", key="t", active=True)],
    }
    flags = key_result_flags(**full)  # type: ignore[arg-type]
    assert [f.code for f in flags] == ["overdue"]
    assert flags[0].actions == ("update_value",)


def test_flags_never_raise() -> None:
    # A link to a project that is not in the tree, a status of nonsense, no deadline at all.
    flags = key_result_flags(
        status="retired",
        deadline=None,
        met=False,
        today=date(2027, 1, 1),
        nodes={},
        links=[LinkView(name="Gone", key=None, active=True)],
    )
    assert flags == ()


# -- goal progress (display) -------------------------------------------------------------------


def test_goal_progress_is_the_mean_of_the_capped_progresses() -> None:
    assert goal_progress(()) is None
    # Each progress is limited to 0 to 1 before the mean.
    assert goal_progress((-1.0, 2.0)) == 0.5
    assert goal_progress((0.25, 0.75)) == 0.5


# -- the zone aware stamp of a manual value (R-08) ---------------------------------------------


def test_a_manual_value_on_a_past_day_is_stamped_at_noon_in_the_zone() -> None:
    from tefteri.domain.key_results import stamp_manual_value

    zone = timezone(timedelta(hours=2))
    past = stamp_manual_value(date(2026, 1, 1), date(2026, 3, 4), zone)
    assert past.date() == date(2026, 1, 1)
    assert past.hour == 12
    assert past.utcoffset() == timedelta(hours=2)
    today = stamp_manual_value(date.today(), date.today(), UTC)
    assert today.tzinfo is UTC
    assert datetime.now(UTC) - today < timedelta(minutes=1)
