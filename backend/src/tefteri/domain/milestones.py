"""The rules of weekly milestones (spec 004). Pure functions: no database, no adapter.

A *milestone project* is a project labelled ``milestone`` (spec 003). These functions decide
which projects the weekly picker offers, when a milestone is done, when it needs to be
re-scoped, what the old look-back choices mean now, and when the close option is hidden. They
use the types of ``domain.classification`` and do not restate its rules. Nothing here names a
task app.
"""

from collections.abc import Collection, Mapping, Sequence
from dataclasses import dataclass
from datetime import date, datetime
from enum import StrEnum
from typing import Literal
from uuid import UUID

from tefteri.domain.classification import ProjectNode, is_weekly_eligible
from tefteri.domain.enums import MilestoneState, ProjectLabel, ReviewDecision

MILESTONE_CAP = 3
"""A week usually holds this many milestones. More is allowed and shows a warning."""

NUDGE_AFTER = 2
"""This many unmarked rollovers in a row make the nudge."""

CloseReason = Literal["no_theme", "theme_unusable", "not_supported"]


class CommitKind(StrEnum):
    """How a project can enter a weekly plan."""

    MILESTONE = "milestone"
    """It is a milestone: add it as it is."""
    LABEL_THEN_COMMIT = "label_then_commit"
    """It has no label and no subproject: label it milestone, then add it."""


def commit_kind(
    nodes: Mapping[str, ProjectNode], key: str, state: MilestoneState | None = None
) -> CommitKind | None:
    """Return how the picker offers a project, or ``None`` when it must not offer it.

    Only a weekly-eligible project is offered (spec 003): not orphaned, not ignored, not
    maintenance, not inside a routine or an ignored project. A project with the stored label
    ``milestone`` is offered when its ``state`` is not ``closed`` or ``done``. A project with no
    stored label is offered when it has no live subproject: choosing it labels it milestone. A
    theme, and a project with no label that has subprojects, are never offered.
    """
    if not is_weekly_eligible(nodes, key):
        return None
    if state in (MilestoneState.CLOSED, MilestoneState.DONE):
        return None
    label = nodes[key].label
    if label is ProjectLabel.MILESTONE:
        return CommitKind.MILESTONE
    if label is None and not any(
        n.parent_key == key and not n.orphaned and n.key != key for n in nodes.values()
    ):
        return CommitKind.LABEL_THEN_COMMIT
    return None


def decision_of(decision: str | None, leftover_action: str | None) -> ReviewDecision | None:
    """Return the decision of a plan entry under the new names (FR-031).

    A stored decision wins. An entry from before spec 004 has only ``leftover_action``: ``carry``
    means ``recommit`` and ``backlog`` means ``park``. Nothing stored gives ``None``. A value that
    is not known is not mapped.
    """
    if decision is not None:
        try:
            return ReviewDecision(decision)
        except ValueError:
            return None
    return {"carry": ReviewDecision.RECOMMIT, "backlog": ReviewDecision.PARK}.get(
        leftover_action or ""
    )


@dataclass(frozen=True)
class RolloverEvent:
    """One recommit of a milestone, as far as the nudge cares."""

    expected: bool
    """The user marked this event as expected ("this was bigger than a week")."""
    created_at: datetime
    id: str
    """Breaks a tie between two events of the same instant."""


def needs_rescope(events: Sequence[RolloverEvent]) -> bool:
    """Return whether a milestone should be shrunk, split or closed (FR-030).

    True when its two newest rollover events are both unmarked. Events are ordered by
    ``created_at`` and then ``id``. A marked event ends the run of unmarked ones.
    """
    newest = sorted(events, key=lambda e: (e.created_at, e.id))[-NUDGE_AFTER:]
    return len(newest) == NUDGE_AFTER and not any(e.expected for e in newest)


@dataclass(frozen=True)
class TaskFacts:
    """What the completion rule needs to know about one task of a milestone."""

    done: bool
    """The task app says it is completed."""
    dropped: bool
    """The task app no longer lists it and it was not completed (a dropped task)."""
    completed_on: date | None
    """The local day it was completed, if the app says."""


@dataclass(frozen=True)
class Completion:
    """The answer of ``completion``."""

    done: bool
    done_on: date | None
    dropped_note: bool
    """Some tasks were dropped: the screen says that the remaining tasks were dropped."""


def completion(tasks: Sequence[TaskFacts]) -> Completion:
    """Say whether a milestone is done by itself (FR-017, SC-011).

    It is done when no task is open (neither closed nor dropped) and at least one task was
    closed. A milestone with no task, or with only dropped tasks, is never done by itself. The
    done day is the latest completion day of the closed tasks.
    """
    closed = [t for t in tasks if t.done]
    dropped = [t for t in tasks if not t.done and t.dropped]
    open_tasks = len(tasks) - len(closed) - len(dropped)
    if open_tasks or not closed:
        return Completion(False, None, bool(dropped))
    days = [t.completed_on for t in closed if t.completed_on is not None]
    return Completion(True, max(days) if days else None, bool(dropped))


@dataclass(frozen=True)
class CloseOptions:
    """Whether close and return is offered for a milestone, and why not."""

    available: bool
    reason: CloseReason | None


def close_options(has_theme: bool, theme_usable: bool, can_move: bool) -> CloseOptions:
    """Say whether the tasks of a milestone can go back to its theme (FR-027).

    The reason comes in a fixed order: no theme, a theme that cannot take tasks (ignored or
    orphaned), a task app that cannot move tasks.
    """
    if not has_theme:
        return CloseOptions(False, "no_theme")
    if not theme_usable:
        return CloseOptions(False, "theme_unusable")
    if not can_move:
        return CloseOptions(False, "not_supported")
    return CloseOptions(True, None)


def over_cap(count: int, cap: int = MILESTONE_CAP) -> bool:
    """Return whether a week holds more milestones than the cap. It warns; it never blocks."""
    return count > cap


def outside_focus(theme_id: UUID | None, focus: Collection[UUID] | None) -> bool:
    """Return whether a milestone is outside the focus of the month (FR-007).

    Without focus data (``None``) nothing is outside focus. A milestone with no theme is outside
    a focus that exists.
    """
    if focus is None:
        return False
    return theme_id is None or theme_id not in focus


def focus_share(
    done_by_theme: Mapping[UUID | None, int], focus: Collection[UUID] | None
) -> float | None:
    """Return the share of completed committed tasks that sit under a focus theme (FR-021).

    ``None`` when there is no focus data or no completed task, so no ratio is shown.
    """
    total = sum(done_by_theme.values())
    if focus is None or total == 0:
        return None
    return (
        sum(n for theme, n in done_by_theme.items() if theme is not None and theme in focus) / total
    )
