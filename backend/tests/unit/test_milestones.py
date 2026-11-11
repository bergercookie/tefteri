"""The pure rules of weekly milestones (spec 004): commit kind, completion, nudge, decisions."""

from datetime import UTC, date, datetime, timedelta
from uuid import uuid4

from tefteri.domain.classification import ProjectNode
from tefteri.domain.enums import MilestoneState, ProjectLabel, ReviewDecision
from tefteri.domain.milestones import (
    MILESTONE_CAP,
    CommitKind,
    RolloverEvent,
    TaskFacts,
    close_options,
    commit_kind,
    completion,
    decision_of,
    focus_share,
    needs_rescope,
    outside_focus,
    over_cap,
)
from tefteri.domain.periods import month_of_week

T, M, R, X = (
    ProjectLabel.THEME,
    ProjectLabel.MILESTONE,
    ProjectLabel.MAINTENANCE,
    ProjectLabel.IGNORED,
)


def nodes(*items: ProjectNode) -> dict[str, ProjectNode]:
    return {n.key: n for n in items}


# -- commit_kind (FR-001, FR-033) --------------------------------------------------------------


def test_a_milestone_is_offered_as_milestone() -> None:
    tree = nodes(ProjectNode("t", None, T), ProjectNode("m", "t", M))
    assert commit_kind(tree, "m") is CommitKind.MILESTONE


def test_a_milestone_with_subprojects_is_still_a_milestone() -> None:
    tree = nodes(ProjectNode("m", None, M), ProjectNode("c", "m", None))
    assert commit_kind(tree, "m") is CommitKind.MILESTONE


def test_an_unclassified_leaf_is_labelled_then_committed() -> None:
    tree = nodes(
        ProjectNode("a", None, None), ProjectNode("t", None, T), ProjectNode("b", "t", None)
    )
    assert commit_kind(tree, "a") is CommitKind.LABEL_THEN_COMMIT  # a top-level leaf
    assert commit_kind(tree, "b") is CommitKind.LABEL_THEN_COMMIT  # a nested leaf


def test_a_theme_and_an_unclassified_project_with_subprojects_are_not_offered() -> None:
    tree = nodes(
        ProjectNode("t", None, T),
        ProjectNode("u", None, None),
        ProjectNode("c", "u", None),
        ProjectNode("n", "t", None),
        ProjectNode("n2", "n", None),
    )
    assert commit_kind(tree, "t") is None
    assert commit_kind(tree, "u") is None  # a top-level project with subprojects
    assert commit_kind(tree, "n") is None  # a nested one with subprojects too


def test_an_orphaned_subproject_does_not_make_a_leaf_a_parent() -> None:
    tree = nodes(ProjectNode("u", None, None), ProjectNode("c", "u", None, orphaned=True))
    assert commit_kind(tree, "u") is CommitKind.LABEL_THEN_COMMIT


def test_maintenance_ignored_orphaned_and_routine_work_are_not_offered() -> None:
    tree = nodes(
        ProjectNode("r", None, R),
        ProjectNode("in_r", "r", M),
        ProjectNode("in_r2", "r", None),
        ProjectNode("x", None, X),
        ProjectNode("in_x", "x", M),
        ProjectNode("gone", None, M, orphaned=True),
    )
    for key in ("r", "in_r", "in_r2", "x", "in_x", "gone"):
        assert commit_kind(tree, key) is None


def test_a_parked_milestone_is_offered_and_a_closed_or_done_one_is_not() -> None:
    tree = nodes(ProjectNode("m", None, M))
    assert commit_kind(tree, "m", MilestoneState.PARKED) is CommitKind.MILESTONE
    assert commit_kind(tree, "m", MilestoneState.ACTIVE) is CommitKind.MILESTONE
    assert commit_kind(tree, "m", MilestoneState.CLOSED) is None
    assert commit_kind(tree, "m", MilestoneState.DONE) is None


# -- decision_of (FR-031) ----------------------------------------------------------------------


def test_a_stored_decision_wins() -> None:
    for d in ReviewDecision:
        assert decision_of(d.value, None) is d
    assert decision_of("park", "carry") is ReviewDecision.PARK


def test_the_old_choices_map_to_the_new_decisions() -> None:
    assert decision_of(None, "carry") is ReviewDecision.RECOMMIT
    assert decision_of(None, "backlog") is ReviewDecision.PARK
    assert decision_of(None, None) is None


def test_an_unknown_value_is_not_mapped() -> None:
    assert decision_of("later", None) is None
    assert decision_of(None, "x") is None


# -- needs_rescope (FR-030) --------------------------------------------------------------------

