"""Milestone projects (spec 004): the planning data of a project labelled milestone.

A milestone row is made the first time the weekly flow touches a project. This service keeps
its done-state, its state and its completion, and says what a screen needs to show about it.
Pure rules are in ``domain.milestones``. Every write of the task app happens elsewhere
(``milestone_close`` moves tasks); this module only writes tefteri's own rows.
"""

import uuid
from dataclasses import dataclass, field
from datetime import UTC, date, datetime, timedelta
from typing import cast
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.connection import Connection, SourceContainer
from tefteri.db.models.milestone import Milestone, MilestoneClosure, MilestoneRollover
from tefteri.db.models.project_label import ProjectLabel as ProjectLabelRow
from tefteri.db.models.task import Task
from tefteri.domain.enums import Capability, MilestoneState, SyncState
from tefteri.domain.milestones import (
    CloseOptions,
    RolloverEvent,
    TaskFacts,
    close_options,
    completion,
    needs_rescope,
)
from tefteri.domain.ports import TaskBackend
from tefteri.services.connections import ConnectionService
from tefteri.services.errors import Invalid, NotFound
from tefteri.services.project_labels import (
    ThemeRef,
    aware,
    container_of,
    tree_of,
)

DONE_STATE_MAX = 255
DONE_STATE_HINT = (
    "Say when the milestone is finished, in one sentence. For example: ship the login flow."
)
UNFINISHED = (MilestoneState.ACTIVE.value, MilestoneState.PARKED.value)


def _today(now: datetime, tz: str) -> date:
    return aware(now).astimezone(ZoneInfo(tz)).date()


@dataclass(frozen=True)
class DoneEffect:
    """What marking a milestone done by hand does (FR-018, FR-041)."""

    open_tasks: int
    message: str


@dataclass
class MilestoneView:
    """A milestone with everything its screen shows."""

    milestone: Milestone
    project: ProjectLabelRow
    theme: ThemeRef | None
    needs_rescope: bool
    rollovers: list[MilestoneRollover]
    open_tasks: int
    can_close: CloseOptions
    last_closure: MilestoneClosure | None
    orphaned: str | None = None
    """The reason the project is not in the task app any more, or ``None``."""
    notices: list[str] = field(default_factory=list)


