"""The required capabilities of a task app (spec 003, FR-015, FR-016)."""

from tefteri.domain.capabilities import REQUIRED_TASK_CAPABILITIES, missing_required, report_for
from tefteri.domain.enums import Capability


def test_nothing_is_missing_when_all_required_capabilities_are_there() -> None:
    assert missing_required(set(Capability)) == []


def test_missing_capabilities_are_named_in_a_stable_order() -> None:
    have = set(Capability) - {Capability.COMPLETION_TIMES, Capability.SUBPROJECTS}
    assert missing_required(have) == [Capability.SUBPROJECTS, Capability.COMPLETION_TIMES]
    assert missing_required(set()) == list(REQUIRED_TASK_CAPABILITIES)


def test_an_optional_capability_is_never_required() -> None:
    have = set(REQUIRED_TASK_CAPABILITIES)
    assert missing_required(have) == []
    assert Capability.RENAME_PROJECTS not in REQUIRED_TASK_CAPABILITIES
    assert Capability.RESTORE_PROJECTS not in REQUIRED_TASK_CAPABILITIES


def test_moving_tasks_is_optional_and_reported() -> None:
    assert Capability.MOVE_TASKS not in REQUIRED_TASK_CAPABILITIES
    have = set(Capability)
    assert report_for(have).optional == {"rename": True, "restore": True, "move_tasks": True}
    without = have - {Capability.MOVE_TASKS}
    report = report_for(without)
    assert report.optional["move_tasks"] is False
    assert report.missing_required == []  # a task app without it is not refused