START = datetime(2030, 1, 7, tzinfo=UTC)


def events(*expected: bool) -> list[RolloverEvent]:
    return [RolloverEvent(e, START + timedelta(days=7 * n), str(n)) for n, e in enumerate(expected)]


def test_no_event_and_one_event_give_no_nudge() -> None:
    assert needs_rescope([]) is False
    assert needs_rescope(events(False)) is False


def test_two_unmarked_events_in_a_row_give_a_nudge() -> None:
    assert needs_rescope(events(False, False)) is True
    assert needs_rescope(events(True, False, False)) is True


def test_a_marked_event_ends_the_run() -> None:
    assert needs_rescope(events(False, True)) is False
    assert needs_rescope(events(True, False)) is False
    assert needs_rescope(events(False, True, False)) is False  # scenario 7
    assert needs_rescope(events(False, False, True)) is False


def test_events_are_ordered_by_time_then_id() -> None:
    a = RolloverEvent(True, START, "b")
    b = RolloverEvent(False, START, "c")
    c = RolloverEvent(False, START, "a")
    # Same time: "a" (unmarked), "b" (marked), "c" (unmarked) -> the last two are not both unmarked.
    assert needs_rescope([a, b, c]) is False
    # Given out of order, the newest two are still found.
    late = RolloverEvent(False, START + timedelta(days=7), "z")
    early = RolloverEvent(False, START, "y")
    assert needs_rescope([late, early]) is True


# -- completion (FR-017, SC-011) ---------------------------------------------------------------


def test_all_tasks_closed_is_done_on_the_latest_completion_day() -> None:
    result = completion(
        [
            TaskFacts(True, False, date(2030, 3, 5)),
            TaskFacts(True, False, date(2030, 3, 7)),
        ]
    )
    assert (result.done, result.done_on, result.dropped_note) == (True, date(2030, 3, 7), False)


def test_closed_and_dropped_is_done_with_a_note() -> None:
    result = completion([TaskFacts(True, False, date(2030, 3, 5)), TaskFacts(False, True, None)])
    assert (result.done, result.done_on, result.dropped_note) == (True, date(2030, 3, 5), True)


def test_only_dropped_tasks_or_no_task_is_never_done() -> None:
    assert completion([TaskFacts(False, True, None)]).done is False
    assert completion([]).done is False
    assert completion([]).done_on is None


def test_an_open_task_blocks_completion() -> None:
    assert (
        completion([TaskFacts(True, False, date(2030, 3, 5)), TaskFacts(False, False, None)]).done
        is False
    )


def test_closed_tasks_without_a_completion_day_are_done_with_no_date() -> None:
    result = completion([TaskFacts(True, False, None)])
    assert (result.done, result.done_on) == (True, None)


# -- close_options (FR-027) --------------------------------------------------------------------


def test_close_is_available_when_everything_is_there() -> None:
    options = close_options(True, True, True)
    assert (options.available, options.reason) == (True, None)


def test_close_reasons_come_in_a_fixed_order() -> None:
    assert close_options(False, False, False).reason == "no_theme"
    assert close_options(True, False, False).reason == "theme_unusable"
    assert close_options(True, True, False).reason == "not_supported"
    assert close_options(False, True, True).available is False


# -- cap and focus (FR-005, FR-007, FR-021, FR-038) --------------------------------------------


def test_the_cap_warns_over_three() -> None:
    assert MILESTONE_CAP == 3
    assert [over_cap(n) for n in (0, 3, 4)] == [False, False, True]
    assert over_cap(5, cap=5) is False and over_cap(6, cap=5) is True


def test_outside_focus_needs_focus_data() -> None:
    a, b = uuid4(), uuid4()
    assert outside_focus(a, None) is False
    assert outside_focus(None, None) is False
    assert outside_focus(a, {a}) is False
    assert outside_focus(b, {a}) is True
    assert outside_focus(None, {a}) is True


def test_focus_share_is_the_share_of_completed_tasks_under_focus() -> None:
    a, b = uuid4(), uuid4()
    assert focus_share({a: 3, b: 1}, {a}) == 0.75
    assert focus_share({None: 2, a: 2}, {a}) == 0.5
    assert focus_share({a: 3}, None) is None
    assert focus_share({}, {a}) is None
    assert focus_share({a: 0}, {a}) is None


def test_the_month_of_a_week_is_the_month_of_its_monday() -> None:
    assert month_of_week(date(2030, 4, 29)) == date(2030, 4, 1)  # ends in May, Monday in April
    assert month_of_week(date(2030, 3, 4)) == date(2030, 3, 1)
