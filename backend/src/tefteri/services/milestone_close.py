"""Close a milestone and return its open tasks to the parent theme, and undo it (spec 004).

Closing moves the open tasks one at a time, with the task app first and tefteri's copy after
each answer. Every success is written to a log (``MilestoneClosure``), so a failure part way
leaves the milestone unclosed, says which tasks moved, and a second call finishes only the rest.
Reopening moves back the tasks that are still where the close put them and are unchanged.
"""

import uuid
from dataclasses import dataclass, field
from datetime import datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.connection import Connection, SourceContainer
from tefteri.db.models.milestone import Milestone, MilestoneClosure
from tefteri.db.models.project_label import ProjectLabel as ProjectLabelRow
from tefteri.db.models.task import Task
from tefteri.domain.enums import Capability, MilestoneState, SyncState
from tefteri.domain.errors import NotSupported
from tefteri.services.errors import BackendProblem, Invalid, guard
from tefteri.services.milestones import UNFINISHED, MilestoneService
from tefteri.services.project_labels import ThemeRef, container_of, tree_of
from tefteri.services.tasks import TaskService


@dataclass(frozen=True)
class ClosePreview:
    """What a close would do, for the confirmation (FR-026)."""

    open_tasks: int
    theme: ThemeRef
    message: str


@dataclass(frozen=True)
class CloseResult:
    """The result of a close that worked."""

    milestone: Milestone
    moved: int
    closure: MilestoneClosure


@dataclass(frozen=True)
class NotMovedBack:
    """A task that a reopen could not move back, and why."""

    task_id: uuid.UUID
    title: str
    reason: str
    """``changed`` (edited since), ``moved`` (moved again), ``missing`` (gone) or ``failed``."""


@dataclass
class ReopenResult:
    """The result of a reopen. A task that did not move back never fails it (FR-037)."""

    milestone: Milestone
    moved_back: int = 0
    not_moved_back: list[NotMovedBack] = field(default_factory=list)


@dataclass(frozen=True)
class _Plan:
    project: ProjectLabelRow
    theme: ThemeRef
    theme_container: SourceContainer
    connection: Connection
    source: SourceContainer


