"""Which capabilities a task app must have (spec 003, FR-015 and FR-016)."""

from collections.abc import Collection
from dataclasses import dataclass

from tefteri.domain.enums import Capability

REQUIRED_TASK_CAPABILITIES: tuple[Capability, ...] = (
    Capability.SUBPROJECTS,
    Capability.ARCHIVE_PROJECTS,
    Capability.PROJECT_TREE,
    Capability.STABLE_PROJECT_IDS,
    Capability.CREATE_TASKS,
    Capability.COMPLETION_TIMES,
)
"""Without these a task app cannot be connected. The order is the order of the messages."""

OPTIONAL_PROJECT_CAPABILITIES: tuple[Capability, ...] = (
    Capability.RENAME_PROJECTS,
    Capability.RESTORE_PROJECTS,
)
"""Without these only the feature that needs them is hidden."""


def missing_required(capabilities: Collection[Capability]) -> list[Capability]:
    """Return the required task capabilities that ``capabilities`` lacks, in a stable order."""
    have = set(capabilities)
    return [c for c in REQUIRED_TASK_CAPABILITIES if c not in have]


DESCRIPTIONS: dict[Capability, str] = {
    Capability.SUBPROJECTS: "nested projects",
    Capability.ARCHIVE_PROJECTS: "archiving projects",
    Capability.PROJECT_TREE: "reading the whole project tree",
    Capability.STABLE_PROJECT_IDS: "stable project ids",
    Capability.CREATE_TASKS: "creating tasks",
    Capability.COMPLETION_TIMES: "task completion times",
}
"""Plain words for each required capability, for the message that names what is missing."""


def missing_message(missing: Collection[Capability]) -> str:
    """Say which required capabilities a task app lacks, naming each one."""
    names = ", ".join(f"{DESCRIPTIONS.get(c, c.value)} ({c.value})" for c in missing)
    return f"Tefteri cannot use this task app. It does not support: {names}."


@dataclass(frozen=True)
class CapabilityReport:
    """What a connection can do, for the client."""

    missing_required: list[str]
    optional: dict[str, bool]


def report_for(capabilities: Collection[Capability]) -> CapabilityReport:
    """Build the report of a task app: the required capabilities it lacks and its optional flags."""
    return CapabilityReport(
        [c.value for c in missing_required(capabilities)],
        {
            "rename": Capability.RENAME_PROJECTS in capabilities,
            "restore": Capability.RESTORE_PROJECTS in capabilities,
        },
    )
