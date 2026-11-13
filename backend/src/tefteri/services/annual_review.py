"""The annual review read model and its readers (spec 008).

The review reads stored monthly snapshots through :class:`SnapshotReader` (feature 007), the
annual plan and its history through :class:`PlanReader` (feature 006), and the count of what the
next year can inherit through :class:`SeedCounter` (also 006). ``main.py`` wires the real
services. The review never reads ``tasks``, ``milestones`` or ``weekly_plans`` and never writes
except a review note.
"""

import uuid
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from datetime import UTC, date, datetime
from typing import Any, Protocol
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.connection import Connection
from tefteri.db.models.goal import Goal
from tefteri.db.models.project_label import ProjectLabel as ProjectLabelRow
from tefteri.db.models.review_note import ReviewNote
from tefteri.db.models.user import User
from tefteri.domain.annual_plan import today_in, year_state
from tefteri.domain.annual_review import (
    MonthRange,
    YearSplit,
    contribution,
    coverage,
    deadline_line,
    distinct_milestones,
    empty_reason,
    key_result_outcome,
    last_value,
    link_months,
    month_key,
    month_statuses,
    months_of,
    moved_after_snapshot,
    peak,
    series,
    year_split,
)
from tefteri.domain.enums import MonthStatus, YearState
from tefteri.domain.snapshot_view import SnapshotView, read_snapshot
from tefteri.domain.work_categories import percentages
from tefteri.services.annual_plan import (
    AnnualPlan,
    GoalOut,
    KeyResultOut,
    PlanChangeOut,
)
from tefteri.services.errors import NotFound


class SnapshotReader(Protocol):
    """Read the current version of each month's snapshot of one year (R-01)."""

    async def current_snapshots(
        self, db: AsyncSession, user_id: uuid.UUID, year: int
    ) -> list[dict[str, object]]:
        """Return ``month``, ``version``, ``taken_at`` and ``snapshot`` oldest month first."""
        ...


class PlanReader(Protocol):
    """Read the annual plan and its append-only history (006)."""

    async def plan(self, db: AsyncSession, user_id: uuid.UUID, year: int, *, tz: str) -> AnnualPlan:
        """Return the goals, key results and links of one planning year."""
        ...

    async def history(self, db: AsyncSession, user_id: uuid.UUID, year: int) -> list[PlanChangeOut]:
        """Return the history of the year in time order."""
        ...


class SeedCounter(Protocol):
    """Count what annual planning offers for the next year (R-09)."""

    async def count(
        self, db: AsyncSession, user_id: uuid.UUID, year: int, *, from_year: int
    ) -> "SeedCount":
        """Return the unmet key results, links and whether the old year has a plan."""
        ...


@dataclass(frozen=True)
class SeedCount:
    """The numbers that the review shows for the next year (FR-018, FR-020)."""

    unmet_key_results: int
    links: int
    has_plan: bool


@dataclass(frozen=True)
class AnnualReviewSeedCounter:
    """Adapt ``AnnualPlanService.suggestions`` to the seed counter protocol (R-09)."""

    annual: Any

    async def count(
        self, db: AsyncSession, user_id: uuid.UUID, year: int, *, from_year: int
    ) -> SeedCount:
        """Count offered key results and links without writing anything."""
        found = await self.annual.suggestions(db, user_id, year, from_year=from_year)
        key_results = [key_result for goal in found for key_result in goal.key_results]
        return SeedCount(
            unmet_key_results=len(key_results),
            links=sum(len(key_result.theme_keys) for key_result in key_results),
            has_plan=bool(found),
        )


@dataclass(frozen=True)
class _MonthView:
    """A parsed snapshot with the month and version supplied by the feature-007 reader."""

    month: str
    version: int | None
    taken_at: datetime | None
    view: SnapshotView