class MilestoneCloseService:
    """Close and return tasks, and reopen."""

    def __init__(self, tasks: TaskService, milestones: MilestoneService) -> None:
        """Use ``tasks`` to move tasks and ``milestones`` for the rows."""
        self._tasks = tasks
        self._milestones = milestones

    # -- checks -------------------------------------------------------------------------------

    async def _plan(self, db: AsyncSession, user_id: uuid.UUID, milestone: Milestone) -> _Plan:
        """Check that the milestone can be closed and say where its tasks go."""
        if milestone.state not in UNFINISHED:
            raise Invalid("This milestone is done or closed already.", code="not_unfinished")
        project = await db.get(ProjectLabelRow, milestone.project_id)
        assert project is not None  # noqa: S101 - the row hangs on its project
        connection = await db.get(Connection, project.connection_id)
        source = await container_of(db, project)
        if project.orphaned_reason is not None or connection is None or source is None:
            raise Invalid("This project is not in your task app any more.")
        tree = await tree_of(db, user_id, project.connection_id)
        theme = tree.theme_of(str(project.id)) if tree else None
        can_move = await self._milestones.can_move_tasks(db, connection)
        options = await self._milestones.close_availability(db, project, theme, can_move=can_move)
        if options.reason == "no_theme" or theme is None:
            raise Invalid(
                "There is no theme to return the tasks to. Label a project as theme first.",
                code="no_theme",
            )
        theme_row = await db.get(ProjectLabelRow, theme.id)
        theme_container = await container_of(db, theme_row) if theme_row else None
        if options.reason == "theme_unusable" or theme_container is None:
            raise Invalid(
                f"The theme {theme.name} is ignored or not in your task app any more.",
                code="no_theme",
            )
        if options.reason == "not_supported":
            await guard(connection, _unsupported())
        return _Plan(project, theme, theme_container, connection, source)

    async def _open_tasks(
        self, db: AsyncSession, user_id: uuid.UUID, container: SourceContainer
    ) -> list[Task]:
        tasks = (
            await db.execute(
                select(Task).where(
                    Task.user_id == user_id,
                    Task.container_id == container.id,
                    Task.status == "open",
                    Task.sync_state != SyncState.DELETED_REMOTELY.value,
                )
            )
        ).scalars()
        return sorted(tasks, key=lambda t: (t.title.casefold(), str(t.id)))

    # -- close ----------------------------------------------------------------------------------

    async def preview(
        self, db: AsyncSession, user_id: uuid.UUID, milestone_id: uuid.UUID
    ) -> ClosePreview:
        """Say how many tasks a close moves and where they go. Nothing is written (FR-026)."""
        milestone = await self._milestones.get(db, user_id, milestone_id)
        plan = await self._plan(db, user_id, milestone)
        count = len(await self._open_tasks(db, user_id, plan.source))
        noun = "open task" if count == 1 else "open tasks"
        return ClosePreview(count, plan.theme, f"{count} {noun} will move to {plan.theme.name}.")

    async def close(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        milestone_id: uuid.UUID,
        now: datetime,
        plan_project_id: uuid.UUID | None = None,
    ) -> CloseResult:
        """Move the open tasks to the parent theme, then close the milestone.

        The milestone is closed only after every move worked. A failure keeps what was moved
        (it is committed), leaves the milestone as it was and raises the problem with the moved
        tasks and the number that remain. A second call moves only the tasks that are left.
        """
        milestone = await self._milestones.get(db, user_id, milestone_id)
        plan = await self._plan(db, user_id, milestone)
        closure = (
            await db.execute(
                select(MilestoneClosure)
                .where(
                    MilestoneClosure.milestone_id == milestone.id,
                    MilestoneClosure.status == "moving",
                )
                .order_by(MilestoneClosure.started_at.desc())
                .limit(1)
            )
        ).scalar_one_or_none()
        if closure is None:
            closure = MilestoneClosure(
                milestone_id=milestone.id,
                plan_project_id=plan_project_id,
                theme_project_id=plan.theme.id,
                theme_name=plan.theme.name,
                status="moving",
                moved=[],
                started_at=now,
            )
            db.add(closure)
            await db.flush()
        todo = await self._open_tasks(db, user_id, plan.source)
        for index, task in enumerate(todo):
            try:
                await self._tasks.move_to_container(db, user_id, task, plan.theme_container)
            except BackendProblem as problem:
                # Keep the moves that worked: the task app has them, so the log must too.
                await db.commit()
                problem.extra = {
                    "moved": await self._moved_list(db, closure),
                    "remaining": len(todo) - index,
                }
                raise
            closure.moved = [
                *closure.moved,
                {
                    "task_id": str(task.id),
                    "remote_id": task.remote_id,
                    "from_remote_project": plan.source.remote_id,
                    "version": task.remote_version,
                },
            ]
            await db.flush()
        closure.status = "closed"
        closure.finished_at = now
        self._milestones.set_state(milestone, MilestoneState.CLOSED, now)
        await db.flush()
        return CloseResult(milestone, len(closure.moved), closure)

    async def _moved_list(
        self, db: AsyncSession, closure: MilestoneClosure
    ) -> list[dict[str, str]]:
        found: list[dict[str, str]] = []
        for entry in closure.moved:
            task = await db.get(Task, uuid.UUID(entry["task_id"]))
            found.append({"task_id": entry["task_id"], "title": task.title if task else ""})
        return found

    # -- reopen -----------------------------------------------------------------------------------

    async def reopen(
        self, db: AsyncSession, user_id: uuid.UUID, milestone_id: uuid.UUID, now: datetime
    ) -> ReopenResult:
        """Make a closed or done milestone active again (FR-037).

        A closed milestone gets back the tasks of its newest close that are still in the theme
        and have not changed since the move. The others are listed with a reason, and the reopen
        still works. A done milestone only loses its done fields.
        """
        milestone = await self._milestones.get(db, user_id, milestone_id)
        result = ReopenResult(milestone)
        if milestone.state == MilestoneState.DONE.value:
            await self._milestones.reopen_done(db, milestone, now)
            return result
        if milestone.state != MilestoneState.CLOSED.value:
            raise Invalid("This milestone is open already.")
        closure = (
            await db.execute(
                select(MilestoneClosure)
                .where(
                    MilestoneClosure.milestone_id == milestone.id,
                    MilestoneClosure.status == "closed",
                )
                .order_by(MilestoneClosure.started_at.desc())
                .limit(1)
            )
        ).scalar_one_or_none()
        if closure is not None:
            theme_container = None
            if closure.theme_project_id is not None:
                theme_row = await db.get(ProjectLabelRow, closure.theme_project_id)
                theme_container = await container_of(db, theme_row) if theme_row else None
            for entry in reversed(closure.moved):
                await self._move_back(db, user_id, entry, theme_container, result)
            closure.status = "reopened"
            closure.reopened_at = now
        self._milestones.set_state(milestone, MilestoneState.ACTIVE, now)
        await db.flush()
        return result

    async def _move_back(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        entry: dict[str, str],
        theme_container: SourceContainer | None,
        result: ReopenResult,
    ) -> None:
        task_id = uuid.UUID(entry["task_id"])
        task = await db.get(Task, task_id)
        if task is None or task.user_id != user_id:
            result.not_moved_back.append(NotMovedBack(task_id, "", "missing"))
            return
        if task.sync_state == SyncState.DELETED_REMOTELY.value:
            result.not_moved_back.append(NotMovedBack(task_id, task.title, "missing"))
            return
        if theme_container is None or task.container_id != theme_container.id:
            result.not_moved_back.append(NotMovedBack(task_id, task.title, "moved"))
            return
        if task.remote_version != entry["version"]:
            result.not_moved_back.append(NotMovedBack(task_id, task.title, "changed"))
            return
        origin = (
            await db.execute(
                select(SourceContainer).where(
                    SourceContainer.connection_id == task.connection_id,
                    SourceContainer.remote_id == entry["from_remote_project"],
                )
            )
        ).scalar_one_or_none()
        if origin is None:
            result.not_moved_back.append(NotMovedBack(task_id, task.title, "missing"))
            return
        try:
            await self._tasks.move_to_container(db, user_id, task, origin)
        except BackendProblem as problem:
            reason = "changed" if problem.code == "remote_conflict" else "failed"
            result.not_moved_back.append(NotMovedBack(task_id, task.title, reason))
            return
        result.moved_back += 1


async def _unsupported() -> None:
    raise NotSupported(Capability.MOVE_TASKS)