class MilestoneService:
    """Get, change and settle the milestone rows of a user."""

    def __init__(self, connections: ConnectionService) -> None:
        """Use ``connections`` to ask what a task app can do."""
        self._connections = connections

    # -- rows ---------------------------------------------------------------------------------

    async def get(self, db: AsyncSession, user_id: uuid.UUID, milestone_id: uuid.UUID) -> Milestone:
        """Return one of the user's milestones or raise ``NotFound``."""
        row = await db.get(Milestone, milestone_id)
        if row is None or row.user_id != user_id:
            raise NotFound
        return row

    async def ensure(
        self,
        db: AsyncSession,
        project: ProjectLabelRow,
        done_state: str | None = None,
        *,
        now: datetime | None = None,
    ) -> Milestone:
        """Return the milestone row of a project, adding an ``active`` one when there is none.

        A ``done_state`` that is given is checked and stored (FR-009).
        """
        row = (
            await db.execute(select(Milestone).where(Milestone.project_id == project.id))
        ).scalar_one_or_none()
        if row is None:
            stamp = now or datetime.now(UTC)
            row = Milestone(
                user_id=project.user_id,
                project_id=project.id,
                state=MilestoneState.ACTIVE.value,
                state_changed_at=stamp,
                rollover_count=0,
            )
            db.add(row)
        if done_state is not None:
            row.done_state = self.check_done_state(done_state)
        await db.flush()
        return row

    @staticmethod
    def check_done_state(text: str) -> str:
        """Return the done-state stripped, or raise ``Invalid`` with ``done_state_required``."""
        clean = (text or "").strip()
        if not clean:
            raise Invalid(DONE_STATE_HINT, code="done_state_required")
        if len(clean) > DONE_STATE_MAX:
            raise Invalid(
                f"Keep the done-state to {DONE_STATE_MAX} characters.", code="done_state_required"
            )
        return clean

    async def set_done_state(
        self, db: AsyncSession, user_id: uuid.UUID, milestone_id: uuid.UUID, text: str
    ) -> Milestone:
        """Set or change the done-state of a milestone."""
        milestone = await self.get(db, user_id, milestone_id)
        milestone.done_state = self.check_done_state(text)
        await db.flush()
        return milestone

    def set_state(self, milestone: Milestone, state: MilestoneState, now: datetime) -> None:
        """Change the state of a milestone and stamp the change."""
        milestone.state = state.value
        milestone.state_changed_at = now

    # -- rollovers and the nudge ---------------------------------------------------------------

    async def rollovers(
        self, db: AsyncSession, milestone_ids: list[uuid.UUID]
    ) -> dict[uuid.UUID, list[MilestoneRollover]]:
        """Return the rollover events of milestones, oldest first."""
        found: dict[uuid.UUID, list[MilestoneRollover]] = {m: [] for m in milestone_ids}
        if not milestone_ids:
            return found
        events = (
            await db.execute(
                select(MilestoneRollover)
                .where(MilestoneRollover.milestone_id.in_(milestone_ids))
                .order_by(MilestoneRollover.created_at, MilestoneRollover.id)
            )
        ).scalars()
        for event in events:
            found[event.milestone_id].append(event)
        return found

    @staticmethod
    def rescope_needed(events: list[MilestoneRollover]) -> bool:
        """Return whether the events make the nudge (two unmarked in a row)."""
        return needs_rescope(
            [RolloverEvent(e.expected, aware(e.created_at), str(e.id)) for e in events]
        )

    async def add_rollover(
        self,
        db: AsyncSession,
        milestone: Milestone,
        *,
        plan_project_id: uuid.UUID | None,
        from_week: date,
        to_week: date,
        expected: bool,
        now: datetime,
    ) -> MilestoneRollover:
        """Record one recommit: an event with its own marker, and the count raised by one."""
        existing = (await self.rollovers(db, [milestone.id]))[milestone.id]
        at = aware(now)
        if existing and at <= aware(existing[-1].created_at):
            # Strictly after the newest event, so the order of the events is always clear.
            at = aware(existing[-1].created_at) + timedelta(microseconds=1)
        event = MilestoneRollover(
            milestone_id=milestone.id,
            plan_project_id=plan_project_id,
            from_week=from_week,
            to_week=to_week,
            expected=expected,
            created_at=at,
        )
        db.add(event)
        milestone.rollover_count += 1
        await db.flush()
        return event

    # -- tasks of a milestone --------------------------------------------------------------------

    async def _tasks(
        self, db: AsyncSession, user_id: uuid.UUID, container: SourceContainer
    ) -> list[Task]:
        return list(
            (
                await db.execute(
                    select(Task).where(Task.user_id == user_id, Task.container_id == container.id)
                )
            ).scalars()
        )

    async def open_task_count(
        self, db: AsyncSession, user_id: uuid.UUID, project: ProjectLabelRow
    ) -> int:
        """Count the open tasks that the project holds now."""
        container = await container_of(db, project)
        if container is None:
            return 0
        return sum(
            1
            for t in await self._tasks(db, user_id, container)
            if t.status == "open" and t.sync_state != SyncState.DELETED_REMOTELY.value
        )

    # -- completion (FR-017, FR-035) -------------------------------------------------------------

    async def settle(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        tz: str,
        milestones: list[Milestone],
        *,
        full_sync: bool,
        now: datetime,
    ) -> list[Milestone]:
        """Mark the milestones whose tasks are all closed or dropped as done. Returns them.

        ``full_sync`` says that the tasks were just read from the whole task app, so a task that
        is marked deleted-remotely is gone for good and counts as dropped. Without it, a project
        that holds such a task is skipped: a task that moved to another project looks deleted
        until the next full sync, and it must not finish a milestone by mistake.
        """
        finished: list[Milestone] = []
        for milestone in milestones:
            if milestone.state not in UNFINISHED:
                continue
            project = await db.get(ProjectLabelRow, milestone.project_id)
            if project is None or project.orphaned_reason is not None:
                continue
            container = await container_of(db, project)
            if container is None:
                continue
            tasks = await self._tasks(db, user_id, container)
            gone = [t for t in tasks if t.sync_state == SyncState.DELETED_REMOTELY.value]
            if gone and not full_sync:
                continue
            zone = ZoneInfo(tz)
            result = completion(
                [
                    TaskFacts(
                        done=t.status == "done",
                        dropped=t.status != "done"
                        and t.sync_state == SyncState.DELETED_REMOTELY.value,
                        completed_on=(
                            aware(t.completed_at).astimezone(zone).date()
                            if t.completed_at
                            else None
                        ),
                    )
                    for t in tasks
                ]
            )
            if result.done:
                await self._become_done(
                    db, milestone, project, result.done_on or _today(now, tz), "auto", now
                )
                finished.append(milestone)
        return finished

    async def _become_done(
        self,
        db: AsyncSession,
        milestone: Milestone,
        project: ProjectLabelRow,
        day: date,
        by: str,
        now: datetime,
    ) -> None:
        """Store the done day and the theme at that moment (FR-035). Nothing edits them later."""
        tree = await tree_of(db, milestone.user_id, project.connection_id)
        theme = tree.theme_of(str(project.id)) if tree else None
        self.set_state(milestone, MilestoneState.DONE, now)
        milestone.done_on = day
        milestone.done_by = by
        milestone.done_theme_id = theme.id if theme else None
        milestone.done_theme_name = theme.name if theme else None
        await db.flush()

    async def mark_done(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        tz: str,
        milestone: Milestone,
        now: datetime,
        *,
        dry_run: bool = False,
    ) -> DoneEffect:
        """Mark a milestone done by hand, or only say what that would do (FR-018, FR-041).

        Open tasks stay where they are. The done day is today of the user, never the review day.
        """
        if milestone.state not in UNFINISHED:
            raise Invalid("This milestone is done or closed already.", code="not_unfinished")
        project = await db.get(ProjectLabelRow, milestone.project_id)
        assert project is not None  # noqa: S101 - the row hangs on its project
        count = await self.open_task_count(db, user_id, project)
        if count:
            plural = "task stays" if count == 1 else "tasks stay"
            message = f"{count} open {plural} in the project. Nothing is moved or deleted."
        else:
            message = "Nothing is moved or deleted."
        if not dry_run:
            await self._become_done(db, milestone, project, _today(now, tz), "user", now)
        return DoneEffect(count, message)

    async def reopen_done(self, db: AsyncSession, milestone: Milestone, now: datetime) -> None:
        """Make a done milestone active again. The done fields are cleared, nothing else changes."""
        self.set_state(milestone, MilestoneState.ACTIVE, now)
        milestone.done_on = None
        milestone.done_by = None
        milestone.done_theme_id = None
        milestone.done_theme_name = None
        await db.flush()

    # -- reading ---------------------------------------------------------------------------------

    async def can_move_tasks(self, db: AsyncSession, connection: Connection | None) -> bool:
        """Return whether the task app of the connection can move tasks."""
        if connection is None:
            return False
        try:
            backend = cast(TaskBackend, await self._connections.backend_of_owner(db, connection))
            return Capability.MOVE_TASKS in backend.capabilities()
        except Exception:  # noqa: BLE001 - a connection that cannot be built cannot move tasks
            return False

    async def close_availability(
        self,
        db: AsyncSession,
        project: ProjectLabelRow,
        theme: ThemeRef | None,
        *,
        can_move: bool | None = None,
    ) -> CloseOptions:
        """Say whether the open tasks of the project can go back to its theme (FR-027)."""
        if can_move is None:
            can_move = await self.can_move_tasks(
                db, await db.get(Connection, project.connection_id)
            )
        return close_options(theme is not None, bool(theme and theme.usable), can_move)

    async def view(
        self, db: AsyncSession, user_id: uuid.UUID, milestone: Milestone
    ) -> MilestoneView:
        """Gather what the screen of one milestone shows."""
        project = await db.get(ProjectLabelRow, milestone.project_id)
        assert project is not None  # noqa: S101 - the row hangs on its project
        tree = await tree_of(db, user_id, project.connection_id)
        theme = tree.theme_of(str(project.id)) if tree else None
        events = (await self.rollovers(db, [milestone.id]))[milestone.id]
        closure = (
            await db.execute(
                select(MilestoneClosure)
                .where(MilestoneClosure.milestone_id == milestone.id)
                .order_by(MilestoneClosure.started_at.desc())
                .limit(1)
            )
        ).scalar_one_or_none()
        return MilestoneView(
            milestone=milestone,
            project=project,
            theme=theme,
            needs_rescope=self.rescope_needed(events),
            rollovers=events,
            open_tasks=await self.open_task_count(db, user_id, project),
            can_close=await self.close_availability(db, project, theme),
            last_closure=closure,
            orphaned=project.orphaned_reason,
        )
