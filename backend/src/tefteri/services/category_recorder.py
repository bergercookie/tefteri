"""Record the work category of a completed task, once (spec 005, FR-007).

The recorder runs in two places: after a sync (``record_new``, for every task that is done and
has no row yet) and when the user completes a task in tefteri (``record_completed``). Both use
the same rules (``domain.work_categories.categorize``). A row is written when a task is first
seen as completed. It is never edited afterwards: the only change is a replacement in place when
a reopened task is completed again (a new completion time). A relabel, a changed commitment, a
rename or a move never changes a stored row.
"""

import logging
import uuid
from collections import defaultdict
from collections.abc import Callable, Mapping
from dataclasses import dataclass, field
from datetime import UTC, date, datetime, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.connection import SourceContainer
from tefteri.db.models.project_label import ProjectLabel as ProjectLabelRow
from tefteri.db.models.project_label import ProjectLabelHistory
from tefteri.db.models.task import Task
from tefteri.db.models.task_category import TaskCategory
from tefteri.db.models.user import User
from tefteri.db.models.weekly import WeeklyPlan
from tefteri.domain.enums import ProjectLabel, SyncState, WorkCategory
from tefteri.domain.periods import PeriodType, period_start
from tefteri.domain.timeutil import day_bounds
from tefteri.domain.work_categories import (
    Decision,
    LabelEntry,
    ProjectContext,
    categorize,
    label_on,
)
from tefteri.services.commitments import CommitmentProvider

logger = logging.getLogger(__name__)

BATCH_SIZE = 500
"""Rows are written and flushed in batches of this many tasks."""
MAX_DEPTH = 64
"""No real project tree is deeper. It also stops a loop in bad parent links."""


def _utc(value: datetime) -> datetime:
    return (value if value.tzinfo else value.replace(tzinfo=UTC)).astimezone(UTC)


def _label(value: str | None) -> ProjectLabel | None:
    return ProjectLabel(value) if value else None


@dataclass
class _World:
    """What one run reads once: the projects, their label history and the user's time zone."""

    tz: str
    containers: dict[uuid.UUID, tuple[uuid.UUID, str]]
    """Container id to (connection id, remote id)."""
    rows: dict[tuple[uuid.UUID, str], ProjectLabelRow]
    history: dict[uuid.UUID, list[LabelEntry]]
    committed: dict[date, set[uuid.UUID] | None] = field(default_factory=dict)
    plans: dict[date, uuid.UUID | None] = field(default_factory=dict)


