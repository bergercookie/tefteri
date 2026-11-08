"""Weekly planning: pick up to three projects, give their tasks a day, look back a week later."""

import uuid
from dataclasses import dataclass, field
from datetime import UTC, date, datetime, timedelta
from typing import cast
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.connection import Connection, SourceContainer
from tefteri.db.models.task import Task
from tefteri.db.models.weekly import WeeklyPlan, WeeklyPlanProject
from tefteri.domain.entities import Container
from tefteri.domain.enums import Capability, ConnectionKind, SyncState
from tefteri.domain.errors import NotSupported
from tefteri.domain.periods import PeriodType, period_start
from tefteri.domain.ports import TaskBackend
from tefteri.services.connections import ConnectionService
from tefteri.services.context import ContextFilter, load_maps
from tefteri.services.errors import Invalid, NotFound, guard
from tefteri.services.projects import ProjectService
from tefteri.services.sync import SyncService
from tefteri.services.tasks import TaskService

MAX_PROJECTS = 3
"""A week holds at most this many projects."""

LEFTOVER_ACTIONS = ("carry", "backlog")


def _aware(value: datetime) -> datetime:
    return value if value.tzinfo else value.replace(tzinfo=UTC)


def due_day(task: Task, tz: str) -> date | None:
    """Return the local day a task is planned for: its block start, else its due date."""
    moment = task.scheduled_start or task.due_at
    return _aware(moment).astimezone(ZoneInfo(tz)).date() if moment else None


@dataclass
class TaskView:
    """A task and the day it is planned for."""

    task: Task
    due_day: date | None
    planned_day: date | None
    """``due_day`` when it lies in the week of the plan, else ``None``."""
    parked: bool = False
    """The user set the task aside for this plan."""


@dataclass
class ProjectView:
    """A project of a plan with its open tasks."""

    row: WeeklyPlanProject
    container: SourceContainer | None
    connection: Connection | None
    open_tasks: list[TaskView] = field(default_factory=list)
    done_tasks: int = 0
    committed: list[TaskView] = field(default_factory=list)
    """The tasks planned when the plan was committed, done or not (empty before the commit)."""


@dataclass
class LookBackProject:
    """How one project of the earlier week went."""

    row: WeeklyPlanProject
    committed: int
    done: int
    leftover: list[TaskView]
    completed: bool
    """All its planned tasks are done (and there was at least one), or the user said so."""


@dataclass
class LookBack:
    """The look-back at an earlier week."""

    plan: WeeklyPlan
    projects: list[LookBackProject]


@dataclass
class Candidate:
    """A project the user can pick for the week."""

    container: SourceContainer
    connection: Connection
    path: str
    open_tasks: int
    carried_tasks: int
    selected: bool


@dataclass
class HistoryEntry:
    """One reviewed week."""

    plan: WeeklyPlan
    projects: list[WeeklyPlanProject]


@dataclass(frozen=True)
class Answer:
    """What the user decided about one project during the look-back."""

    plan_project_id: uuid.UUID
    finished_anyway: bool = False
    leftover: str = "backlog"
    archive: bool = False
    """Archive the project in the task app once its result is stored."""


def normalize_week(day: date) -> date:
    """Return the Monday of the week that holds ``day``."""
    return period_start(PeriodType.WEEK, day)


