"""The numbers of each week, and how they compare with the weeks before.

Everything here is a count: tasks, milestones and themes. Time is never measured. The numbers come
from what tefteri already stores: the committed plan of the week and its review, the work category
that each completed task got when it was completed, and the date on which a milestone became done.

A week that has ended is kept in ``weekly_metrics`` the first time that it is read, so that the
history does not change when a task is deleted in the task app later. It is made again when the
week is reviewed after that, because the review fixes the counts of the plan. The week that is
running is always worked out again.
"""

import uuid
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import date, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.milestone import Milestone
from tefteri.db.models.task import Task
from tefteri.db.models.weekly import WeeklyMetric, WeeklyPlan, WeeklyPlanProject
from tefteri.domain.enums import MilestoneState, SyncState
from tefteri.domain.periods import PeriodType, period_start
from tefteri.domain.work_categories import CategoryCounts, percentages
from tefteri.services.statistics import StatisticsService
from tefteri.services.work_scope import WorkScope

MAX_WEEKS = 52
"""The most weeks that one call returns."""


@dataclass(frozen=True)
class WeekMetrics:
    """The numbers of one week (Monday to Sunday)."""

    week_start: date
    finished: bool
    """The week has ended. The running week is not final."""
    has_plan: bool
    """A plan was committed for the week."""
    reviewed: bool
    committed_tasks: int
    committed_done: int
    milestones_committed: int
    milestones_done: int
    milestones_finished: int
    tasks_done: int
    goal_aligned: int
    maintenance: int
    off_plan: int
    themes_active: int

    @property
    def completion_percent(self) -> int | None:
        """Committed tasks that were done, in whole percent. ``None`` with no committed task."""
        if self.committed_tasks == 0:
            return None
        return round(100 * self.committed_done / self.committed_tasks)

    @property
    def goal_aligned_percent(self) -> int | None:
        """The share of goal-aligned work in the three categories. ``None`` with no work."""
        if self.tasks_done == 0:
            return None
        return percentages_of(self.goal_aligned, self.maintenance, self.off_plan)[0]

    @property
    def has_data(self) -> bool:
        """The week has something to compare: a committed task or a completed one."""
        return self.committed_tasks > 0 or self.tasks_done > 0


def percentages_of(goal_aligned: int, maintenance: int, off_plan: int) -> tuple[int, int, int]:
    """Whole percentages of the three work categories that add up to 100."""
    p = percentages(CategoryCounts(goal_aligned, maintenance, off_plan))
    return p.goal_aligned, p.maintenance, p.off_plan