def _utc(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value


def _local_day(value: datetime | None, tz: ZoneInfo) -> date | None:
    at = _utc(value)
    return None if at is None else at.astimezone(tz).date()


def _parse_snapshots(raw: Sequence[dict[str, object]]) -> list[_MonthView]:
    parsed: list[_MonthView] = []
    for item in raw:
        payload = item.get("snapshot")
        month = month_key(item.get("month"))
        if not month:
            month = month_key(payload.get("month") if isinstance(payload, dict) else None)
        if not month:
            continue
        version = item.get("version")
        taken_at = item.get("taken_at")
        parsed.append(
            _MonthView(
                month=month,
                version=version if isinstance(version, int) else None,
                taken_at=_utc(taken_at) if isinstance(taken_at, datetime) else None,
                view=read_snapshot(payload),
            )
        )
    parsed.sort(key=lambda snapshot: (snapshot.month, snapshot.version or 0))
    return parsed


class AnnualReviewService:
    """Build the read-only annual review of one planning year (FR-001, FR-027)."""

    def __init__(
        self,
        snapshots: SnapshotReader,
        plan: PlanReader,
        seeds: SeedCounter,
        *,
        clock: Callable[[], datetime] = lambda: datetime.now(UTC),
    ) -> None:
        """Keep the three readers and the injected clock."""
        self._snapshots = snapshots
        self._plan = plan
        self._seeds = seeds
        self._clock = clock

    async def review(self, db: AsyncSession, user_id: uuid.UUID, year: int) -> dict[str, Any]:
        """Build the whole review of ``year`` and change no row (FR-014, SC-002)."""
        user = await db.get(User, user_id)
        if user is None:
            raise NotFound
        tz = ZoneInfo(user.timezone)
        today = today_in(user.timezone, self._clock())
        state = year_state(year, today)
        raw_snapshots = await self._snapshots.current_snapshots(db, user_id, year)
        parsed = _parse_snapshots(raw_snapshots)
        views = [item.view for item in parsed]
        statuses = month_statuses(year, [item.month for item in parsed], today)
        covered = coverage(statuses, year=year, today=today)
        plan = await self._plan.plan(db, user_id, year, tz=user.timezone)
        history = await self._plan.history(db, user_id, year)
        goal_rows = await self._goal_rows(db, user_id, year)
        notes = await self._notes(db, user_id, year)
        projects = await self._projects(db, user_id, plan)
        connections = await self._connections(db, user_id, projects)
        split = year_split(views, year=year, today=today)

        goals = [
            self._goal(
                goal,
                state=state,
                year=year,
                today=today,
                tz=tz,
                parsed=parsed,
                history=history,
                projects=projects,
                connections=connections,
                retired_at=goal_rows.get(goal.id),
                note=notes.get(goal.id),
            )
            for goal in [*plan.goals, *plan.retired_goals]
        ]
        year_note = notes.get(None)
        reason = empty_reason(year_state=state, goals=len(goals), snapshots=len(parsed))
        next_year = await self._next_year(
            db, user_id, year, state=state, has_plan=bool(plan.goals or plan.retired_goals)
        )
        return {
            "year": year,
            "state": state,
            "in_progress": state == YearState.CURRENT.value,
            "rules": {"hit": "last_value_reaches_target", "differ_threshold": 0.25},
            "months": [
                {
                    "month": month,
                    "status": status.value,
                    "version": self._version(parsed, month),
                    "taken_at": self._taken_at(parsed, month),
                    "schema_version": self._schema_version(parsed, month),
                    "action": "open_monthly_review"
                    if status in (MonthStatus.MISSING, MonthStatus.OPEN)
                    else None,
                }
                for month, status in zip(months_of(year), statuses, strict=True)
            ],
            "coverage": {
                "stored": covered.stored,
                "expected": covered.expected,
                "missing": covered.missing,
            },
            "empty": None
            if reason is None
            else {"reason": reason, "actions": ["open_annual_plan"]},
            "goals": goals,
            "milestones_shipped": {
                "count": distinct_milestones(views),
                "months_covered": covered.stored,
            },
            "split": self._split_out(split),
            "drill_down": {
                "live": True,
                "route": "/statistics/tasks",
                "query": {"period": "year", "day": f"{year}-01-01"},
            },
            "next_year": next_year,
            "year_note": self._note_out(year_note),
        }

    # -- reading helpers ----------------------------------------------------------------------

    async def _goal_rows(
        self, db: AsyncSession, user_id: uuid.UUID, year: int
    ) -> dict[uuid.UUID, Goal]:
        rows = list(
            (
                await db.execute(
                    select(Goal).where(
                        Goal.user_id == user_id,
                        Goal.period_type == "year",
                        Goal.period_start == date(year, 1, 1),
                    )
                )
            ).scalars()
        )
        return {row.id: row for row in rows}

    async def _notes(
        self, db: AsyncSession, user_id: uuid.UUID, year: int
    ) -> dict[uuid.UUID | None, ReviewNote]:
        rows = list(
            (
                await db.execute(
                    select(ReviewNote).where(ReviewNote.user_id == user_id, ReviewNote.year == year)
                )
            ).scalars()
        )
        return {row.goal_id: row for row in rows}

    async def _projects(
        self, db: AsyncSession, user_id: uuid.UUID, plan: AnnualPlan
    ) -> dict[uuid.UUID, ProjectLabelRow]:
        ids = {
            link.project_id
            for goal in [*plan.goals, *plan.retired_goals]
            for key_result in goal.key_results
            for link in key_result.links
        }
        if not ids:
            return {}
        rows = list(
            (
                await db.execute(
                    select(ProjectLabelRow).where(
                        ProjectLabelRow.user_id == user_id, ProjectLabelRow.id.in_(ids)
                    )
                )
            ).scalars()
        )
        return {row.id: row for row in rows}

    async def _connections(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        projects: dict[uuid.UUID, ProjectLabelRow],
    ) -> dict[uuid.UUID, str]:
        ids = {row.connection_id for row in projects.values()}
        if not ids:
            return {}
        rows = list(
            (
                await db.execute(
                    select(Connection).where(Connection.user_id == user_id, Connection.id.in_(ids))
                )
            ).scalars()
        )
        return {row.id: row.display_name for row in rows}

    async def _next_year(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        year: int,
        *,
        state: str,
        has_plan: bool,
    ) -> dict[str, Any]:
        available = state != YearState.FUTURE.value
        if not available:
            return {
                "year": year + 1,
                "from_year": year,
                "available": False,
                "has_plan": has_plan,
                "unmet_key_results": 0,
                "links": 0,
            }
        found = await self._seeds.count(db, user_id, year + 1, from_year=year)
        return {
            "year": year + 1,
            "from_year": year,
            "available": True,
            "has_plan": has_plan,
            "unmet_key_results": found.unmet_key_results,
            "links": found.links,
        }

    @staticmethod
    def _version(parsed: Sequence[_MonthView], month: str) -> int | None:
        for item in parsed:
            if item.month == month:
                return item.version
        return None

    @staticmethod
    def _taken_at(parsed: Sequence[_MonthView], month: str) -> datetime | None:
        for item in parsed:
            if item.month == month:
                return item.taken_at
        return None

    @staticmethod
    def _schema_version(parsed: Sequence[_MonthView], month: str) -> int | None:
        for item in parsed:
            if item.month == month:
                return item.view.schema_version
        return None

    # -- goals and key results ---------------------------------------------------------------

    def _goal(
        self,
        goal: GoalOut,
        *,
        state: str,
        year: int,
        today: date,
        tz: ZoneInfo,
        parsed: Sequence[_MonthView],
        history: Sequence[PlanChangeOut],
        projects: dict[uuid.UUID, ProjectLabelRow],
        connections: dict[uuid.UUID, str],
        retired_at: Goal | None,
        note: ReviewNote | None,
    ) -> dict[str, Any]:
        views = [item.view for item in parsed]
        key_results = [
            self._key_result(
                key_result,
                goal_status=goal.status,
                state=state,
                year=year,
                today=today,
                tz=tz,
                parsed=parsed,
                views=views,
                history=history,
                projects=projects,
                connections=connections,
            )
            for key_result in goal.key_results
        ]
        counts = {"hit": 0, "missed": 0, "no_value": 0, "retired": 0, "in_progress": 0}
        for key_result in key_results:
            counts[key_result["outcome"]] += 1
        return {
            "id": str(goal.id),
            "title": goal.title,
            "status": goal.status,
            "retired_at": _utc(retired_at.retired_at) if retired_at is not None else None,
            "retired_reason": retired_at.retired_reason if retired_at is not None else None,
            "counts": counts,
            "flags": []
            if key_results
            else [{"code": "no_key_result", "actions": ["open_annual_plan"]}],
            "note": self._note_out(note),
            "key_results": key_results,
        }

    def _key_result(
        self,
        key_result: KeyResultOut,
        *,
        goal_status: str,
        state: str,
        year: int,
        today: date,
        tz: ZoneInfo,
        parsed: Sequence[_MonthView],
        views: Sequence[SnapshotView],
        history: Sequence[PlanChangeOut],
        projects: dict[uuid.UUID, ProjectLabelRow],
        connections: dict[uuid.UUID, str],
    ) -> dict[str, Any]:
        key_id = str(key_result.id)
        last = last_value(views, key_id)
        outcome = key_result_outcome(
            year_state=state,
            key_result_status=key_result.status,
            goal_status=goal_status,
            start_value=key_result.start_value,
            target=key_result.target,
            last=last,
        )
        deadline = deadline_line(
            views,
            key_id,
            start_value=key_result.start_value,
            target=key_result.target,
            deadline=key_result.deadline,
            year=year,
            today=today,
            tz=tz,
        )
        points = series(views, key_id, year=year, today=today)
        best = peak(points, key_result.start_value, key_result.target)
        after = moved_after_snapshot(
            last,
            current_value=key_result.current_value,
            current_at=key_result.current_at,
            year_state=state,
        )
        themes, flags = self._themes(
            key_result,
            views=views,
            parsed=parsed,
            tz=tz,
            projects=projects,
            connections=connections,
        )
        changes = [
            {
                "kind": row.kind,
                "field": row.field,
                "old_value": row.old_value,
                "new_value": row.new_value,
                "at": _utc(row.at),
            }
            for row in history
            if row.key_result_id == key_result.id
            and row.kind in ("key_result_edited", "key_result_retired", "key_result_restored")
        ]
        show_last = last if last is not None and outcome.value != "no_value" else None
        return {
            "id": key_id,
            "metric": key_result.metric,
            "kind": key_result.kind,
            "start_value": key_result.start_value,
            "target": key_result.target,
            "direction": "up" if key_result.target > key_result.start_value else "down",
            "deadline": key_result.deadline,
            "update_source": key_result.update_source,
            "status": key_result.status,
            "retired_at": _utc(key_result.retired_at),
            "outcome": outcome.value,
            "last_value": show_last.value if show_last is not None else None,
            "last_month": show_last.month if show_last is not None else None,
            "last_at": show_last.at if show_last is not None else None,
            "deadline_line": {
                "state": deadline.state.value,
                "value": deadline.value,
                "month": deadline.month,
            },
            "series": [
                {
                    "month": point.month,
                    "status": point.status.value,
                    "value": point.value,
                    "not_stored": point.not_stored,
                }
                for point in points
            ],
            "peak": None if best is None else {"value": best.value, "month": best.month},
            "moved_after_snapshot": after,
            "current_value": key_result.current_value,
            "changes": changes,
            "flags": flags,
            "themes": themes,
        }

    def _themes(
        self,
        key_result: KeyResultOut,
        *,
        views: Sequence[SnapshotView],
        parsed: Sequence[_MonthView],
        tz: ZoneInfo,
        projects: dict[uuid.UUID, ProjectLabelRow],
        connections: dict[uuid.UUID, str],
    ) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
        grouped: dict[uuid.UUID, dict[str, Any]] = {}
        for link in key_result.links:
            item = grouped.setdefault(
                link.project_id,
                {"links": [], "name": link.name, "label": link.label},
            )
            item["links"].append(link)
        themes: list[dict[str, Any]] = []
        reasons: list[dict[str, Any]] = []
        for project_id, item in grouped.items():
            ranges: list[MonthRange] = []
            for link in item["links"]:
                start = _local_day(link.started_at, tz) or date(link.started_at.year, 1, 1)
                end = _local_day(link.ended_at, tz)
                ranges.append(
                    MonthRange(start, end, link_months(start, end, key_result_year(key_result)))
                )
            project = projects.get(project_id)
            stored_name = self._stored_theme_name(views, str(project_id)) or item["name"]
            found = contribution(
                project_id=str(project_id),
                name=stored_name,
                ranges=ranges,
                snapshots=views,
                key_result_id=str(key_result.id),
                start_value=key_result.start_value,
                target=key_result.target,
            )
            milestones = self._theme_milestones(views, str(project_id), ranges)
            orphaned = None
            if project is not None and project.orphaned_reason is not None:
                orphaned = {
                    "reason": project.orphaned_reason,
                    "at": _utc(project.orphaned_at),
                }
            label = project.label if project is not None else item["label"]
            connection_id = str(project.connection_id) if project is not None else None
            themes.append(
                {
                    "project_id": str(project_id),
                    "connection_id": connection_id,
                    "connection_name": connections.get(project.connection_id)
                    if project is not None
                    else None,
                    "name": stored_name,
                    "label": label,
                    "orphaned": orphaned,
                    "ranges": [
                        {
                            "from": month_range.start,
                            "to": month_range.end,
                            "months": month_range.months,
                        }
                        for month_range in ranges
                    ],
                    "shipped": found.shipped,
                    "shipped_outside_focus": found.shipped_outside_focus,
                    "target_sum": found.target_sum,
                    "months_with_target": found.months_with_target,
                    "movement": None
                    if found.move is None
                    else {
                        "from": found.move.from_value,
                        "to": found.move.to_value,
                        "fraction": found.move.fraction,
                        "months": found.move.months,
                    },
                    "hint": found.hint.value if found.hint is not None else None,
                    "milestones": milestones,
                }
            )
            reason = self._link_state(project, item["label"])
            if reason is not None:
                reasons.append(
                    {
                        "project_id": str(project_id),
                        "name": stored_name,
                        "state": reason,
                    }
                )
        flags: list[dict[str, Any]] = []
        if not key_result.links:
            reasons.append({"project_id": None, "name": None, "state": "no_links"})
        if reasons:
            flags.append(
                {
                    "code": "no_usable_theme",
                    "reasons": reasons,
                    "actions": ["open_annual_plan"],
                }
            )
        return themes, flags

    @staticmethod
    def _link_state(project: ProjectLabelRow | None, fallback: str | None) -> str | None:
        if project is None:
            return "orphaned"
        if project.orphaned_reason is not None:
            return "orphaned"
        if project.label == "theme":
            return None
        if project.label is None:
            return "unclassified"
        if project.label == "ignored":
            return "ignored"
        return "relabelled"

    @staticmethod
    def _stored_theme_name(views: Sequence[SnapshotView], project_id: str) -> str | None:
        name: str | None = None
        for view in views:
            for theme in view.themes:
                if theme.project_id == project_id and theme.name:
                    name = theme.name
        return name

    @staticmethod
    def _theme_milestones(
        views: Sequence[SnapshotView], project_id: str, ranges: Sequence[MonthRange]
    ) -> list[dict[str, Any]]:
        found: dict[str, dict[str, Any]] = {}
        for view in views:
            month = month_key(view.month)
            for theme in view.themes:
                if theme.project_id != project_id:
                    continue
                for milestone in theme.milestones:
                    if milestone.milestone_id is None or milestone.done_on is None:
                        continue
                    if not any(
                        month_range.start <= milestone.done_on <= (month_range.end or date.max)
                        for month_range in ranges
                    ):
                        continue
                    found[milestone.milestone_id] = {
                        "milestone_id": milestone.milestone_id,
                        "name": milestone.name,
                        "done_on": milestone.done_on,
                        "month": month,
                        "in_focus": True,
                    }
            for outside in view.outside_focus:
                if outside.theme_project_id != project_id:
                    continue
                if outside.milestone_id is None or outside.done_on is None:
                    continue
                if not any(
                    month_range.start <= outside.done_on <= (month_range.end or date.max)
                    for month_range in ranges
                ):
                    continue
                found[outside.milestone_id] = {
                    "milestone_id": outside.milestone_id,
                    "name": outside.name,
                    "done_on": outside.done_on,
                    "month": month,
                    "in_focus": False,
                }
        return sorted(found.values(), key=lambda item: (item["done_on"], item["milestone_id"]))

    @staticmethod
    def _split_out(split: YearSplit) -> dict[str, Any]:
        return {
            "months_covered": split.months_covered,
            "counts": {
                "goal_aligned": split.counts.goal_aligned,
                "maintenance": split.counts.maintenance,
                "off_plan": split.counts.off_plan,
            },
            "total": split.total,
            "hidden": split.hidden,
            "percentages": {
                "goal_aligned": split.percentages.goal_aligned,
                "maintenance": split.percentages.maintenance,
                "off_plan": split.percentages.off_plan,
            },
            "months": [
                {
                    "month": row.month,
                    "status": row.status.value,
                    "counts": None
                    if row.counts is None
                    else {
                        "goal_aligned": row.counts.goal_aligned,
                        "maintenance": row.counts.maintenance,
                        "off_plan": row.counts.off_plan,
                    },
                    "hidden": row.counts.hidden if row.counts is not None else None,
                    "percentages": None
                    if row.counts is None
                    else {
                        "goal_aligned": percentages(row.counts).goal_aligned,
                        "maintenance": percentages(row.counts).maintenance,
                        "off_plan": percentages(row.counts).off_plan,
                    },
                    "not_stored": row.not_stored,
                }
                for row in split.months
            ],
            "trend_note": None,
        }

    @staticmethod
    def _note_out(note: ReviewNote | None) -> dict[str, Any] | None:
        if note is None:
            return None
        return {
            "id": str(note.id),
            "body": note.body,
            "updated_at": _utc(note.updated_at),
        }


def key_result_year(key_result: KeyResultOut) -> int:
    """Return the planning year of a key result (its deadline always falls in that year)."""
    return key_result.deadline.year