class CategoryRecorder:
    """Decide and store the category of completed tasks."""

    def __init__(
        self,
        commitments: CommitmentProvider,
        clock: Callable[[], datetime] = lambda: datetime.now(UTC),
    ) -> None:
        """Read the weekly commitment through ``commitments``; ``clock`` is injectable."""
        self._commitments = commitments
        self._clock = clock

    async def record_new(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        previously_open: Mapping[uuid.UUID, uuid.UUID | None],
    ) -> int:
        """Record every done task of the user that has no row for its completion time.

        ``previously_open`` maps the id of each task that the cache held as open before the sync
        to the id of its container then: the project that decides when the task moved and was
        completed between two syncs (research R-03). A task that is not in it uses its current
        project. Returns the number of rows written or replaced.
        """
        found = (
            await db.execute(
                select(Task, TaskCategory)
                .outerjoin(TaskCategory, TaskCategory.task_id == Task.id)
                .where(
                    Task.user_id == user_id,
                    Task.status == "done",
                    Task.completed_at.is_not(None),
                    Task.sync_state != SyncState.DELETED_REMOTELY.value,
                    or_(TaskCategory.id.is_(None), TaskCategory.completed_at != Task.completed_at),
                )
            )
        ).all()
        todo: list[tuple[Task, TaskCategory | None]] = [(t, c) for t, c in found]
        todo += await self._reopened(db, user_id, previously_open, {t.id for t, _ in found})
        if not todo:
            return 0
        world = await self._load(db, user_id)
        written = 0
        for start in range(0, len(todo), BATCH_SIZE):
            for task, row in todo[start : start + BATCH_SIZE]:
                written += await self._record(
                    db, user_id, world, task, row, "sync", previously_open
                )
            await db.flush()
        return written

    async def _reopened(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        previously_open: Mapping[uuid.UUID, uuid.UUID | None],
        skip: set[uuid.UUID],
    ) -> list[tuple[Task, TaskCategory]]:
        """Find done tasks that have a row, that the cache held as open before this sync.

        The cache keeps completion times in whole seconds, so a task that was reopened and
        completed again within the same second has the completion time of its row. Seeing it
        open in between is what shows that this is a new completion (research R-08).
        """
        if not previously_open:
            return []
        with_row = (
            await db.execute(
                select(Task.id)
                .join(TaskCategory, TaskCategory.task_id == Task.id)
                .where(
                    Task.user_id == user_id,
                    Task.status == "done",
                    Task.completed_at.is_not(None),
                    Task.sync_state != SyncState.DELETED_REMOTELY.value,
                )
            )
        ).scalars()
        ids = [i for i in with_row if i in previously_open and i not in skip]
        found: list[tuple[Task, TaskCategory]] = []
        for start in range(0, len(ids), BATCH_SIZE):
            rows = await db.execute(
                select(Task, TaskCategory)
                .join(TaskCategory, TaskCategory.task_id == Task.id)
                .where(Task.id.in_(ids[start : start + BATCH_SIZE]))
            )
            found.extend((t, c) for t, c in rows.all())
        return found

    async def record_completed(self, db: AsyncSession, user_id: uuid.UUID, task: Task) -> None:
        """Record a task that the user completed in tefteri, with the project tefteri knows."""
        if task.status != "done" or task.completed_at is None:
            return
        await db.flush()
        row = (
            await db.execute(select(TaskCategory).where(TaskCategory.task_id == task.id))
        ).scalar_one_or_none()
        if row is not None and _utc(row.completed_at) == _utc(task.completed_at):
            return
        world = await self._load(db, user_id)
        await self._record(db, user_id, world, task, row, "app", {})
        await db.flush()

    async def _load(self, db: AsyncSession, user_id: uuid.UUID) -> _World:
        user = await db.get(User, user_id)
        containers = {
            c.id: (c.connection_id, c.remote_id)
            for c in (
                await db.execute(select(SourceContainer).where(SourceContainer.user_id == user_id))
            ).scalars()
        }
        rows = {
            (r.connection_id, r.remote_id): r
            for r in (
                await db.execute(select(ProjectLabelRow).where(ProjectLabelRow.user_id == user_id))
            ).scalars()
        }
        history: dict[uuid.UUID, list[LabelEntry]] = defaultdict(list)
        for entry in (
            await db.execute(
                select(ProjectLabelHistory)
                .join(ProjectLabelRow, ProjectLabelRow.id == ProjectLabelHistory.project_id)
                .where(ProjectLabelRow.user_id == user_id)
                .order_by(ProjectLabelHistory.from_at)
            )
        ).scalars():
            history[entry.project_id].append(LabelEntry(_label(entry.label), entry.from_at))
        return _World(user.timezone if user is not None else "UTC", containers, rows, history)

    def _project_of(
        self,
        world: _World,
        task: Task,
        previously_open: Mapping[uuid.UUID, uuid.UUID | None],
    ) -> ProjectLabelRow | None:
        container_id = previously_open.get(task.id) or task.container_id
        found = world.containers.get(container_id) if container_id is not None else None
        return world.rows.get(found) if found is not None else None

    def _context(
        self, world: _World, project: ProjectLabelRow, day_end: datetime
    ) -> ProjectContext:
        own = label_on(world.history.get(project.id, []), day_end)
        ancestors: list[ProjectLabel | None] = []
        seen = {project.remote_id}
        parent = project.parent_remote_id
        while parent is not None and parent not in seen and len(ancestors) < MAX_DEPTH:
            seen.add(parent)
            row = world.rows.get((project.connection_id, parent))
            if row is None:
                break
            ancestors.append(label_on(world.history.get(row.id, []), day_end))
            parent = row.parent_remote_id
        return ProjectContext(True, own, ancestors)

    async def _record(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        world: _World,
        task: Task,
        row: TaskCategory | None,
        via: str,
        previously_open: Mapping[uuid.UUID, uuid.UUID | None],
    ) -> int:
        assert task.completed_at is not None  # noqa: S101 - callers select done tasks with a time
        completed_at = _utc(task.completed_at)
        day = completed_at.astimezone(ZoneInfo(world.tz)).date()
        monday = period_start(PeriodType.WEEK, day)
        if monday not in world.committed:
            world.committed[monday] = await self._commitments.committed_projects(
                db, user_id, monday
            )
        committed = world.committed[monday]
        if committed is None:
            return 0  # the weekly commitment cannot be read: record nothing, guess nothing
        project = self._project_of(world, task, previously_open)
        if project is None:
            decision = categorize(ProjectContext(False), False)
            name = label = None
            project_id = None
        else:
            day_end = day_bounds(day, world.tz)[1] - timedelta(microseconds=1)
            context = self._context(world, project, day_end)
            decision = categorize(context, project.id in committed)
            name, label, project_id = project.name, context.label_on_day, project.id
        plan_id = await self._plan_of(db, user_id, world, monday, decision)
        values = {
            "completed_at": completed_at,
            "completed_on": day,
            "category": decision.category.value,
            "reason": decision.reason.value,
            "unsorted": decision.unsorted,
            "project_id": project_id,
            "project_name": name,
            "project_label": label.value if label is not None else None,
            "plan_id": plan_id,
            "decided_via": via,
            "decided_at": self._clock(),
        }
        if row is None:
            db.add(TaskCategory(user_id=user_id, task_id=task.id, **values))
        else:
            for key, value in values.items():  # a new completion time: replace in place
                setattr(row, key, value)
        return 1

    async def _plan_of(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        world: _World,
        monday: date,
        decision: Decision,
    ) -> uuid.UUID | None:
        if decision.category is not WorkCategory.GOAL_ALIGNED:
            return None
        if monday not in world.plans:
            world.plans[monday] = (
                await db.execute(
                    select(WeeklyPlan.id).where(
                        WeeklyPlan.user_id == user_id,
                        WeeklyPlan.week_start == monday,
                        WeeklyPlan.status == "committed",
                    )
                )
            ).scalar_one_or_none()
        return world.plans[monday]
