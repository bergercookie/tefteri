"""Statistics of completed tasks by work category (spec 005).

Every number here is read from the stored ``task_categories`` rows. Nothing is recomputed: a
category is decided once by the recorder (``services.category_recorder``). A day is one grouped
query, a week or a month is the sum of its days and a year is the sum of its months, so the views
always agree (FR-009). Lists load in pages with a keyset cursor, so they have no cap (FR-012).

A row counts while its task is done, the completion time of the task still equals the one the row
was decided for, and the task app did not delete the task (research R-07, R-08).

Feature 007 reads ``daily_counts`` and ``counts`` to store its snapshots. They give counts, never
shares.
"""

import base64
import binascii
import json
import uuid
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from typing import Any
from zoneinfo import ZoneInfo

from sqlalchemy import ColumnElement, and_, case, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.connection import Connection, SourceContainer
from tefteri.db.models.project_label import ProjectLabel as ProjectLabelRow
from tefteri.db.models.sync import SyncRun
from tefteri.db.models.task import Task
from tefteri.db.models.task_category import TaskCategory
from tefteri.db.models.weekly import WeeklyPlan, WeeklyPlanProject
from tefteri.domain.enums import CategoryReason, ConnectionKind, SyncState, WorkCategory
from tefteri.domain.periods import PeriodType, period_end, period_start
from tefteri.domain.week_progress import CommittedTask, WeekProgress, week_progress
from tefteri.domain.work_categories import CategoryCounts, Percentages, percentages
from tefteri.services.commitments import CommitmentProvider
from tefteri.services.errors import Invalid

MAX_LIMIT = 200
DEFAULT_LIMIT = 50
ORDERS = ("newest", "project")
WORK_CATEGORIES = (WorkCategory.GOAL_ALIGNED, WorkCategory.MAINTENANCE, WorkCategory.OFF_PLAN)


@dataclass(frozen=True)
class Part:
    """One day (week, month) or one month (year) of a period."""

    start: date
    end: date
    counts: CategoryCounts


@dataclass(frozen=True)
class EmptyState:
    """Why a period shows no number, and what the user can do about it."""

    reason: str  # no_tasks | no_labels
    action: str  # plan_week | label_projects


@dataclass(frozen=True)
class SyncInfo:
    """When the task apps were last synced, and how that sync ended."""

    last_synced_at: datetime | None
    outcome: str | None  # ok | auth_expired | unreachable | error


@dataclass(frozen=True)
class Summary:
    """The counts of one period."""

    period: PeriodType
    start: date
    end: date
    available: bool
    unavailable_reason: str | None
    counts: CategoryCounts
    percentages: Percentages
    unsorted: int
    part_kind: str  # day | month
    parts: list[Part]
    empty: EmptyState | None
    sync: SyncInfo
    progress: WeekProgress | None


@dataclass(frozen=True)
class StatTask:
    """A completed task with its stored category."""

    id: uuid.UUID
    title: str
    completed_at: datetime
    completed_day: date
    category: WorkCategory
    reason: CategoryReason
    unsorted: bool
    project_id: uuid.UUID | None
    project_name: str | None
    project_color: str | None
    orphaned: bool
    connection_id: uuid.UUID
    remote_id: str


@dataclass(frozen=True)
class TaskPage:
    """One page of completed tasks."""

    total: int
    items: list[StatTask]
    next_cursor: str | None


def parse_period(value: str) -> PeriodType:
    """Return the period type or raise ``Invalid``."""
    try:
        return PeriodType(value)
    except ValueError:
        raise Invalid("period must be week, month or year") from None


def parse_category(value: str | None) -> WorkCategory | None:
    """Return the category filter or raise ``Invalid``."""
    if value is None:
        return None
    try:
        return WorkCategory(value)
    except ValueError:
        raise Invalid("category must be goal_aligned, maintenance, off_plan or hidden") from None


def _counted() -> list[ColumnElement[bool]]:
    """The conditions under which a stored row counts."""
    return [
        Task.status == "done",
        Task.completed_at == TaskCategory.completed_at,
        Task.sync_state != SyncState.DELETED_REMOTELY.value,
    ]