class WeeklyMetricsService:
    """Work out, keep and list the numbers of the weeks."""

    def __init__(self, statistics: StatisticsService) -> None:
        """Read the counts of the work categories through ``statistics``."""
        self._statistics = statistics

    async def compute(
        self, db: AsyncSession, user_id: uuid.UUID, week_start: date, *, finished: bool
    ) -> WeekMetrics:
        """Work out the numbers of the week that starts on ``week_start``."""
        end = week_start + timedelta(days=7)
        plan = (
            await db.execute(
                select(WeeklyPlan).where(
                    WeeklyPlan.user_id == user_id,
                    WeeklyPlan.week_start == week_start,
                    WeeklyPlan.status == "committed",
                )
            )
        ).scalar_one_or_none()
        committed = done = milestones_done = 0
        milestones_committed = 0
        if plan is not None:
            rows = list(
                (
                    await db.execute(
                        select(WeeklyPlanProject).where(WeeklyPlanProject.plan_id == plan.id)
                    )
                ).scalars()
            )
            milestones_committed = len(rows)
            if plan.reviewed_at is not None:
                # The review fixed the counts of each milestone.
                committed = sum(r.reviewed_committed or 0 for r in rows)
                done = sum(r.reviewed_done or 0 for r in rows)
                milestones_done = sum(1 for r in rows if r.outcome == "done")
            else:
                committed, done, milestones_done = await self._open_plan(db, rows)
        finished_milestones = int(
            (
                await db.execute(
                    select(func.count())
                    .select_from(Milestone)
                    .where(
                        Milestone.user_id == user_id,
                        Milestone.state == MilestoneState.DONE.value,
                        Milestone.done_on >= week_start,
                        Milestone.done_on < end,
                    )
                )
            ).scalar_one()
        )
        counts = await self._statistics.counts(db, user_id, week_start, end)
        scope = await WorkScope.load(db, user_id)
        themes = {
            scope.theme_of_label(project)
            for project in await self._statistics.project_ids(db, user_id, week_start, end)
        }
        themes.discard(None)
        return WeekMetrics(
            week_start=week_start,
            finished=finished,
            has_plan=plan is not None,
            reviewed=plan is not None and plan.reviewed_at is not None,
            committed_tasks=committed,
            committed_done=done,
            milestones_committed=milestones_committed,
            milestones_done=milestones_done,
            milestones_finished=finished_milestones,
            tasks_done=counts.total,
            goal_aligned=counts.goal_aligned,
            maintenance=counts.maintenance,
            off_plan=counts.off_plan,
            themes_active=len(themes),
        )

    @staticmethod
    async def _open_plan(
        db: AsyncSession, rows: Sequence[WeeklyPlanProject]
    ) -> tuple[int, int, int]:
        """Count a plan that was not reviewed yet: committed tasks, done ones, done milestones."""
        ids: set[uuid.UUID] = set()
        for r in rows:
            ids.update(uuid.UUID(i) for i in r.committed_task_ids)
        done_ids: set[uuid.UUID] = set()
        if ids:
            done_ids = set(
                (
                    await db.execute(
                        select(Task.id).where(
                            Task.id.in_(ids),
                            Task.status == "done",
                            Task.sync_state != SyncState.DELETED_REMOTELY.value,
                        )
                    )
                ).scalars()
            )
        states: dict[uuid.UUID, str] = {}
        milestone_ids = [r.milestone_id for r in rows if r.milestone_id is not None]
        if milestone_ids:
            states = {
                m.id: m.state
                for m in (
                    await db.execute(select(Milestone).where(Milestone.id.in_(milestone_ids)))
                ).scalars()
            }
        committed = sum(len(r.committed_task_ids) for r in rows)
        done = 0
        milestones_done = 0
        for r in rows:
            mine = {uuid.UUID(i) for i in r.committed_task_ids}
            done_here = len(mine & done_ids)
            done += done_here
            state = states.get(r.milestone_id) if r.milestone_id else None
            if state == MilestoneState.DONE.value or (
                state is None and mine and done_here == len(mine)
            ):
                milestones_done += 1
        return committed, done, milestones_done

    async def trends(
        self, db: AsyncSession, user_id: uuid.UUID, today: date, weeks: int
    ) -> list[WeekMetrics]:
        """Return the numbers of the last ``weeks`` weeks, the running week last.

        A week that has ended comes from the table. When it is not there, or when the week was
        reviewed after it was kept, it is worked out and kept. The running week is not kept.
        """
        weeks = max(1, min(weeks, MAX_WEEKS))
        current = period_start(PeriodType.WEEK, today)
        starts = [current - timedelta(days=7 * i) for i in range(weeks - 1, -1, -1)]
        kept = {
            m.week_start: m
            for m in (
                await db.execute(
                    select(WeeklyMetric).where(
                        WeeklyMetric.user_id == user_id, WeeklyMetric.week_start.in_(starts)
                    )
                )
            ).scalars()
        }
        out: list[WeekMetrics] = []
        for start in starts:
            if start == current:
                out.append(await self.compute(db, user_id, start, finished=False))
                continue
            row = kept.get(start)
            if row is not None and (row.reviewed or not await self._reviewed(db, user_id, start)):
                out.append(_of(row))
                continue
            fresh = await self.compute(db, user_id, start, finished=True)
            if row is None:
                row = WeeklyMetric(user_id=user_id, week_start=start)
                db.add(row)
            _store(row, fresh)
            out.append(fresh)
        await db.flush()
        return out

    @staticmethod
    async def _reviewed(db: AsyncSession, user_id: uuid.UUID, week_start: date) -> bool:
        reviewed_at = (
            await db.execute(
                select(WeeklyPlan.reviewed_at).where(
                    WeeklyPlan.user_id == user_id,
                    WeeklyPlan.week_start == week_start,
                    WeeklyPlan.status == "committed",
                )
            )
        ).scalar_one_or_none()
        return reviewed_at is not None


def _of(row: WeeklyMetric) -> WeekMetrics:
    return WeekMetrics(
        week_start=row.week_start,
        finished=True,
        has_plan=row.committed_tasks > 0 or row.milestones_committed > 0,
        reviewed=row.reviewed,
        committed_tasks=row.committed_tasks,
        committed_done=row.committed_done,
        milestones_committed=row.milestones_committed,
        milestones_done=row.milestones_done,
        milestones_finished=row.milestones_finished,
        tasks_done=row.tasks_done,
        goal_aligned=row.goal_aligned,
        maintenance=row.maintenance,
        off_plan=row.off_plan,
        themes_active=row.themes_active,
    )


def _store(row: WeeklyMetric, m: WeekMetrics) -> None:
    row.reviewed = m.reviewed
    row.committed_tasks = m.committed_tasks
    row.committed_done = m.committed_done
    row.milestones_committed = m.milestones_committed
    row.milestones_done = m.milestones_done
    row.milestones_finished = m.milestones_finished
    row.tasks_done = m.tasks_done
    row.goal_aligned = m.goal_aligned
    row.maintenance = m.maintenance
    row.off_plan = m.off_plan
    row.themes_active = m.themes_active
