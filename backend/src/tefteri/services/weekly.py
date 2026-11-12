"""Weekly planning: commit milestone projects, give their tasks a day, review the week (spec 004).

The unit of commitment is a milestone project (a project labelled milestone, spec 003). The cap
of three milestones only warns. At the review each unfinished milestone gets one decision:
recommit, park, close and return its tasks, or decide later. Entries from before spec 004 are
read under the new names and never rewritten.
"""

import uuid
from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import UTC, date, datetime, timedelta
from typing import cast
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.connection import Connection, SourceContainer
from tefteri.db.models.milestone import Milestone
from tefteri.db.models.project_label import ProjectLabel as ProjectLabelRow
from tefteri.db.models.task import Task
from tefteri.db.models.weekly import WeeklyPlan, WeeklyPlanProject
from tefteri.domain.classification import is_weekly_eligible, label_of
from tefteri.domain.enums import (
    Capability,
    MilestoneState,
    ProjectLabel,
    ReviewDecision,
    SyncState,
)
from tefteri.domain.errors import NotSupported
from tefteri.domain.milestones import (
    MILESTONE_CAP,
    CommitKind,
    commit_kind,
    decision_of,
    focus_share,
    outside_focus,
    over_cap,
)
from tefteri.domain.periods import PeriodType, month_of_week, period_start
from tefteri.domain.ports import TaskBackend
from tefteri.services.classification import ClassificationService
from tefteri.services.connections import ConnectionService
from tefteri.services.errors import Invalid, NotFound, guard
from tefteri.services.focus import FocusProvider, NoFocus
from tefteri.services.milestone_close import MilestoneCloseService
from tefteri.services.milestones import UNFINISHED, MilestoneService
from tefteri.services.project_labels import (
    ConnectionTree,
    ThemeRef,
    container_of,
    load_trees,
    milestones_by_project,
    project_of,
    tree_of,
    write_labels,
)
from tefteri.services.projects import ProjectService
from tefteri.services.sync import SyncService
from tefteri.services.tasks import TaskService

__all__ = ["MILESTONE_CAP", "WeeklyService"]


def _aware(value: datetime) -> datetime:
    return value if value.tzinfo else value.replace(tzinfo=UTC)


def due_day(task: Task, tz: str) -> date | None:
    """Return the local day a task is planned for: its block start, else its due date."""
    moment = task.scheduled_start or task.due_at
    return _aware(moment).astimezone(ZoneInfo(tz)).date() if moment else None


@dataclass(frozen=True)
class ThemeTag:
    """The theme of a milestone as it was when the milestone was committed."""

    id: uuid.UUID
    name: str


@dataclass
class TaskView:
    """A task and the day it is planned for."""

    task: Task
    due_day: date | None
    planned_day: date | None
    """``due_day`` when it lies in the week of the plan, else ``None``."""
    parked: bool = False
    """The user set the task aside for this plan ("not this week")."""
    completed_day: date | None = None
    """The local day the task was completed, when the task app says."""


@dataclass
class ProjectView:
    """A milestone of a plan with its open tasks."""

    row: WeeklyPlanProject
    container: SourceContainer | None
    connection: Connection | None
    open_tasks: list[TaskView] = field(default_factory=list)
    done_tasks: int = 0
    committed: list[TaskView] = field(default_factory=list)
    """The tasks planned when the plan was committed, done or not (empty before the commit)."""
    milestone: Milestone | None = None
    """``None`` for an entry from before spec 004."""
    theme: ThemeTag | None = None
    outside_focus: bool = False
    rollover_count: int = 0
    needs_rescope: bool = False
    orphaned: bool = False
    notice: str | None = None
    """``relabelled`` when the project got another label after it was committed."""


@dataclass(frozen=True)
class PlanFacts:
    """What the plan shows about the cap and the focus."""

    milestone_count: int
    over_cap: bool
    month: date
    focus_known: bool


@dataclass(frozen=True)
class CloseInfo:
    """Whether close and return is offered for an entry of the review, and why not."""

    available: bool
    reason: str | None
    open_tasks: int
    theme_name: str | None


@dataclass
class LookBackProject:
    """How one milestone of the earlier week went."""

    row: WeeklyPlanProject
    committed: int
    done: int
    leftover: list[TaskView]
    completed: bool
    """The milestone is done (or, for an old entry, all its planned tasks are done)."""
    color: str | None = None
    """The color of the project in the task app (``#rrggbb``), if it still exists there."""
    milestone: Milestone | None = None
    theme: ThemeTag | None = None
    decision: ReviewDecision | None = None
    """What was decided, under the new names (an old ``carry`` shows as ``recommit``)."""
    legacy: bool = False
    """The entry is from before spec 004: it has no milestone or an old choice."""
    rollover_count: int = 0
    needs_rescope: bool = False
    outside_focus: bool = False
    close: CloseInfo | None = None