class WeeklyService:
    """The weekly planning workflow."""

    def __init__(
        self,
        tasks: TaskService,
        connections: ConnectionService,
        sync: SyncService,
        projects: ProjectService,
    ) -> None:
        """Use ``tasks`` to write days to the task app and ``sync`` to read projects again.

        ``projects`` archives the projects that the user finishes in the look-back.
        """
        self._tasks = tasks
        self._connections = connections
        self._sync = sync
        self._projects = projects

    # -- plans ------------------------------------------------------------------------------

    async def find(self, db: AsyncSession, user_id: uuid.UUID, week: date) -> WeeklyPlan | None:
        """Return the plan of ``week`` if the user started one."""
        return (
            await db.execute(
                select(WeeklyPlan).where(
                    WeeklyPlan.user_id == user_id, WeeklyPlan.week_start == week
                )
            )
        ).scalar_one_or_none()

    async def start(self, db: AsyncSession, user_id: uuid.UUID, week: date) -> WeeklyPlan:
        """Return the plan of ``week``, creating an empty draft the first time."""
        plan = await self.find(db, user_id, week)
        if plan is None:
            plan = WeeklyPlan(
                user_id=user_id,
                week_start=week,
                status="draft",
                reflection="",
                retro_skipped=False,
            )
            db.add(plan)
            await db.flush()
        return plan

    async def _rows(self, db: AsyncSession, plan: WeeklyPlan) -> list[WeeklyPlanProject]:
        return list(
            (
                await db.execute(
                    select(WeeklyPlanProject)
                    .where(WeeklyPlanProject.plan_id == plan.id)
                    .order_by(WeeklyPlanProject.position, WeeklyPlanProject.name)
                )
            ).scalars()
        )

    def _editable(self, plan: WeeklyPlan) -> None:
        if plan.status == "committed":
            raise Invalid("This plan is committed. Choose Change the plan to edit it.")

    async def project_views(
        self, db: AsyncSession, user_id: uuid.UUID, plan: WeeklyPlan, tz: str
    ) -> list[ProjectView]:
        """Return the plan's projects with their open tasks."""
        end = plan.week_start + timedelta(days=7)
        views = []
        for row in await self._rows(db, plan):
            container = (
                await db.get(SourceContainer, row.container_id) if row.container_id else None
            )
            connection = await db.get(Connection, container.connection_id) if container else None
            view = ProjectView(row, container, connection)
            if container is not None:
                promised = set(row.committed_task_ids) if plan.status == "committed" else set()
                parked = set(row.parked_task_ids)
                for t in await self._container_tasks(db, user_id, container.id):
                    day = due_day(t, tz)
                    in_week = day is not None and plan.week_start <= day < end
                    tv = TaskView(t, day, day if in_week else None, str(t.id) in parked)
                    if str(t.id) in promised:
                        view.committed.append(tv)
                    if t.status == "done":
                        view.done_tasks += 1
                        continue
                    view.open_tasks.append(tv)
                view.committed.sort(key=lambda v: (v.planned_day or date.max, v.task.title))
                view.open_tasks.sort(key=lambda v: (v.planned_day or date.max, v.task.title))
            views.append(view)
        return views

    async def _container_tasks(
        self, db: AsyncSession, user_id: uuid.UUID, container_id: uuid.UUID
    ) -> list[Task]:
        return list(
            (
                await db.execute(
                    select(Task).where(
                        Task.user_id == user_id,
                        Task.container_id == container_id,
                        Task.sync_state != SyncState.DELETED_REMOTELY.value,
                    )
                )
            ).scalars()
        )

    # -- choosing projects -------------------------------------------------------------------

    async def candidates(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        week: date,
        context: ContextFilter,
    ) -> list[Candidate]:
        """List the projects of the task apps, carried-over ones first."""
        plan = await self.find(db, user_id, week)
        chosen = {r.container_id for r in await self._rows(db, plan)} if plan else set()
        maps = await load_maps(db, user_id)
        connections = {
            c.id: c
            for c in (
                await db.execute(
                    select(Connection).where(
                        Connection.user_id == user_id,
                        Connection.kind == ConnectionKind.TASKS.value,
                    )
                )
            ).scalars()
        }
        containers = list(
            (
                await db.execute(select(SourceContainer).where(SourceContainer.user_id == user_id))
            ).scalars()
        )
        by_remote = {(c.connection_id, c.remote_id): c for c in containers}
        tasks = list(
            (
                await db.execute(
                    select(Task).where(
                        Task.user_id == user_id,
                        Task.status == "open",
                        Task.sync_state != SyncState.DELETED_REMOTELY.value,
                    )
                )
            ).scalars()
        )
        open_count: dict[uuid.UUID, int] = {}
        for t in tasks:
            if t.container_id is not None:
                open_count[t.container_id] = open_count.get(t.container_id, 0) + 1
        carried = await self._carried(db, user_id, week, tasks)
        out = []
        for c in containers:
            connection = connections.get(c.connection_id)
            if connection is None or not maps.matches(context, None, c.id, c.connection_id):
                continue
            names = [c.name]
            parent = by_remote.get((c.connection_id, c.parent_remote_id or ""))
            guard_depth = 0
            while parent is not None and guard_depth < 10:
                names.append(parent.name)
                parent = by_remote.get((c.connection_id, parent.parent_remote_id or ""))
                guard_depth += 1
            out.append(
                Candidate(
                    c,
                    connection,
                    " › ".join(reversed(names)),
                    open_count.get(c.id, 0),
                    carried.get(c.id, 0),
                    c.id in chosen,
                )
            )
        out.sort(key=lambda x: (x.carried_tasks == 0, x.path.casefold()))
        return out

    async def _carried(
        self, db: AsyncSession, user_id: uuid.UUID, week: date, tasks: list[Task]
    ) -> dict[uuid.UUID, int]:
        """Return, per project, the open tasks that the last look-back said to carry over."""
        last = await self._previous(db, user_id, week, reviewed_only=True)
        if last is None:
            return {}
        open_ids = {str(t.id) for t in tasks}
        out: dict[uuid.UUID, int] = {}
        for row in await self._rows(db, last):
            if row.leftover_action == "carry" and row.container_id is not None:
                n = sum(1 for tid in row.committed_task_ids if tid in open_ids)
                if n:
                    out[row.container_id] = n
        return out

    async def add_project(
        self, db: AsyncSession, user_id: uuid.UUID, plan: WeeklyPlan, container_id: uuid.UUID
    ) -> WeeklyPlanProject:
        """Add a project to the week. At most three, and only projects of a task app."""
        self._editable(plan)
        rows = await self._rows(db, plan)
        existing = next((r for r in rows if r.container_id == container_id), None)
        if existing is not None:
            return existing
        container = (
            await db.execute(
                select(SourceContainer).where(
                    SourceContainer.id == container_id, SourceContainer.user_id == user_id
                )
            )
        ).scalar_one_or_none()
        connection = await db.get(Connection, container.connection_id) if container else None
        if container is None or connection is None or connection.kind != "tasks":
            raise NotFound
        if len(rows) >= MAX_PROJECTS:
            raise Invalid(f"Choose at most {MAX_PROJECTS} projects for a week.")
        return await self._add(db, plan, container, rows, created_here=False)

    async def _add(
        self,
        db: AsyncSession,
        plan: WeeklyPlan,
        container: SourceContainer,
        rows: list[WeeklyPlanProject],
        *,
        created_here: bool,
    ) -> WeeklyPlanProject:
        row = WeeklyPlanProject(
            plan_id=plan.id,
            container_id=container.id,
            name=container.name,
            position=max((r.position for r in rows), default=-1) + 1,
            created_here=created_here,
            committed_task_ids=[],
        )
        db.add(row)
        await db.flush()
        return row

    async def remove_project(
        self, db: AsyncSession, plan: WeeklyPlan, plan_project_id: uuid.UUID
    ) -> None:
        """Take a project out of the week. Its tasks keep the days they have."""
        self._editable(plan)
        row = await db.get(WeeklyPlanProject, plan_project_id)
        if row is None or row.plan_id != plan.id:
            raise NotFound
        await db.delete(row)
        await db.flush()

    async def create_subproject(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        plan: WeeklyPlan,
        parent_id: uuid.UUID,
        name: str,
    ) -> WeeklyPlanProject:
        """Create a project under ``parent_id`` in the task app and add it to the week."""
        self._editable(plan)
        title = name.strip()
        if not title:
            raise Invalid("Give the new project a name.")
        rows = await self._rows(db, plan)
        if len(rows) >= MAX_PROJECTS:
            raise Invalid(f"Choose at most {MAX_PROJECTS} projects for a week.")
        parent = (
            await db.execute(
                select(SourceContainer).where(
                    SourceContainer.id == parent_id, SourceContainer.user_id == user_id
                )
            )
        ).scalar_one_or_none()
        connection = await db.get(Connection, parent.connection_id) if parent else None
        if parent is None or connection is None or connection.kind != "tasks":
            raise NotFound
        backend = cast(TaskBackend, await self._connections.backend_of_owner(db, connection))
        if Capability.SUBPROJECTS not in backend.capabilities():
            await guard(connection, _unsupported())
        remote = await guard(
            connection,
            backend.create_container(title, Container(parent.remote_id, parent.name, None)),
        )
        container = SourceContainer(
            user_id=user_id,
            connection_id=connection.id,
            remote_id=remote.remote_id,
            name=remote.name,
            parent_remote_id=remote.parent_id or parent.remote_id,
            context=parent.context,
        )
        db.add(container)
        await db.flush()
        return await self._add(db, plan, container, rows, created_here=True)

    # -- reading the task app again -----------------------------------------------------------

    async def refresh(
        self, db: AsyncSession, user_id: uuid.UUID, week: date, plans: list[WeeklyPlan]
    ) -> None:
        """Read the tasks of the chosen projects again from their task apps."""
        containers: dict[uuid.UUID, list[SourceContainer]] = {}
        for plan in plans:
            for row in await self._rows(db, plan):
                container = (
                    await db.get(SourceContainer, row.container_id) if row.container_id else None
                )
                if container is not None:
                    group = containers.setdefault(container.connection_id, [])
                    if container not in group:
                        group.append(container)
        for connection_id, rows in containers.items():
            connection = await db.get(Connection, connection_id)
            if connection is not None and connection.user_id == user_id:
                await guard(connection, self._sync.sync_projects(db, connection, rows))

    # -- giving days -------------------------------------------------------------------------

    async def spread(
        self, db: AsyncSession, user_id: uuid.UUID, plan: WeeklyPlan, tz: str, today: date
    ) -> int:
        """Give every task that has no day in the week a day, keeping the days evenly loaded.

        Tasks go to Monday to Friday, never to a day that has passed. When only the weekend is
        left they go to the weekend. Returns how many tasks got a day.
        """
        self._editable(plan)
        days = [plan.week_start + timedelta(days=i) for i in range(7)]
        future = [d for d in days if d >= today]
        eligible = [d for d in future if d.weekday() < 5] or future
        if not eligible:
            raise Invalid("This week is over. Plan a later week.")
        views = await self.project_views(db, user_id, plan, tz)
        load = {d: 0 for d in eligible}
        for v in views:
            for t in v.open_tasks:
                if not t.parked and t.planned_day in load:
                    load[t.planned_day] += 1
        count = 0
        for v in views:
            for t in v.open_tasks:
                if t.planned_day is not None or t.parked:
                    continue
                day = min(eligible, key=lambda d: (load[d], d))
                await self._tasks.schedule_date(db, user_id, t.task, day)
                load[day] += 1
                count += 1
        return count

    async def set_parked(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        plan: WeeklyPlan,
        task_id: uuid.UUID,
        parked: bool,
    ) -> None:
        """Set a task of the plan aside (or put it back). The task app is not touched."""
        self._editable(plan)
        key = str(task_id)
        for row in await self._rows(db, plan):
            if row.container_id is None:
                continue
            ids = {str(t.id) for t in await self._container_tasks(db, user_id, row.container_id)}
            if key not in ids:
                continue
            current = [i for i in row.parked_task_ids if i != key]
            row.parked_task_ids = [*current, key] if parked else current
            await db.flush()
            return
        raise NotFound("This task is not in a project of the plan.")

    # -- commit ------------------------------------------------------------------------------

    async def commit(
        self, db: AsyncSession, user_id: uuid.UUID, plan: WeeklyPlan, tz: str, now: datetime
    ) -> WeeklyPlan:
        """Fix the plan: remember which tasks are planned for the week, for the look-back."""
        views = await self.project_views(db, user_id, plan, tz)
        if not views:
            raise Invalid("Choose at least one project before you finish.")
        for v in views:
            v.row.committed_task_ids = [
                str(t.task.id) for t in v.open_tasks if t.planned_day is not None and not t.parked
            ]
        plan.status = "committed"
        plan.committed_at = now
        await db.flush()
        return plan

    async def reopen(self, db: AsyncSession, plan: WeeklyPlan) -> WeeklyPlan:
        """Make a committed plan editable again."""
        plan.status = "draft"
        plan.committed_at = None
        await db.flush()
        return plan

    async def skip_look_back(self, db: AsyncSession, plan: WeeklyPlan) -> WeeklyPlan:
        """Plan this week without looking back at the last one."""
        plan.retro_skipped = True
        await db.flush()
        return plan

    # -- looking back --------------------------------------------------------------------------

    async def _previous(
        self, db: AsyncSession, user_id: uuid.UUID, week: date, *, reviewed_only: bool = False
    ) -> WeeklyPlan | None:
        query = select(WeeklyPlan).where(
            WeeklyPlan.user_id == user_id,
            WeeklyPlan.week_start < week,
            WeeklyPlan.status == "committed",
        )
        if reviewed_only:
            query = query.where(WeeklyPlan.reviewed_at.is_not(None))
        return (await db.execute(query.order_by(WeeklyPlan.week_start.desc()))).scalars().first()

    async def look_back(
        self, db: AsyncSession, user_id: uuid.UUID, week: date, tz: str
    ) -> LookBack | None:
        """Return how the last committed week before ``week`` went (``None`` if there was none)."""
        previous = await self._previous(db, user_id, week)
        if previous is None:
            return None
        end = previous.week_start + timedelta(days=7)
        out = []
        for row in await self._rows(db, previous):
            tasks = (
                {str(t.id): t for t in await self._container_tasks(db, user_id, row.container_id)}
                if row.container_id
                else {}
            )
            planned = [tasks[i] for i in row.committed_task_ids if i in tasks]
            done = sum(1 for t in planned if t.status == "done")
            leftover = []
            for t in planned:
                if t.status != "done":
                    day = due_day(t, tz)
                    in_week = day is not None and previous.week_start <= day < end
                    leftover.append(TaskView(t, day, day if in_week else None))
            if previous.reviewed_at is not None:
                committed = row.reviewed_committed or 0
                done = row.reviewed_done or 0
                completed = row.outcome == "done"
            else:
                committed = len(planned)
                completed = committed > 0 and done == committed
            out.append(LookBackProject(row, committed, done, leftover, completed))
        return LookBack(previous, out)

    async def review(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        plan_id: uuid.UUID,
        tz: str,
        answers: list[Answer],
        reflection: str,
        now: datetime,
    ) -> WeeklyPlan:
        """Store the look-back: which projects are done, and what happens to the leftovers.

        ``backlog`` removes the old due date of a leftover task in the task app. ``carry`` leaves
        the task as it is and suggests its project for the next week.
        """
        plan = await db.get(WeeklyPlan, plan_id)
        if plan is None or plan.user_id != user_id or plan.status != "committed":
            raise NotFound
        if plan.reviewed_at is not None:
            raise Invalid("This week was reviewed already.")
        for a in answers:
            if a.leftover not in LEFTOVER_ACTIONS:
                raise Invalid("Leftover tasks can be carried over or go back to the backlog.")
        by_id = {a.plan_project_id: a for a in answers}
        back = await self.look_back(db, user_id, plan.week_start + timedelta(days=7), tz)
        assert back is not None and back.plan.id == plan.id  # noqa: S101 - same plan, found above
        for p in back.projects:
            answer = by_id.get(p.row.id, Answer(p.row.id))
            p.row.reviewed_committed = p.committed
            p.row.reviewed_done = p.done
            p.row.outcome = "done" if p.completed or answer.finished_anyway else "not_done"
            p.row.leftover_action = answer.leftover if p.leftover else None
            if answer.leftover == "backlog":
                for t in p.leftover:
                    if t.task.due_at is not None:
                        await self._tasks.unschedule(db, user_id, t.task)
        plan.reviewed_at = now
        plan.reflection = reflection.strip()
        await db.flush()
        # Archive last: the counts are stored, and the plan no longer waits for its look-back.
        for p in back.projects:
            wish = by_id.get(p.row.id)
            if wish is not None and wish.archive and p.row.container_id is not None:
                await self._projects.archive(db, user_id, p.row.container_id)
        return plan

    async def history(self, db: AsyncSession, user_id: uuid.UUID) -> list[HistoryEntry]:
        """List the reviewed weeks, newest first."""
        plans = (
            await db.execute(
                select(WeeklyPlan)
                .where(WeeklyPlan.user_id == user_id, WeeklyPlan.reviewed_at.is_not(None))
                .order_by(WeeklyPlan.week_start.desc())
            )
        ).scalars()
        return [HistoryEntry(p, await self._rows(db, p)) for p in plans]


async def _unsupported() -> None:
    raise NotSupported(Capability.SUBPROJECTS)
