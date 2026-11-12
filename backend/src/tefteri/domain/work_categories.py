"""The rules that put a completed task into a work category (spec 005). Pure functions.

No database and no adapter is used here, so every rule is tested without either. The category of
a task is decided once, when tefteri first sees the task as completed, and is never recomputed
(FR-007). The functions here only decide; ``services.category_recorder`` stores the answer.

The first rule that fits wins (research R-06):

1. The task has no project: off-plan, unsorted (``no_project``).
2. The project, or an ancestor, is ignored: hidden.
3. The project, or an ancestor, is maintenance: maintenance (decision 10: work inside a routine
   project is maintenance).
4. The project is a milestone in the commitment of the completion week: goal-aligned.
5. The project is a milestone that is not committed: off-plan.
6. The project is a theme: off-plan.
7. The project has no label: off-plan, unsorted.
"""

from collections.abc import Sequence
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import NamedTuple

from tefteri.domain.enums import CategoryReason, ProjectLabel, WorkCategory


@dataclass(frozen=True)
class CategoryCounts:
    """Completed tasks per category. ``hidden`` is the ignored count and is not in ``total``."""

    goal_aligned: int = 0
    maintenance: int = 0
    off_plan: int = 0
    hidden: int = 0

    @property
    def total(self) -> int:
        """The tasks of the three work categories. The hidden count is not part of it."""
        return self.goal_aligned + self.maintenance + self.off_plan

    def __add__(self, other: "CategoryCounts") -> "CategoryCounts":
        """Add field by field (a month is the sum of its days)."""
        return CategoryCounts(
            self.goal_aligned + other.goal_aligned,
            self.maintenance + other.maintenance,
            self.off_plan + other.off_plan,
            self.hidden + other.hidden,
        )

    def of(self, category: WorkCategory) -> int:
        """Return the count of one category."""
        return int(getattr(self, category.value))

    @classmethod
    def one(cls, category: WorkCategory, n: int = 1) -> "CategoryCounts":
        """Return counts with ``n`` tasks in ``category`` and none elsewhere."""
        return cls(**{category.value: n})


@dataclass(frozen=True)
class LabelEntry:
    """One entry of the label history of a project (``None`` is back to unclassified)."""

    label: ProjectLabel | None
    from_at: datetime


@dataclass(frozen=True)
class ProjectContext:
    """What the rules need to know about the project of a task on its completion day."""

    has_project: bool
    label_on_day: ProjectLabel | None = None
    ancestor_labels_on_day: Sequence[ProjectLabel | None] = ()


@dataclass(frozen=True)
class Decision:
    """The result of the rules."""

    category: WorkCategory
    reason: CategoryReason
    unsorted: bool = False


class Percentages(NamedTuple):
    """Whole percentages of the three work categories. They add up to 100, or are all 0."""

    goal_aligned: int
    maintenance: int
    off_plan: int


def _utc(value: datetime) -> datetime:
    return value if value.tzinfo else value.replace(tzinfo=UTC)


def label_on(entries: Sequence[LabelEntry], day_end: datetime) -> ProjectLabel | None:
    """Return the label a project had on a day: the entry with the latest start not after the end.

    When every entry starts later, the oldest entry is used (spec 005, US5 scenario 10). No entry
    means unclassified. Two entries with the same start: the last one in ``entries`` wins.
    """
    if not entries:
        return None
    limit = _utc(day_end)
    best: LabelEntry | None = None
    for entry in entries:
        if _utc(entry.from_at) <= limit and (
            best is None or _utc(entry.from_at) >= _utc(best.from_at)
        ):
            best = entry
    if best is None:
        best = entries[0]
        for entry in entries:
            if _utc(entry.from_at) < _utc(best.from_at):
                best = entry
    return best.label


def categorize(context: ProjectContext, committed: bool) -> Decision:
    """Decide the category of a completed task. ``committed``: its project is in the commitment."""
    if not context.has_project:
        return Decision(WorkCategory.OFF_PLAN, CategoryReason.NO_PROJECT, True)
    own = context.label_on_day
    ancestors = context.ancestor_labels_on_day
    if own is ProjectLabel.IGNORED:
        return Decision(WorkCategory.HIDDEN, CategoryReason.IGNORED)
    if ProjectLabel.IGNORED in ancestors:
        return Decision(WorkCategory.HIDDEN, CategoryReason.IGNORED_ANCESTOR)
    if own is ProjectLabel.MAINTENANCE:
        return Decision(WorkCategory.MAINTENANCE, CategoryReason.MAINTENANCE_LABEL)
    if ProjectLabel.MAINTENANCE in ancestors:
        return Decision(WorkCategory.MAINTENANCE, CategoryReason.INSIDE_ROUTINE)
    if own is ProjectLabel.MILESTONE:
        if committed:
            return Decision(WorkCategory.GOAL_ALIGNED, CategoryReason.COMMITTED_MILESTONE)
        return Decision(WorkCategory.OFF_PLAN, CategoryReason.MILESTONE_NOT_COMMITTED)
    if own is ProjectLabel.THEME:
        return Decision(WorkCategory.OFF_PLAN, CategoryReason.THEME)
    return Decision(WorkCategory.OFF_PLAN, CategoryReason.UNCLASSIFIED, True)


def percentages(counts: CategoryCounts) -> Percentages:
    """Return whole percentages of the three work categories that add up to 100.

    The largest remainder method; a tie goes to goal-aligned, then maintenance, then off-plan.
    The hidden count never enters. A total of zero gives zeros. Percentages are never stored.
    """
    values = (counts.goal_aligned, counts.maintenance, counts.off_plan)
    total = sum(values)
    if total == 0:
        return Percentages(0, 0, 0)
    floors = [100 * v // total for v in values]
    remainders = [100 * v % total for v in values]
    order = sorted(range(3), key=lambda i: (-remainders[i], i))
    for i in order[: 100 - sum(floors)]:
        floors[i] += 1
    return Percentages(floors[0], floors[1], floors[2])