@dataclass(frozen=True)
class Summary:
    """The numbers of the review (FR-020, FR-021)."""

    committed_tasks: int
    done_tasks: int
    milestones_committed: int
    milestones_done: int
    pace: list[tuple[date, int]]
    """Completed committed tasks for each local day of the week."""
    focus_share: float | None
    note: str | None


@dataclass
class LookBack:
    """The look-back at an earlier week."""

    plan: WeeklyPlan
    projects: list[LookBackProject]
    summary: Summary


@dataclass
class Candidate:
    """A project the user can pick for the week."""

    container: SourceContainer
    connection: Connection
    path: str
    open_tasks: int
    carried_tasks: int
    selected: bool
    kind: CommitKind
    """``milestone``, or ``label_then_commit`` for a project with no label (shown as unsorted)."""
    milestone: Milestone | None = None
    state: MilestoneState = MilestoneState.ACTIVE
    theme: ThemeRef | None = None
    in_focus: bool | None = None
    """``None`` when no focus data exists."""
    rollover_count: int = 0
    needs_rescope: bool = False
    decision_open: bool = False

    @property
    def unsorted(self) -> bool:
        """The project has no label yet (spec 003): picking it labels it milestone."""
        return self.kind is CommitKind.LABEL_THEN_COMMIT


@dataclass(frozen=True)
class ThemeEntry:
    """A theme of the picker."""

    row: ProjectLabelRow
    container: SourceContainer
    connection: Connection
    in_focus: bool | None
    milestones: int
    open_milestones: int


@dataclass(frozen=True)
class Themes:
    """The themes for the picker headers and its empty states."""

    focus_known: bool
    themes: list[ThemeEntry]
    unsorted_count: int


@dataclass(frozen=True)
class HistoryProject:
    """An entry of a reviewed week."""

    row: WeeklyPlanProject
    milestone: Milestone | None
    decision: ReviewDecision | None
    legacy: bool


@dataclass
class HistoryEntry:
    """One reviewed week."""

    plan: WeeklyPlan
    projects: list[HistoryProject]


@dataclass(frozen=True)
class Answer:
    """What the user decided about one milestone during the review."""

    plan_project_id: uuid.UUID
    decision: str | None = None
    """``recommit``, ``park``, ``close`` or ``decide_later``. Nothing means ``decide_later``."""
    expected: bool = False
    """With ``recommit``: this rollover was expected ("bigger than a week")."""
    mark_done: bool = False
    """The user says that the milestone is done."""
    archive: bool = False
    """Archive the project in the task app once its result is stored."""


@dataclass(frozen=True)
class Nudge:
    """A milestone that now needs to be shrunk, split or closed."""

    milestone_id: uuid.UUID
    name: str