def _months(start: date, end: date) -> list[tuple[date, date]]:
    out = []
    cursor = start
    while cursor < end:
        nxt = period_end(PeriodType.MONTH, cursor)
        out.append((cursor, nxt))
        cursor = nxt
    return out


class StatisticsService:
    """Read the stored categories: counts, lists, week progress."""

    def __init__(self, commitments: CommitmentProvider) -> None:
        """``commitments`` tells whether the weekly commitment can be read (FR-026)."""
        self._commitments = commitments

    # -- counts ------------------------------------------------------------------------------

    async def daily_counts(
        self, db: AsyncSession, user_id: uuid.UUID, start: date, end: date
    ) -> dict[date, CategoryCounts]:
        """Return the counts of every day of ``[start, end)``, zeros included. Read only."""
        rows = (
            await db.execute(
                select(TaskCategory.completed_on, TaskCategory.category, func.count())
                .join(Task, Task.id == TaskCategory.task_id)
                .where(
                    TaskCategory.user_id == user_id,
                    TaskCategory.completed_on >= start,
                    TaskCategory.completed_on < end,
                    *_counted(),
                )
                .group_by(TaskCategory.completed_on, TaskCategory.category)
            )
        ).all()
        out: dict[date, CategoryCounts] = {}
        day = start
        while day < end:
            out[day] = CategoryCounts()
            day += timedelta(days=1)
        for day, category, n in rows:
            out[day] = out[day] + CategoryCounts.one(WorkCategory(category), n)
        return out

    async def counts(
        self, db: AsyncSession, user_id: uuid.UUID, start: date, end: date
    ) -> CategoryCounts:
        """Return the counts of ``[start, end)``: the sum of ``daily_counts``."""
        total = CategoryCounts()
        for counts in (await self.daily_counts(db, user_id, start, end)).values():
            total = total + counts
        return total

    async def _unsorted(self, db: AsyncSession, user_id: uuid.UUID, start: date, end: date) -> int:
        return int(
            (
                await db.execute(
                    select(func.count())
                    .select_from(TaskCategory)
                    .join(Task, Task.id == TaskCategory.task_id)
                    .where(
                        TaskCategory.user_id == user_id,
                        TaskCategory.completed_on >= start,
                        TaskCategory.completed_on < end,
                        TaskCategory.unsorted.is_(True),
                        TaskCategory.category != WorkCategory.HIDDEN.value,
                        *_counted(),
                    )
                )
            ).scalar_one()
        )

    async def _sync_info(self, db: AsyncSession, user_id: uuid.UUID) -> SyncInfo:
        run = (
            await db.execute(
                select(SyncRun)
                .join(Connection, Connection.id == SyncRun.connection_id)
                .where(SyncRun.user_id == user_id, Connection.kind == ConnectionKind.TASKS.value)
                .order_by(SyncRun.started_at.desc())
                .limit(1)
            )
        ).scalar_one_or_none()
        if run is None:
            return SyncInfo(None, None)
        outcome = "ok" if run.outcome == "ok" else (run.error or run.outcome)
        return SyncInfo(run.finished_at or run.started_at, outcome)

    async def summary(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        tz: str,
        period: PeriodType,
        day: date,
        today: date,
    ) -> Summary:
        """Return the counts, parts, percentages and empty state of the period holding ``day``."""
        start = period_start(period, day)
        end = period_end(period, start)
        week = period_start(PeriodType.WEEK, start)
        sync = await self._sync_info(db, user_id)
        part_kind = "month" if period is PeriodType.YEAR else "day"
        available = await self._commitments.committed_projects(db, user_id, week) is not None
        if not available:
            ranges = (
                _months(start, end)
                if period is PeriodType.YEAR
                else [
                    (start + timedelta(days=i), start + timedelta(days=i + 1))
                    for i in range((end - start).days)
                ]
            )
            return Summary(
                period,
                start,
                end,
                False,
                "weekly_commitment_unavailable",
                CategoryCounts(),
                percentages(CategoryCounts()),
                0,
                part_kind,
                [Part(a, b, CategoryCounts()) for a, b in ranges],
                None,
                sync,
                None,
            )
        daily = await self.daily_counts(db, user_id, start, end)
        if period is PeriodType.YEAR:
            parts = []
            for a, b in _months(start, end):
                month = CategoryCounts()
                for d, c in daily.items():
                    if a <= d < b:
                        month = month + c
                parts.append(Part(a, b, month))
        else:
            parts = [Part(d, d + timedelta(days=1), c) for d, c in daily.items()]
        counts = CategoryCounts()
        for part in parts:
            counts = counts + part.counts
        empty = None
        if counts.total == 0 and counts.hidden == 0:
            labelled = (
                await db.execute(
                    select(func.count())
                    .select_from(ProjectLabelRow)
                    .where(ProjectLabelRow.user_id == user_id, ProjectLabelRow.label.is_not(None))
                )
            ).scalar_one()
            empty = (
                EmptyState("no_tasks", "plan_week")
                if labelled
                else EmptyState("no_labels", "label_projects")
            )
        progress = (
            await self.progress(db, user_id, tz, start, today)
            if period is PeriodType.WEEK
            else None
        )
        return Summary(
            period,
            start,
            end,
            True,
            None,
            counts,
            percentages(counts),
            await self._unsorted(db, user_id, start, end),
            part_kind,
            parts,
            empty,
            sync,
            progress,
        )

    # -- week progress -----------------------------------------------------------------------

    async def progress(
        self, db: AsyncSession, user_id: uuid.UUID, tz: str, week: date, today: date
    ) -> WeekProgress | None:
        """Return the progress of the committed plan of ``week``, or ``None`` with no such plan."""
        plan = (
            await db.execute(
                select(WeeklyPlan).where(
                    WeeklyPlan.user_id == user_id,
                    WeeklyPlan.week_start == week,
                    WeeklyPlan.status == "committed",
                )
            )
        ).scalar_one_or_none()
        if plan is None:
            return None
        promised: set[str] = set()
        for ids in (
            await db.execute(
                select(WeeklyPlanProject.committed_task_ids).where(
                    WeeklyPlanProject.plan_id == plan.id
                )
            )
        ).scalars():
            promised.update(ids or [])
        tasks: list[Task] = []
        if promised:
            ids_ = [uuid.UUID(x) for x in promised]
            for i in range(0, len(ids_), 500):
                tasks.extend(
                    (
                        await db.execute(
                            select(Task).where(
                                Task.user_id == user_id,
                                Task.id.in_(ids_[i : i + 500]),
                                Task.sync_state != SyncState.DELETED_REMOTELY.value,
                            )
                        )
                    ).scalars()
                )
        zone = ZoneInfo(tz)
        committed = []
        for t in tasks:
            done_day = None
            if t.completed_at is not None:
                at = t.completed_at if t.completed_at.tzinfo else t.completed_at.replace(tzinfo=UTC)
                done_day = at.astimezone(zone).date()
            committed.append(CommittedTask(t.status == "done", done_day))
        return week_progress(committed, week, today)

    # -- lists -------------------------------------------------------------------------------

    async def tasks(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        *,
        period: PeriodType,
        day: date,
        category: WorkCategory | None,
        order: str,
        limit: int,
        cursor: str | None,
    ) -> tuple[date, date, TaskPage]:
        """Return one page of the completed tasks of a period, and the range of the period.

        ``category`` ``None`` lists the three work categories. Paging is by keyset: a task that
        is completed while the user pages never shifts the next page.
        """
        if order not in ORDERS:
            raise Invalid("order must be newest or project")
        if not 1 <= limit <= MAX_LIMIT:
            raise Invalid(f"limit must be from 1 to {MAX_LIMIT}")
        start = period_start(period, day)
        end = period_end(period, start)
        key = f"{period.value}|{start}|{category.value if category else ''}|{order}"
        where: list[ColumnElement[bool]] = [
            TaskCategory.user_id == user_id,
            TaskCategory.completed_on >= start,
            TaskCategory.completed_on < end,
            *_counted(),
        ]
        where.append(
            TaskCategory.category == category.value
            if category is not None
            else TaskCategory.category != WorkCategory.HIDDEN.value
        )
        total = int(
            (
                await db.execute(
                    select(func.count())
                    .select_from(TaskCategory)
                    .join(Task, Task.id == TaskCategory.task_id)
                    .where(*where)
                )
            ).scalar_one()
        )
        no_project = case((TaskCategory.project_name.is_(None), 1), else_=0)
        folded = func.coalesce(func.lower(TaskCategory.project_name), "")
        sort: list[ColumnElement[Any]]
        if order == "newest":
            sort = [TaskCategory.completed_at.desc(), TaskCategory.task_id.desc()]
        else:
            sort = [
                no_project.asc(),
                folded.asc(),
                TaskCategory.completed_at.desc(),
                TaskCategory.task_id.desc(),
            ]
        if cursor is not None:
            where.append(self._after(order, self._decode(cursor, key, order), no_project, folded))
        rows = (
            await db.execute(
                select(
                    TaskCategory,
                    Task,
                    ProjectLabelRow.orphaned_reason,
                    SourceContainer.color,
                    no_project,
                    folded,
                )
                .join(Task, Task.id == TaskCategory.task_id)
                .outerjoin(ProjectLabelRow, ProjectLabelRow.id == TaskCategory.project_id)
                .outerjoin(
                    SourceContainer,
                    and_(
                        SourceContainer.connection_id == ProjectLabelRow.connection_id,
                        SourceContainer.remote_id == ProjectLabelRow.remote_id,
                    ),
                )
                .where(*where)
                .order_by(*sort)
                .limit(limit + 1)
            )
        ).all()
        page = rows[:limit]
        items = [
            StatTask(
                id=task.id,
                title=task.title,
                completed_at=row.completed_at,
                completed_day=row.completed_on,
                category=WorkCategory(row.category),
                reason=CategoryReason(row.reason),
                unsorted=row.unsorted,
                project_id=row.project_id,
                project_name=row.project_name,
                project_color=color,
                orphaned=orphaned is not None,
                connection_id=task.connection_id,
                remote_id=task.remote_id,
            )
            for row, task, orphaned, color, _flag, _name in page
        ]
        next_cursor = None
        if len(rows) > limit:
            row, task, _o, _c, flag, name = page[-1]
            keys: list[object] = (
                [row.completed_at.isoformat(), str(task.id)]
                if order == "newest"
                else [flag, name, row.completed_at.isoformat(), str(task.id)]
            )
            next_cursor = self._encode(key, keys)
        return start, end, TaskPage(total, items, next_cursor)

    @staticmethod
    def _encode(key: str, keys: list[object]) -> str:
        raw = json.dumps({"f": key, "k": keys}, separators=(",", ":")).encode()
        return base64.urlsafe_b64encode(raw).decode().rstrip("=")

    @staticmethod
    def _decode(cursor: str, key: str, order: str) -> list[object]:
        try:
            data = json.loads(base64.urlsafe_b64decode(cursor + "=" * (-len(cursor) % 4)))
            keys = data["k"]
            ok = (
                data["f"] == key
                and isinstance(keys, list)
                and len(keys) == (2 if order == "newest" else 4)
            )
        except (ValueError, KeyError, TypeError, binascii.Error):
            ok = False
        if not ok:
            raise Invalid("This cursor does not belong to this list.", "invalid_cursor")
        try:
            parsed: list[object] = [
                *keys[:-2],
                datetime.fromisoformat(str(keys[-2])),
                uuid.UUID(str(keys[-1])),
            ]
        except ValueError:
            raise Invalid("This cursor does not belong to this list.", "invalid_cursor") from None
        return parsed

    @staticmethod
    def _after(
        order: str, keys: list[object], no_project: ColumnElement[int], folded: ColumnElement[str]
    ) -> ColumnElement[bool]:
        at, tid = keys[-2], keys[-1]
        newest = or_(
            TaskCategory.completed_at < at,
            and_(TaskCategory.completed_at == at, TaskCategory.task_id < tid),
        )
        if order == "newest":
            return newest
        flag, name = keys[0], keys[1]
        return or_(
            no_project > flag,
            and_(
                no_project == flag,
                or_(folded > name, and_(folded == name, newest)),
            ),
        )