@dataclass
class ReviewResult:
    """The answer of a review."""

    plan: WeeklyPlan
    notices: list[str] = field(default_factory=list)
    nudges: list[Nudge] = field(default_factory=list)


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
        classification: ClassificationService,
        milestones: MilestoneService,
        closer: MilestoneCloseService,
        focus: FocusProvider | None = None,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        """Use ``tasks`` to write days to the task app and ``sync`` to read projects again.

        ``projects`` archives the projects that the user finishes in the review.
        ``classification`` creates and labels a new milestone. ``milestones`` and ``closer``
        keep the milestone rows and close them. ``focus`` tells the focus themes of a month
        (feature 007 supplies it; the default knows none). ``clock`` is injectable for tests.
        """
        self._tasks = tasks
        self._connections = connections
        self._sync = sync
        self._projects = projects
        self._classification = classification
        self._milestones = milestones
        self._closer = closer
        self._focus = focus or NoFocus()
        self._clock = clock or (lambda: datetime.now(UTC))

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

    async def _milestones_of(
        self, db: AsyncSession, rows: list[WeeklyPlanProject]
    ) -> dict[uuid.UUID, Milestone]:
        ids = [r.milestone_id for r in rows if r.milestone_id is not None]
        if not ids:
            return {}
        found = (await db.execute(select(Milestone).where(Milestone.id.in_(ids)))).scalars()
        return {m.id: m for m in found}

    @staticmethod
    def _theme_tag(row: WeeklyPlanProject) -> ThemeTag | None:
        if row.theme_project_id is None or row.theme_name is None:
            return None
        return ThemeTag(row.theme_project_id, row.theme_name)

    async def _settle(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        tz: str,
        milestones: list[Milestone],
        *,
        full_sync: bool = False,
    ) -> None:
        await self._milestones.settle(
            db, user_id, tz, milestones, full_sync=full_sync, now=self._clock()
        )

    async def focus_of(
        self, db: AsyncSession, user_id: uuid.UUID, week: date
    ) -> set[uuid.UUID] | None:
        """Return the focus themes of the month of ``week`` (``None``: no focus data, FR-038)."""
        return await self._focus.themes_for_month(db, user_id, month_of_week(week))

    async def plan_facts(
        self, db: AsyncSession, user_id: uuid.UUID, plan: WeeklyPlan, views: list[ProjectView]
    ) -> PlanFacts:
        """Count the milestones of the plan against the cap and say whether focus data exists."""
        count = sum(1 for v in views if v.row.milestone_id is not None)
        focus = await self.focus_of(db, user_id, plan.week_start)
        return PlanFacts(count, over_cap(count), month_of_week(plan.week_start), focus is not None)

    async def project_views(
        self, db: AsyncSession, user_id: uuid.UUID, plan: WeeklyPlan, tz: str
    ) -> list[ProjectView]:
        """Return the plan's milestones with their open tasks and their milestone facts."""
        end = plan.week_start + timedelta(days=7)
        rows = await self._rows(db, plan)
        milestones = await self._milestones_of(db, rows)
        await self._settle(db, user_id, tz, list(milestones.values()))
        rolls = await self._milestones.rollovers(db, list(milestones))
        focus = await self.focus_of(db, user_id, plan.week_start)
        views = []
        for row in rows:
            container = (
                await db.get(SourceContainer, row.container_id) if row.container_id else None
            )
            connection = await db.get(Connection, container.connection_id) if container else None
            view = ProjectView(row, container, connection)
            milestone = milestones.get(row.milestone_id) if row.milestone_id else None
            view.milestone = milestone
            view.theme = self._theme_tag(row)
            if milestone is not None:
                project = await db.get(ProjectLabelRow, milestone.project_id)
                view.rollover_count = milestone.rollover_count
                view.needs_rescope = self._milestones.rescope_needed(rolls[milestone.id])
                view.orphaned = project is None or project.orphaned_reason is not None
                if project is not None and project.label != ProjectLabel.MILESTONE.value:
                    view.notice = "relabelled"
                view.outside_focus = outside_focus(row.theme_project_id, focus)
            else:
                view.orphaned = container is None
            if container is not None:
                promised = set(row.committed_task_ids) if plan.status == "committed" else set()
                parked = set(row.parked_task_ids)
                for t in await self._container_tasks(db, user_id, container.id):
                    day = due_day(t, tz)
                    in_week = day is not None and plan.week_start <= day < end
                    done_day = (
                        _aware(t.completed_at).astimezone(ZoneInfo(tz)).date()
                        if t.completed_at
                        else None
                    )
                    tv = TaskView(t, day, day if in_week else None, str(t.id) in parked, done_day)
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

    # -- choosing milestones -----------------------------------------------------------------

    async def candidates(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        week: date,
    ) -> list[Candidate]:
        """List the projects that the user may commit to the week (spec 004, FR-001).

        A milestone that is active or parked is listed, and so is a project with no label and
        no subproject (it is labelled milestone when picked). A theme, maintenance, ignored and
        orphaned projects, and what is inside a routine, are never listed. A milestone that is
        closed or done is not listed either. A project that is already in the plan is listed
        with ``selected`` set.
        """
        plan = await self.find(db, user_id, week)
        chosen = {r.container_id for r in await self._rows(db, plan)} if plan else set()
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
        milestones = await milestones_by_project(db, user_id)
        rolls = await self._milestones.rollovers(db, [m.id for m in milestones.values()])
        open_decisions = await self._open_decisions(db, user_id)
        focus = await self.focus_of(db, user_id, week)
        out: list[Candidate] = []
        for tree in await load_trees(db, user_id):
            parents = {n.parent_key for n in tree.nodes.values() if n.parent_key and not n.orphaned}
            for row in tree.rows:
                key = str(row.id)
                milestone = milestones.get(row.id)
                state = MilestoneState(milestone.state) if milestone else MilestoneState.ACTIVE
                kind = commit_kind(tree.nodes, key, state, has_children=key in parents)
                container = by_remote.get((tree.connection.id, row.remote_id))
                if kind is None or container is None:
                    continue
                theme = tree.theme_of(key)
                in_focus: bool | None = None
                if focus is not None:
                    in_focus = theme is not None and theme.id in focus
                out.append(
                    Candidate(
                        container=container,
                        connection=tree.connection,
                        path=_path(container, by_remote),
                        open_tasks=open_count.get(container.id, 0),
                        carried_tasks=carried.get(container.id, 0),
                        selected=container.id in chosen,
                        kind=kind,
                        milestone=milestone,
                        state=state,
                        theme=theme,
                        in_focus=in_focus,
                        rollover_count=milestone.rollover_count if milestone else 0,
                        needs_rescope=(
                            self._milestones.rescope_needed(rolls[milestone.id])
                            if milestone
                            else False
                        ),
                        decision_open=bool(milestone and milestone.id in open_decisions),
                    )
                )
        out.sort(
            key=lambda x: (
                focus is not None and not x.in_focus,
                x.carried_tasks == 0,
                x.path.casefold(),
            )
        )
        return out

    async def _open_decisions(self, db: AsyncSession, user_id: uuid.UUID) -> set[uuid.UUID]:
        """Return the milestones whose newest decision is "decide later" (FR-036)."""
        rows = (
            await db.execute(
                select(
                    WeeklyPlanProject.milestone_id,
                    WeeklyPlanProject.decision,
                    WeeklyPlan.week_start,
                    WeeklyPlanProject.decided_at,
                )
                .join(WeeklyPlan, WeeklyPlan.id == WeeklyPlanProject.plan_id)
                .where(
                    WeeklyPlan.user_id == user_id,
                    WeeklyPlanProject.milestone_id.is_not(None),
                    WeeklyPlanProject.decision.is_not(None),
                )
            )
        ).all()
        newest: dict[uuid.UUID, tuple[date, datetime, str]] = {}
        for milestone_id, decision, week, decided in rows:
            if milestone_id is None or decision is None:
                continue
            at = _aware(decided) if decided else datetime.min.replace(tzinfo=UTC)
            if milestone_id not in newest or (week, at) > newest[milestone_id][:2]:
                newest[milestone_id] = (week, at, decision)
        return {m for m, (_, _, d) in newest.items() if d == ReviewDecision.DECIDE_LATER.value}

    async def themes(self, db: AsyncSession, user_id: uuid.UUID, week: date) -> Themes:
        """List the themes for the picker headers and its empty states.

        Only live themes that are weekly-eligible (spec 003) are listed. A project with no label
        is listed only when it has subprojects, so that it acts as a theme. The focus themes come
        first when focus data exists.
        """
        focus = await self.focus_of(db, user_id, week)
        containers = {
            (c.connection_id, c.remote_id): c
            for c in (
                await db.execute(select(SourceContainer).where(SourceContainer.user_id == user_id))
            ).scalars()
        }
        milestones = await milestones_by_project(db, user_id)
        found: list[ThemeEntry] = []
        unsorted = 0
        for tree in await load_trees(db, user_id):
            parents = {n.parent_key for n in tree.nodes.values() if n.parent_key and not n.orphaned}
            counts: dict[str, list[int]] = {}
            for row in tree.rows:
                if row.label == ProjectLabel.MILESTONE.value and row.orphaned_reason is None:
                    theme = tree.theme_of(str(row.id))
                    if theme is not None:
                        m = milestones.get(row.id)
                        is_open = m is None or m.state in UNFINISHED
                        entry = counts.setdefault(str(theme.id), [0, 0])
                        entry[0] += 1
                        entry[1] += 1 if is_open else 0
                if row.label is None and row.orphaned_reason is None:
                    unsorted += 1
            for row in tree.rows:
                key = str(row.id)
                container = containers.get((tree.connection.id, row.remote_id))
                if (
                    container is None
                    or not is_weekly_eligible(tree.nodes, key)
                    or label_of(tree.nodes, key) is not ProjectLabel.THEME
                    or (row.label is None and key not in parents)
                ):
                    continue
                n, n_open = counts.get(key, [0, 0])
                found.append(
                    ThemeEntry(
                        row,
                        container,
                        tree.connection,
                        None if focus is None else row.id in focus,
                        n,
                        n_open,
                    )
                )
        found.sort(key=lambda t: (focus is not None and not t.in_focus, t.row.name.casefold()))
        return Themes(focus is not None, found, unsorted)

    async def _carried(
        self, db: AsyncSession, user_id: uuid.UUID, week: date, tasks: list[Task]
    ) -> dict[uuid.UUID, int]:
        """Return, per project, the open tasks of the milestones last recommitted."""
        last = await self._previous(db, user_id, week, reviewed_only=True)
        if last is None:
            return {}
        open_ids = {str(t.id) for t in tasks}
        out: dict[uuid.UUID, int] = {}
        for row in await self._rows(db, last):
            if (
                decision_of(row.decision, row.leftover_action) is ReviewDecision.RECOMMIT
                and row.container_id is not None
            ):
                n = sum(1 for tid in row.committed_task_ids if tid in open_ids)
                if n:
                    out[row.container_id] = n
        return out

    async def add_project(
        self, db: AsyncSession, user_id: uuid.UUID, plan: WeeklyPlan, container_id: uuid.UUID
    ) -> WeeklyPlanProject:
        """Add a milestone to the week. There is no limit: the cap only warns (FR-006).

        A project with no label and no subproject is labelled milestone first (history source
        ``user``). A theme, and a project with no label that has subprojects, are refused with
        ``not_a_milestone``. A project that may not be planned (maintenance, ignored, orphaned,
        inside a routine, or a milestone that is closed or done) is refused with
        ``not_eligible``. Adding the same project twice changes nothing (FR-014).
        """
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
        project = await project_of(db, container)
        tree = await tree_of(db, user_id, connection.id)
        assert tree is not None  # noqa: S101 - the connection is a task connection
        key = str(project.id)
        milestone = (
            await db.execute(select(Milestone).where(Milestone.project_id == project.id))
        ).scalar_one_or_none()
        state = MilestoneState(milestone.state) if milestone else MilestoneState.ACTIVE
        kind = commit_kind(tree.nodes, key, state)
        if kind is None:
            if not is_weekly_eligible(tree.nodes, key) or state not in (
                MilestoneState.ACTIVE,
                MilestoneState.PARKED,
            ):
                raise Invalid(
                    "This project cannot be planned: it is ignored, maintenance, "
                    "gone from the task app or finished.",
                    code="not_eligible",
                )
            raise Invalid(
                "A theme or a project with subprojects is not a milestone. "
                "Choose a milestone or create one under it.",
                code="not_a_milestone",
            )
        if kind is CommitKind.LABEL_THEN_COMMIT:
            await write_labels(
                db,
                [(project, ProjectLabel.MILESTONE)],
                now=self._clock(),
                batch_id=uuid.uuid4(),
                source="user",
            )
        milestone = await self._milestones.ensure(db, project, now=self._clock())
        return await self._add(
            db,
            plan,
            container,
            container.name,
            milestone,
            tree.theme_of(key),
            rows,
            created_here=False,
        )

    async def _add(
        self,
        db: AsyncSession,
        plan: WeeklyPlan,
        container: SourceContainer | None,
        name: str,
        milestone: Milestone,
        theme: ThemeRef | None,
        rows: list[WeeklyPlanProject],
        *,
        created_here: bool,
    ) -> WeeklyPlanProject:
        row = WeeklyPlanProject(
            plan_id=plan.id,
            container_id=container.id if container else None,
            name=name,
            position=max((r.position for r in rows), default=-1) + 1,
            created_here=created_here,
            committed_task_ids=[],
            milestone_id=milestone.id,
            theme_project_id=theme.id if theme else None,
            theme_name=theme.name if theme else None,
        )
        db.add(row)
        await db.flush()
        return row

    async def remove_project(
        self, db: AsyncSession, plan: WeeklyPlan, plan_project_id: uuid.UUID
    ) -> None:
        """Take a milestone out of the week. Its tasks keep the days they have."""
        self._editable(plan)
        row = await db.get(WeeklyPlanProject, plan_project_id)
        if row is None or row.plan_id != plan.id:
            raise NotFound
        await db.delete(row)
        await db.flush()

    async def create_milestone(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        plan: WeeklyPlan,
        parent_id: uuid.UUID,
        name: str,
        done_state: str,
    ) -> WeeklyPlanProject:
        """Create a milestone under a theme in the task app, label it and add it to the week.

        The done-state is checked first, before the task app is called (FR-009). Then the shared
        rule of spec 003 runs: the project is created in the task app, and only after that
        worked tefteri records the label, the done-state and the commitment (FR-010).
        """
        self._editable(plan)
        title = name.strip()
        if not title:
            raise Invalid("Give the new milestone a name.")
        clean_done_state = self._milestones.check_done_state(done_state)
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
        parent_row = await project_of(db, parent)
        tree = await tree_of(db, user_id, connection.id)
        assert tree is not None  # noqa: S101 - the connection is a task connection
        key = str(parent_row.id)
        if not is_weekly_eligible(tree.nodes, key) or label_of(tree.nodes, key) is not (
            ProjectLabel.THEME
        ):
            raise Invalid("A milestone is created under a theme. Choose a theme.")
        rows = await self._rows(db, plan)
        created = await self._classification.create_and_label(
            db, user_id, connection.id, title, parent_row.id, ProjectLabel.MILESTONE
        )
        container = await container_of(db, created.row)
        milestone = await self._milestones.ensure(
            db, created.row, clean_done_state, now=self._clock()
        )
        tree = await tree_of(db, user_id, connection.id)
        assert tree is not None  # noqa: S101
        return await self._add(
            db,
            plan,
            container,
            container.name if container else created.row.name,
            milestone,
            tree.theme_of(str(created.row.id)),
            rows,
            created_here=True,
        )

    async def add_task(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        plan: WeeklyPlan,
        plan_project_id: uuid.UUID,
        title: str,
    ) -> Task:
        """Create a task under the milestone of an entry in the task app (FR-012).

        The task is not committed until it gets a day. A committed plan refuses it.
        """
        self._editable(plan)
        row = await db.get(WeeklyPlanProject, plan_project_id)
        if row is None or row.plan_id != plan.id:
            raise NotFound
        clean = title.strip()
        if not clean:
            raise Invalid("Give the new task a title.")
        container = await db.get(SourceContainer, row.container_id) if row.container_id else None
        connection = await db.get(Connection, container.connection_id) if container else None
        if container is None or connection is None:
            raise Invalid("This project is not in your task app any more.")
        backend = cast(TaskBackend, await self._connections.backend_of_owner(db, connection))
        if Capability.CREATE_TASKS not in backend.capabilities():
            await guard(connection, _unsupported(Capability.CREATE_TASKS))
        return await self._tasks.create(
            db, user_id, connection_id=connection.id, title=clean, container_id=container.id
        )

    # -- reading the task app again -----------------------------------------------------------

    async def refresh(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        week: date,  # noqa: ARG002
        plans: list[WeeklyPlan],
        tz: str = "UTC",
    ) -> None:
        """Read the tasks of the chosen projects again from their task apps."""
        containers: dict[uuid.UUID, list[SourceContainer]] = {}
        milestone_ids: set[uuid.UUID] = set()
        for plan in plans:
            for row in await self._rows(db, plan):
                if row.milestone_id is not None:
                    milestone_ids.add(row.milestone_id)
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
        if milestone_ids:
            found = (
                await db.execute(select(Milestone).where(Milestone.id.in_(milestone_ids)))
            ).scalars()
            await self._settle(db, user_id, tz, list(found))

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
        """Set a task aside for this week (or put it back). The task app is not touched.

        The API keeps the word "parked" for this. The screens say "Not this week", because
        "parked" is the state of a milestone now.
        """
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
        """Fix the plan: remember which tasks are planned for the week, for the look-back.

        A plan with no milestone can be committed (the week then has only work outside the plan).
        The theme of each milestone is stored again, as it is at the time of the commit.
        """
        views = await self.project_views(db, user_id, plan, tz)
        trees: dict[uuid.UUID, ConnectionTree | None] = {}
        for v in views:
            v.row.committed_task_ids = [
                str(t.task.id) for t in v.open_tasks if t.planned_day is not None and not t.parked
            ]
            if v.milestone is None:
                continue
            project = await db.get(ProjectLabelRow, v.milestone.project_id)
            if project is None or project.orphaned_reason is not None:
                continue
            if project.connection_id not in trees:
                trees[project.connection_id] = await tree_of(db, user_id, project.connection_id)
            tree = trees[project.connection_id]
            theme = tree.theme_of(str(project.id)) if tree else None
            v.row.theme_project_id = theme.id if theme else None
            v.row.theme_name = theme.name if theme else None
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
        """Return how the last committed week before ``week`` went (``None`` if there was none).

        Each entry has its decision under the new names (an old ``carry`` shows as ``recommit``
        and an old ``backlog`` as ``park``, with ``legacy`` set). Nothing is written for an old
        entry. The summary holds the numbers of the week.
        """
        previous = await self._previous(db, user_id, week)
        if previous is None:
            return None
        end = previous.week_start + timedelta(days=7)
        rows = await self._rows(db, previous)
        milestones = await self._milestones_of(db, rows)
        if previous.reviewed_at is None:
            await self._settle(db, user_id, tz, list(milestones.values()))
        rolls = await self._milestones.rollovers(db, list(milestones))
        focus = await self.focus_of(db, user_id, previous.week_start)
        trees: dict[uuid.UUID, ConnectionTree | None] = {}
        can_move: dict[uuid.UUID, bool] = {}
        zone = ZoneInfo(tz)
        pace = {previous.week_start + timedelta(days=i): 0 for i in range(7)}
        done_by_theme: dict[uuid.UUID | None, int] = {}
        out = []
        for row in rows:
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
                elif t.completed_at is not None:
                    finished = _aware(t.completed_at).astimezone(zone).date()
                    if finished in pace:
                        pace[finished] += 1
            milestone = milestones.get(row.milestone_id) if row.milestone_id else None
            if previous.reviewed_at is not None:
                committed = row.reviewed_committed or 0
                done = row.reviewed_done or 0
                completed = row.outcome == "done"
            else:
                committed = len(planned)
                completed = (
                    milestone.state == MilestoneState.DONE.value
                    if milestone is not None
                    else committed > 0 and done == committed
                )
            container = (
                await db.get(SourceContainer, row.container_id) if row.container_id else None
            )
            decision = decision_of(row.decision, row.leftover_action)
            entry = LookBackProject(
                row,
                committed,
                done,
                leftover,
                completed,
                container.color if container else None,
                milestone=milestone,
                theme=self._theme_tag(row),
                decision=decision,
                legacy=milestone is None or (row.decision is None and decision is not None),
            )
            done_by_theme[row.theme_project_id] = done_by_theme.get(row.theme_project_id, 0) + done
            if milestone is not None:
                entry.rollover_count = milestone.rollover_count
                entry.needs_rescope = self._milestones.rescope_needed(rolls[milestone.id])
                entry.outside_focus = outside_focus(row.theme_project_id, focus)
                entry.close = await self._close_info(db, user_id, milestone, trees, can_move)
            out.append(entry)
        committed_total = sum(p.committed for p in out)
        done_total = sum(p.done for p in out)
        summary = Summary(
            committed_tasks=committed_total,
            done_tasks=done_total,
            milestones_committed=len(out),
            milestones_done=sum(1 for p in out if p.completed),
            pace=sorted(pace.items()),
            focus_share=focus_share(done_by_theme, focus) if committed_total else None,
            note=(
                None
                if committed_total
                else "No task was committed that week, so there are no numbers to show."
            ),
        )
        return LookBack(previous, out, summary)

    async def _close_info(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        milestone: Milestone,
        trees: dict[uuid.UUID, ConnectionTree | None],
        can_move: dict[uuid.UUID, bool],
    ) -> CloseInfo:
        project = await db.get(ProjectLabelRow, milestone.project_id)
        if project is None:
            return CloseInfo(False, None, 0, None)
        if project.connection_id not in trees:
            trees[project.connection_id] = await tree_of(db, user_id, project.connection_id)
            can_move[project.connection_id] = await self._milestones.can_move_tasks(
                db, await db.get(Connection, project.connection_id)
            )
        tree = trees[project.connection_id]
        theme = tree.theme_of(str(project.id)) if tree else None
        theme_name = theme.name if theme else None
        if milestone.state not in UNFINISHED:
            return CloseInfo(False, None, 0, theme_name)
        options = await self._milestones.close_availability(
            db, project, theme, can_move=can_move[project.connection_id]
        )
        if project.orphaned_reason is not None:
            return CloseInfo(False, options.reason, 0, theme_name)
        return CloseInfo(
            options.available,
            options.reason,
            await self._milestones.open_task_count(db, user_id, project),
            theme_name,
        )

    async def review(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        plan_id: uuid.UUID,
        tz: str,
        answers: list[Answer],
        reflection: str,
        now: datetime,
    ) -> ReviewResult:
        """Store the review: one decision for every unfinished milestone of the week.

        A milestone that is done needs none. ``recommit`` adds a rollover event and puts the
        milestone into the plan of the week after the reviewed one (a committed plan goes back
        to draft, with a notice). ``park`` sets the state ``parked``. ``decide_later`` and no
        answer change nothing (FR-036). ``close`` needs a milestone that is closed already.
        ``mark_done`` marks the milestone done by hand. The due dates of tasks are never
        touched, and the old ``leftover_action`` is never written.
        """
        plan = await db.get(WeeklyPlan, plan_id)
        if plan is None or plan.user_id != user_id or plan.status != "committed":
            raise NotFound
        if plan.reviewed_at is not None:
            raise Invalid("This week was reviewed already.")
        allowed = {d.value for d in ReviewDecision}
        for a in answers:
            if a.decision is not None and a.decision not in allowed:
                raise Invalid("A milestone can be recommitted, parked, closed or decided later.")
        by_id = {a.plan_project_id: a for a in answers}
        back = await self.look_back(db, user_id, plan.week_start + timedelta(days=7), tz)
        assert back is not None and back.plan.id == plan.id  # noqa: S101 - same plan, found above
        result = ReviewResult(plan)
        recommitted: list[Milestone] = []
        next_week = plan.week_start + timedelta(days=7)
        for p in back.projects:
            row = p.row
            answer = by_id.get(row.id, Answer(row.id))
            row.reviewed_committed = p.committed
            row.reviewed_done = p.done
            milestone = p.milestone
            if milestone is None and row.container_id is not None:
                milestone = await self._adopt(db, user_id, row)
                if milestone is not None and p.completed:
                    await self._milestones.mark_done(db, user_id, tz, milestone, now)
            if milestone is None:
                # An entry whose project is gone and that never had a milestone.
                row.outcome = "done" if p.completed or answer.mark_done else "not_done"
                continue
            if answer.mark_done and milestone.state in UNFINISHED:
                effect = await self._milestones.mark_done(db, user_id, tz, milestone, now)
                if effect.open_tasks:
                    result.notices.append(f"{row.name}: {effect.message}")
            if milestone.state == MilestoneState.DONE.value:
                row.outcome = "done"
                continue
            row.outcome = "not_done"
            row.decided_at = now
            if milestone.state == MilestoneState.CLOSED.value:
                if answer.decision not in (None, ReviewDecision.CLOSE.value):
                    raise Invalid(
                        "This milestone is closed already. Reopen it to decide again.",
                        code="not_unfinished",
                    )
                row.decision = ReviewDecision.CLOSE.value
                continue
            decision = ReviewDecision(answer.decision or ReviewDecision.DECIDE_LATER.value)
            if decision is ReviewDecision.CLOSE:
                raise Invalid(
                    f"Close {row.name} first and confirm it. "
                    "The review only records a close that is done.",
                    code="confirm_required",
                )
            row.decision = decision.value
            row.expected_rollover = answer.expected if decision is ReviewDecision.RECOMMIT else None
            if decision is ReviewDecision.PARK:
                self._milestones.set_state(milestone, MilestoneState.PARKED, now)
            elif decision is ReviewDecision.RECOMMIT:
                await self._recommit(
                    db,
                    user_id,
                    row,
                    milestone,
                    plan.week_start,
                    next_week,
                    answer.expected,
                    now,
                    result,
                )
                recommitted.append(milestone)
        plan.reviewed_at = now
        plan.reflection = reflection.strip()
        await db.flush()
        for milestone in recommitted:
            events = (await self._milestones.rollovers(db, [milestone.id]))[milestone.id]
            if self._milestones.rescope_needed(events):
                project = await db.get(ProjectLabelRow, milestone.project_id)
                result.nudges.append(Nudge(milestone.id, project.name if project else ""))
        # Archive last: the counts are stored, and the plan no longer waits for its review.
        for p in back.projects:
            wish = by_id.get(p.row.id)
            if wish is not None and wish.archive and p.row.container_id is not None:
                await self._projects.archive(db, user_id, p.row.container_id)
        return result

    async def _adopt(
        self, db: AsyncSession, user_id: uuid.UUID, row: WeeklyPlanProject
    ) -> Milestone | None:
        """Give an entry of a week that was committed before spec 004 its milestone row.

        This happens only when such a week is reviewed now. The project is not relabelled.
        """
        container = await db.get(SourceContainer, row.container_id) if row.container_id else None
        if container is None:
            return None
        project = await project_of(db, container)
        milestone = await self._milestones.ensure(db, project, now=self._clock())
        row.milestone_id = milestone.id
        tree = await tree_of(db, user_id, project.connection_id)
        theme = tree.theme_of(str(project.id)) if tree else None
        row.theme_project_id = theme.id if theme else None
        row.theme_name = theme.name if theme else None
        await db.flush()
        return milestone

    async def _recommit(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        row: WeeklyPlanProject,
        milestone: Milestone,
        from_week: date,
        to_week: date,
        expected: bool,
        now: datetime,
        result: ReviewResult,
    ) -> None:
        """Record the rollover and put the milestone into the next week's plan (FR-024)."""
        await self._milestones.add_rollover(
            db,
            milestone,
            plan_project_id=row.id,
            from_week=from_week,
            to_week=to_week,
            expected=expected,
            now=now,
        )
        if milestone.state == MilestoneState.PARKED.value:
            self._milestones.set_state(milestone, MilestoneState.ACTIVE, now)
        following = await self.start(db, user_id, to_week)
        if following.status == "committed":
            following.status = "draft"
            following.committed_at = None
            result.notices.append(
                "The plan of the next week went back to draft, so that you can pick tasks "
                "for the milestones that you recommitted."
            )
        rows = await self._rows(db, following)
        if any(r.milestone_id == milestone.id for r in rows):
            return
        project = await db.get(ProjectLabelRow, milestone.project_id)
        container = await container_of(db, project) if project else None
        theme = None
        if project is not None and project.orphaned_reason is None:
            tree = await tree_of(db, user_id, project.connection_id)
            theme = tree.theme_of(str(project.id)) if tree else None
        await self._add(
            db,
            following,
            container,
            container.name if container else row.name,
            milestone,
            theme,
            rows,
            created_here=False,
        )

    async def history(self, db: AsyncSession, user_id: uuid.UUID) -> list[HistoryEntry]:
        """List the reviewed weeks, newest first, with the decisions under the new names."""
        plans = (
            await db.execute(
                select(WeeklyPlan)
                .where(WeeklyPlan.user_id == user_id, WeeklyPlan.reviewed_at.is_not(None))
                .order_by(WeeklyPlan.week_start.desc())
            )
        ).scalars()
        entries = []
        for plan in plans:
            rows = await self._rows(db, plan)
            milestones = await self._milestones_of(db, rows)
            projects = []
            for row in rows:
                decision = decision_of(row.decision, row.leftover_action)
                milestone = milestones.get(row.milestone_id) if row.milestone_id else None
                projects.append(
                    HistoryProject(
                        row,
                        milestone,
                        decision,
                        legacy=milestone is None or (row.decision is None and decision is not None),
                    )
                )
            entries.append(HistoryEntry(plan, projects))
        return entries


def _path(
    container: SourceContainer, by_remote: dict[tuple[uuid.UUID, str], SourceContainer]
) -> str:
    names = [container.name]
    parent = by_remote.get((container.connection_id, container.parent_remote_id or ""))
    depth = 0
    while parent is not None and depth < 10:
        names.append(parent.name)
        parent = by_remote.get((container.connection_id, parent.parent_remote_id or ""))
        depth += 1
    return " › ".join(reversed(names))


async def _unsupported(capability: Capability) -> None:
    raise NotSupported(capability)
