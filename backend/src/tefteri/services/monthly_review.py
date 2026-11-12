"""Monthly review drafts, key-result values, suggestions and immutable snapshots."""

import math
import uuid
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from typing import Protocol
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from tefteri.db.models.key_result import KeyResultTheme
from tefteri.db.models.milestone import Milestone
from tefteri.db.models.monthly import (
    FocusChange,
    MonthlyFocus,
    MonthlyFocusEntry,
    MonthlyReview,
    MonthlyReviewSnapshot,
)
from tefteri.db.models.project_label import ProjectLabel as ProjectLabelRow
from tefteri.db.models.user import User
from tefteri.domain.classification import is_eligible, label_of
from tefteri.domain.enums import (
    FocusChangeKind,
    FocusEntryStatus,
    KeyResultUpdate,
    ThemeDecision,
    TrendState,
    ValueSource,
)
from tefteri.domain.monthly import (
    CategoryCounts,
    DecisionInput,
    DoneMilestone,
    EntryWindow,
    FocusChangeInput,
    KeyResultInput,
    MonthlyReviewInput,
    OutsideFocusInput,
    SuggestionEligibility,
    SuggestionResult,
    ThemeInput,
    after_month_end,
    build_payload,
    build_suggestions,
    classify_done,
    decision_effect,
    key_result_flags,
    key_result_status,
    month_bounds,
    off_plan_share,
    planning_year_of,
    shared_key_results,
    trend,
)
from tefteri.domain.periods import PeriodType as StatisticsPeriodType
from tefteri.services.annual_plan import AnnualPlanService, KeyResultOut
from tefteri.services.errors import (
    ConfirmRequired,
    FutureMonth,
    Invalid,
    NoSuchVersion,
    NotAFocusTheme,
    NotFound,
)
from tefteri.services.key_results import KeyResultService, SeriesPoint
from tefteri.services.project_labels import ConnectionTree, load_trees
from tefteri.services.statistics import StatisticsService


class CategoryCountsReader(Protocol):
    """Read feature-005 month counts without recalculating task categories."""

    async def month_counts(
        self, db: AsyncSession, user_id: uuid.UUID, month_start: date
    ) -> CategoryCounts | None:
        """Return the stored counts for one month, or ``None`` when statistics are unavailable."""
        ...


class StatisticsCategoryCountsReader:
    """Adapt feature-005 monthly summaries to the feature-007 count value."""

    def __init__(
        self,
        statistics: StatisticsService,
        *,
        clock: Callable[[], datetime] = lambda: datetime.now(UTC),
    ) -> None:
        """Keep the statistics service and clock needed by the month-summary call."""
        self._statistics = statistics
        self._clock = clock

    async def month_counts(
        self, db: AsyncSession, user_id: uuid.UUID, month_start: date
    ) -> CategoryCounts | None:
        """Return non-empty, available summary counts; do not make a second category calculation."""
        user = await db.get(User, user_id)
        if user is None:
            raise NotFound
        today = self._clock().astimezone(ZoneInfo(user.timezone)).date()
        summary = await self._statistics.summary(
            db,
            user_id,
            user.timezone,
            StatisticsPeriodType.MONTH,
            month_start,
            today,
        )
        counts = summary.counts
        if not summary.available or counts.total == 0 and counts.hidden == 0:
            return None
        return CategoryCounts(
            goal_aligned=counts.goal_aligned,
            maintenance=counts.maintenance,
            off_plan=counts.off_plan,
            hidden=counts.hidden,
        )


@dataclass(frozen=True)
class ReviewTrend:
    """The display-only off-plan share and comparison with two earlier months."""

    state: str
    share: float | None
    previous: tuple[dict[str, object], ...]


@dataclass(frozen=True)
class ReviewEffect:
    """One review decision and its user-facing effect line."""

    project_id: uuid.UUID
    decision: str
    message: str


@dataclass(frozen=True)
class MonthlyReviewDraft:
    """A live review payload and derived display values; it has not been persisted."""

    month: date
    snapshot: dict[str, object]
    trend: ReviewTrend
    categories_note: str | None
    effects: tuple[ReviewEffect, ...]
    value_prompts: tuple[uuid.UUID, ...]


@dataclass(frozen=True)
class ReviewStoreResult:
    """A real save or a no-write preview of the next immutable snapshot version."""

    version: int
    snapshot: dict[str, object]
    values_written: list[dict[str, str]]
    effects: tuple[ReviewEffect, ...]
    will_create_version: int


@dataclass(frozen=True)
class ReviewVersion:
    """One immutable snapshot version and its creation time."""

    version: int
    taken_at: datetime
    current: bool


@dataclass(frozen=True)
class ReviewRead:
    """The current or requested stored snapshot, or a fresh draft when none exists."""

    month: date
    stored: bool
    draft: bool
    version: int | None
    current_version: int | None
    taken_at: datetime | None
    snapshot: dict[str, object]


def _month_start(day: date) -> date:
    """Normalize any date to the first day of its month."""
    return date(day.year, day.month, 1)


def _utc(value: datetime) -> datetime:
    """Normalize timestamps from SQLite and PostgreSQL for range comparisons."""
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)


def _previous_month(month: date, offset: int) -> date:
    """Return the first day of a previous calendar month."""
    year, number = month.year, month.month - offset
    while number <= 0:
        year -= 1
        number += 12
    return date(year, number, 1)


def _decision_inputs(
    raw: Sequence[DecisionInput | Mapping[str, object]] | None,
    themes: Sequence[ThemeInput],
    project_rows: Mapping[uuid.UUID, ProjectLabelRow],
    trees_by_id: Mapping[uuid.UUID, ConnectionTree],
) -> tuple[DecisionInput, ...]:
    """Normalize decisions, apply the implicit later choice and validate replacements."""
    by_id: dict[uuid.UUID, DecisionInput] = {}
    for item in raw or ():
        if isinstance(item, DecisionInput):
            project_id = uuid.UUID(item.project_id)
            theme = next((theme for theme in themes if theme.project_id == str(project_id)), None)
            if theme is None:
                raise NotFound
            replacement_id = (
                uuid.UUID(item.replacement_project_id)
                if item.replacement_project_id is not None
                else None
            )
            replacement_name = item.replacement_name
            choice = item.decision
            if choice is ThemeDecision.REPLACE:
                replacement = project_rows.get(replacement_id) if replacement_id else None
                tree = trees_by_id.get(replacement_id) if replacement_id else None
                if (
                    replacement_id == project_id
                    or replacement is None
                    or tree is None
                    or replacement.orphaned_reason is not None
                    or replacement.label != "theme"
                    or not is_eligible(tree.nodes, str(replacement_id))
                    or label_of(tree.nodes, str(replacement_id)).value != "theme"
                ):
                    raise NotAFocusTheme()
                replacement_name = replacement_name or replacement.name
            by_id[project_id] = DecisionInput(
                project_id=str(project_id),
                name=theme.name,
                decision=choice,
                target=theme.target,
                replacement_project_id=(
                    str(replacement_id) if replacement_id is not None else None
                ),
                replacement_name=replacement_name,
            )
            continue
        else:
            raw_id = item.get("project_id")
            try:
                project_id = raw_id if isinstance(raw_id, uuid.UUID) else uuid.UUID(str(raw_id))
                choice = ThemeDecision(str(item.get("decision", "later")))
            except (ValueError, TypeError):
                raise Invalid("Choose carry, drop, replace or later.") from None
            theme = next((theme for theme in themes if theme.project_id == str(project_id)), None)
            if theme is None:
                raise NotFound
            replacement_raw = item.get("replacement_project_id")
            replacement_id = None
            replacement_name = None
            if replacement_raw is not None:
                try:
                    replacement_id = (
                        replacement_raw
                        if isinstance(replacement_raw, uuid.UUID)
                        else uuid.UUID(str(replacement_raw))
                    )
                except ValueError:
                    raise NotAFocusTheme() from None
                replacement = project_rows.get(replacement_id)
                tree = trees_by_id.get(replacement_id)
                if (
                    replacement_id == project_id
                    or replacement is None
                    or tree is None
                    or replacement.orphaned_reason is not None
                    or replacement.label != "theme"
                    or not is_eligible(tree.nodes, str(replacement_id))
                    or label_of(tree.nodes, str(replacement_id)).value != "theme"
                ):
                    raise NotAFocusTheme()
                replacement_name = replacement.name
            if choice is ThemeDecision.REPLACE and replacement_id is None:
                raise NotAFocusTheme()
            if project_id in by_id:
                raise Invalid("Choose one decision for each theme.")
            by_id[project_id] = DecisionInput(
                project_id=str(project_id),
                name=theme.name,
                decision=choice,
                target=theme.target,
                replacement_project_id=(
                    str(replacement_id) if replacement_id is not None else None
                ),
                replacement_name=replacement_name,
            )
    for theme in themes:
        project_id = uuid.UUID(theme.project_id)
        by_id.setdefault(
            project_id,
            DecisionInput(
                project_id=theme.project_id,
                name=theme.name,
                decision=ThemeDecision.LATER,
                target=theme.target,
            ),
        )
    return tuple(by_id[uuid.UUID(theme.project_id)] for theme in themes)


class MonthlyReviewService:
    """Build live monthly reviews and append immutable snapshot versions."""

    def __init__(
        self,
        annual: AnnualPlanService,
        key_results: KeyResultService,
        category_reader: CategoryCountsReader,
        *,
        clock: Callable[[], datetime] = lambda: datetime.now(UTC),
    ) -> None:
        """Use feature services for annual plans, dated values and stored category counts."""
        self._annual = annual
        self._key_results = key_results
        self._category_reader = category_reader
        self._clock = clock

    async def draft(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        month: date,
        *,
        tz: str,
        key_result_values: Mapping[uuid.UUID | str, float] | None = None,
        value_times: Mapping[uuid.UUID, datetime] | None = None,
        decisions: Sequence[DecisionInput | Mapping[str, object]] | None = None,
    ) -> MonthlyReviewDraft:
        """Calculate a live review without storing a snapshot or contacting an adapter."""
        month = _month_start(month)
        zone = ZoneInfo(tz)
        start, end = month_bounds(month)
        today = self._clock().astimezone(zone).date()
        if month > _month_start(today):
            raise FutureMonth()

        focus = (
            await db.execute(
                select(MonthlyFocus).where(
                    MonthlyFocus.user_id == user_id, MonthlyFocus.month == start
                )
            )
        ).scalar_one_or_none()
        entries: list[MonthlyFocusEntry] = []
        if focus is not None:
            entries = list(
                (
                    await db.execute(
                        select(MonthlyFocusEntry)
                        .where(MonthlyFocusEntry.focus_id == focus.id)
                        .order_by(MonthlyFocusEntry.position, MonthlyFocusEntry.created_at)
                    )
                ).scalars()
            )
        trees = await load_trees(db, user_id)
        tree_by_project = {row.id: tree for tree in trees for row in tree.rows}
        project_rows = {row.id: row for tree in trees for row in tree.rows}
        trees_by_id = {row_id: tree for row_id, tree in tree_by_project.items()}

        theme_label = aliased(ProjectLabelRow)
        done_rows = (
            await db.execute(
                select(Milestone, ProjectLabelRow.name, theme_label.name)
                .join(ProjectLabelRow, ProjectLabelRow.id == Milestone.project_id)
                .outerjoin(theme_label, theme_label.id == Milestone.done_theme_id)
                .where(
                    Milestone.user_id == user_id,
                    Milestone.state == "done",
                    Milestone.done_on >= start,
                    Milestone.done_on < end,
                )
                .order_by(Milestone.done_on, ProjectLabelRow.name, Milestone.id)
            )
        ).all()
        done_milestones: list[DoneMilestone] = []
        done_theme_names: dict[str, str | None] = {}
        for milestone, project_name, theme_name in done_rows:
            if milestone.done_on is None:
                continue
            theme_id = str(milestone.done_theme_id) if milestone.done_theme_id else None
            done_milestones.append(
                DoneMilestone(str(milestone.id), project_name, milestone.done_on, theme_id)
            )
            if theme_id is not None:
                done_theme_names[theme_id] = theme_name or milestone.done_theme_name

        windows = [
            EntryWindow(
                project_id=str(entry.project_id),
                name=project_rows[entry.project_id].name
                if entry.project_id in project_rows
                else entry.name,
                target=entry.target,
                counts_from=entry.counts_from,
                left_on=entry.left_on,
                left_reason=(
                    FocusEntryStatus(entry.left_reason) if entry.left_reason is not None else None
                ),
            )
            for entry in entries
        ]
        results, outside = classify_done(start, windows, done_milestones)
        entries_by_id = {str(entry.project_id): entry for entry in entries}
        focus_theme_ids = {str(entry.project_id) for entry in entries}
        annual_plan = await self._annual.plan(
            db,
            user_id,
            planning_year_of(start),
            tz=tz,
        )
        key_result_rows: dict[uuid.UUID, KeyResultOut] = {}
        goal_titles: dict[uuid.UUID, str] = {}
        for goal in [*annual_plan.goals, *annual_plan.retired_goals]:
            for key_result in goal.key_results:
                key_result_rows[key_result.id] = key_result
                goal_titles[key_result.id] = goal.title

        link_map: dict[uuid.UUID, list[KeyResultTheme]] = {}
        month_begin = datetime.combine(start, time.min, zone).astimezone(UTC)
        review_cutoff = (
            datetime.combine(end, time.min, zone) - timedelta(microseconds=1)
        ).astimezone(UTC)
        for key_result_id in key_result_rows:
            history = await self._key_results.all_links(db, key_result_id)
            valid = [
                link
                for link in history
                if _utc(link.started_at) <= review_cutoff
                and (link.ended_at is None or _utc(link.ended_at) >= month_begin)
            ]
            if valid:
                link_map[key_result_id] = valid

        linked_by_theme: dict[str, list[str]] = {}
        for key_result_id, links in link_map.items():
            for link in links:
                linked_by_theme.setdefault(str(link.project_id), []).append(str(key_result_id))
        theme_inputs: list[ThemeInput] = []
        for result in results:
            project_id = uuid.UUID(result.project_id)
            entry = entries_by_id[result.project_id]
            project = project_rows.get(project_id)
            status = (
                FocusEntryStatus.IN_FOCUS
                if entry.left_on is None
                else FocusEntryStatus(entry.left_reason or FocusEntryStatus.REMOVED.value)
            )
            theme_inputs.append(
                ThemeInput(
                    project_id=result.project_id,
                    name=result.name,
                    target=result.target,
                    counts_from=result.counts_from,
                    done=result.milestones,
                    earlier_not_counted=result.earlier_not_counted,
                    left_on=entry.left_on,
                    status=status,
                    orphaned=project.orphaned_reason if project is not None else "missing",
                    label_changed=(
                        project.label
                        if project is not None and project.label not in (None, "theme")
                        else None
                    ),
                    key_result_ids=tuple(linked_by_theme.get(result.project_id, ())),
                )
            )
        theme_names = {item.project_id: item.name for item in theme_inputs}
        outside_inputs = tuple(
            OutsideFocusInput(
                milestone=item.milestone,
                theme_name=(
                    theme_names.get(item.theme_project_id)
                    or done_theme_names.get(item.theme_project_id)
                    if item.theme_project_id is not None
                    else None
                ),
            )
            for item in outside
        )

        raw_values: dict[uuid.UUID, float] = {}
        for key, value in (key_result_values or {}).items():
            try:
                result_id = key if isinstance(key, uuid.UUID) else uuid.UUID(str(key))
            except ValueError:
                raise NotFound from None
            if (
                not isinstance(value, (int, float))
                or isinstance(value, bool)
                or not math.isfinite(value)
            ):
                raise Invalid("The value must be a finite number.")
            if result_id not in key_result_rows:
                raise NotFound
            raw_values[result_id] = float(value)

        kr_inputs: list[KeyResultInput] = []
        key_result_links = {
            str(result_id): tuple(dict.fromkeys(str(link.project_id) for link in result_links))
            for result_id, result_links in link_map.items()
        }
        shared = shared_key_results(key_result_links, focus_theme_ids)
        today_at = self._clock()
        default_value_at = self._clock().astimezone(zone)
        month_end = end
        for key_result_id, row in key_result_rows.items():
            result_links = link_map.get(key_result_id)
            if not result_links:
                continue
            key_result_row = await self._key_results.get(db, user_id, key_result_id)
            series = await self._key_results.series(db, user_id, key_result_row)
            start_on = await self._key_results.value_on(db, user_id, key_result_id, start)
            start_value = row.start_value if start_on.value is None else start_on.value
            latest: SeriesPoint | None = series[0] if series else None
            latest_value = row.start_value if latest is None else latest.value
            latest_at = None if latest is None else latest.at
            entered = key_result_id in raw_values
            if entered:
                latest_value = raw_values[key_result_id]
                latest_at = (value_times or {}).get(key_result_id, default_value_at)
            theme_ids = key_result_links[str(key_result_id)]
            flags = [str(flag.get("code")) for flag in row.flags if flag.get("code")]
            usable_ids = []
            for link in links:
                linked_row = project_rows.get(link.project_id)
                tree = tree_by_project.get(link.project_id)
                if (
                    linked_row is not None
                    and tree is not None
                    and linked_row.orphaned_reason is None
                    and is_eligible(tree.nodes, str(link.project_id))
                    and label_of(tree.nodes, str(link.project_id)).value == "theme"
                ):
                    usable_ids.append(str(link.project_id))
            flags = list(key_result_flags(usable_ids, focus_theme_ids, flags))
            if row.deadline < today and "past_deadline" not in flags:
                flags.append("past_deadline")
            kr_inputs.append(
                KeyResultInput(
                    key_result_id=str(key_result_id),
                    goal_id=str(row.goal_id),
                    goal_title=goal_titles[key_result_id],
                    metric=row.metric,
                    update_source=row.update_source,
                    start_value=row.start_value,
                    base_value=start_value,
                    latest_value=latest_value,
                    latest_at=latest_at,
                    target=row.target,
                    deadline=row.deadline,
                    theme_ids=theme_ids,
                    status=(
                        KeyResultUpdate.UPDATED
                        if entered
                        else key_result_status(latest_at, start, zone)
                    ),
                    entered_in_review=entered,
                    after_month_end=after_month_end(latest_at, month_end, zone),
                    past_deadline=row.deadline < today,
                    retired=row.retired_at is not None or row.status != "active",
                    shared=key_result_id in shared,
                    flags=tuple(flags),
                )
            )
        current_counts = await self._category_reader.month_counts(db, user_id, start)
        previous_counts = [
            await self._category_reader.month_counts(db, user_id, _previous_month(start, offset))
            for offset in (1, 2)
        ]
        categories = current_counts or CategoryCounts()
        previous = [item if item is not None else CategoryCounts() for item in previous_counts]
        trend_state = (
            trend(categories, previous)
            if current_counts is not None and all(item is not None for item in previous_counts)
            else TrendState.NOT_ENOUGH_HISTORY
        )
        previous_shares: tuple[dict[str, object], ...] = tuple(
            {
                "month": _previous_month(start, offset).isoformat(),
                "share": None if counts is None else off_plan_share(counts),
            }
            for offset, counts in zip((1, 2), previous_counts, strict=True)
        )
        current_share = off_plan_share(categories)

        focus_changes: list[FocusChangeInput] = []
        if focus is not None:
            log_rows = list(
                (
                    await db.execute(
                        select(FocusChange)
                        .where(FocusChange.focus_id == focus.id)
                        .order_by(FocusChange.created_at, FocusChange.id)
                    )
                ).scalars()
            )
            undone_batches = {row.undoes_batch_id for row in log_rows if row.undoes_batch_id}
            focus_changes = [
                FocusChangeInput(
                    kind=FocusChangeKind(row.kind),
                    changed_on=row.changed_on,
                    out_project_id=str(row.out_project_id) if row.out_project_id else None,
                    out_name=row.out_name,
                    in_project_id=str(row.in_project_id) if row.in_project_id else None,
                    in_name=row.in_name,
                    target_before=row.target_before,
                    target_after=row.target_after,
                    undone=row.batch_id in undone_batches,
                )
                for row in log_rows
            ]
        project_rows_by_id = project_rows
        normalized_decisions = _decision_inputs(
            decisions,
            theme_inputs,
            project_rows_by_id,
            trees_by_id,
        )
        review_input = MonthlyReviewInput(
            month=start,
            taken_at=today_at,
            themes=tuple(theme_inputs),
            changes=tuple(focus_changes),
            outside_focus=outside_inputs,
            categories=categories,
            key_results=tuple(kr_inputs),
            decisions=normalized_decisions,
        )
        snapshot = build_payload(review_input)
        prompts = tuple(
            uuid.UUID(item.key_result_id)
            for item in kr_inputs
            if item.update_source == "manual" and not item.retired
        )
        effects = tuple(
            ReviewEffect(
                project_id=uuid.UUID(item.project_id),
                decision=item.decision.value,
                message=decision_effect(
                    item.decision,
                    target=item.target,
                    replacement_name=item.replacement_name,
                ),
            )
            for item in normalized_decisions
        )
        return MonthlyReviewDraft(
            month=start,
            snapshot=snapshot,
            trend=ReviewTrend(trend_state.value, current_share, previous_shares),
            categories_note="no_data" if current_counts is None else None,
            effects=effects,
            value_prompts=prompts,
        )

    async def store(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        month: date,
        *,
        tz: str,
        key_result_values: Mapping[uuid.UUID | str, float] | None = None,
        decisions: Sequence[DecisionInput | Mapping[str, object]] | None = None,
        confirm_new_version: bool = False,
        dry_run: bool = False,
    ) -> ReviewStoreResult:
        """Write manual values and add a new immutable snapshot in the caller's transaction."""
        month = _month_start(month)
        existing = await self._review_header(db, user_id, month)
        if existing is not None and not confirm_new_version:
            raise ConfirmRequired()
        if existing is None:
            version = 1
        else:
            latest_version = await db.scalar(
                select(MonthlyReviewSnapshot.version)
                .where(MonthlyReviewSnapshot.review_id == existing.id)
                .order_by(MonthlyReviewSnapshot.version.desc())
                .limit(1)
            )
            version = (latest_version or 0) + 1
        before = await self.draft(
            db,
            user_id,
            month,
            tz=tz,
            key_result_values=key_result_values,
            decisions=decisions,
        )
        if dry_run:
            return ReviewStoreResult(version, before.snapshot, [], before.effects, version)

        user = await db.get(User, user_id)
        if user is None:
            raise NotFound
        today = self._clock().astimezone(ZoneInfo(tz)).date()
        values_written: list[dict[str, str]] = []
        value_times: dict[uuid.UUID, datetime] = {}
        for raw_id, value in (key_result_values or {}).items():
            key_result_id = raw_id if isinstance(raw_id, uuid.UUID) else uuid.UUID(str(raw_id))
            row = await self._key_results.get(db, user_id, key_result_id)
            series = await self._key_results.series(db, user_id, row)
            if series and series[0].on_date == today and series[0].value == float(value):
                value_times[key_result_id] = series[0].at
                continue
            value_row, _ = await self._key_results.enter_value(
                db,
                user_id,
                row,
                float(value),
                today,
                tz=tz,
                source=ValueSource.MANUAL,
            )
            values_written.append(
                {"key_result_id": str(key_result_id), "value_id": str(value_row.id)}
            )
            value_times[key_result_id] = value_row.at
        final = await self.draft(
            db,
            user_id,
            month,
            tz=tz,
            key_result_values=key_result_values,
            value_times=value_times,
            decisions=decisions,
        )
        if existing is None:
            existing = MonthlyReview(
                user_id=user_id,
                month=month,
                current_version=version,
                current_changed_at=self._clock(),
            )
            db.add(existing)
            await db.flush()
        snapshot = MonthlyReviewSnapshot(
            review_id=existing.id,
            version=version,
            schema_version=1,
            payload=final.snapshot,
            values_written=values_written,
            created_at=self._clock(),
        )
        db.add(snapshot)
        existing.current_version = version
        existing.current_changed_at = self._clock()
        await db.flush()
        return ReviewStoreResult(version, final.snapshot, values_written, final.effects, version)

    async def _review_header(
        self, db: AsyncSession, user_id: uuid.UUID, month: date
    ) -> MonthlyReview | None:
        """Find the user's review header for a normalized month."""
        return (
            await db.execute(
                select(MonthlyReview).where(
                    MonthlyReview.user_id == user_id,
                    MonthlyReview.month == _month_start(month),
                )
            )
        ).scalar_one_or_none()

    async def versions(
        self, db: AsyncSession, user_id: uuid.UUID, month: date
    ) -> list[ReviewVersion]:
        """List snapshot versions for one owned month, oldest first."""
        header = await self._review_header(db, user_id, month)
        if header is None:
            return []
        rows = list(
            (
                await db.execute(
                    select(MonthlyReviewSnapshot)
                    .where(MonthlyReviewSnapshot.review_id == header.id)
                    .order_by(MonthlyReviewSnapshot.version)
                )
            ).scalars()
        )
        return [
            ReviewVersion(row.version, row.created_at, row.version == header.current_version)
            for row in rows
        ]

    async def review(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        month: date,
        *,
        version: int | None = None,
        tz: str = "UTC",
    ) -> ReviewRead | MonthlyReviewDraft:
        """Read a stored snapshot verbatim, falling back to a live draft when none exists."""
        month = _month_start(month)
        header = await self._review_header(db, user_id, month)
        if header is None:
            return await self.draft(db, user_id, month, tz=tz)
        selected = version if version is not None else header.current_version
        row = (
            await db.execute(
                select(MonthlyReviewSnapshot).where(
                    MonthlyReviewSnapshot.review_id == header.id,
                    MonthlyReviewSnapshot.version == selected,
                )
            )
        ).scalar_one_or_none()
        if row is None:
            raise NoSuchVersion
        return ReviewRead(
            month,
            True,
            False,
            row.version,
            header.current_version,
            row.created_at,
            row.payload,
        )

    async def make_current(
        self, db: AsyncSession, user_id: uuid.UUID, month: date, version: int
    ) -> None:
        """Move the review header pointer without changing any immutable snapshot row."""
        header = await self._review_header(db, user_id, month)
        if header is None:
            raise NoSuchVersion
        exists = await db.scalar(
            select(MonthlyReviewSnapshot.id).where(
                MonthlyReviewSnapshot.review_id == header.id,
                MonthlyReviewSnapshot.version == version,
            )
        )
        if exists is None:
            raise NoSuchVersion
        header.current_version = version
        header.current_changed_at = self._clock()
        await db.flush()

    async def current_snapshots(
        self, db: AsyncSession, user_id: uuid.UUID, year: int
    ) -> list[dict[str, object]]:
        """Return each month's current stored snapshot for the annual-review reader."""
        start = date(year, 1, 1)
        end = date(year + 1, 1, 1)
        headers = list(
            (
                await db.execute(
                    select(MonthlyReview)
                    .where(
                        MonthlyReview.user_id == user_id,
                        MonthlyReview.month >= start,
                        MonthlyReview.month < end,
                    )
                    .order_by(MonthlyReview.month)
                )
            ).scalars()
        )
        output: list[dict[str, object]] = []
        for header in headers:
            snapshot = (
                await db.execute(
                    select(MonthlyReviewSnapshot).where(
                        MonthlyReviewSnapshot.review_id == header.id,
                        MonthlyReviewSnapshot.version == header.current_version,
                    )
                )
            ).scalar_one_or_none()
            if snapshot is not None:
                output.append(
                    {
                        "month": header.month.strftime("%Y-%m"),
                        "version": snapshot.version,
                        "taken_at": snapshot.created_at,
                        "snapshot": snapshot.payload,
                    }
                )
        return output

    async def suggestions(
        self, db: AsyncSession, user_id: uuid.UUID, month: date
    ) -> SuggestionResult:
        """Build suggestions from the newest earlier stored current snapshot, checking 003."""
        month = _month_start(month)
        header = (
            await db.execute(
                select(MonthlyReview)
                .where(MonthlyReview.user_id == user_id, MonthlyReview.month < month)
                .order_by(MonthlyReview.month.desc())
                .limit(1)
            )
        ).scalar_one_or_none()
        if header is None:
            return build_suggestions(month, None, (), {})
        snapshot = (
            await db.execute(
                select(MonthlyReviewSnapshot).where(
                    MonthlyReviewSnapshot.review_id == header.id,
                    MonthlyReviewSnapshot.version == header.current_version,
                )
            )
        ).scalar_one_or_none()
        if snapshot is None:
            return build_suggestions(month, None, (), {})
        trees = await load_trees(db, user_id)
        rows = {row.id: row for tree in trees for row in tree.rows}
        tree_by_id = {row.id: tree for tree in trees for row in tree.rows}
        decisions: list[DecisionInput] = []
        eligibility: dict[str, SuggestionEligibility] = {}
        stored_decisions = snapshot.payload.get("decisions")
        if not isinstance(stored_decisions, list):
            return build_suggestions(month, header.month, (), {})
        stored_themes = snapshot.payload.get("themes")
        if not isinstance(stored_themes, list):
            stored_themes = []
        for item in stored_decisions:
            if not isinstance(item, dict):
                continue
            project_id = str(item.get("project_id", ""))
            decision = ThemeDecision(str(item.get("decision", "later")))
            replacement_id = item.get("replacement_project_id")
            decisions.append(
                DecisionInput(
                    project_id=project_id,
                    name=str(item.get("name", "")),
                    decision=decision,
                    target=next(
                        (
                            theme.get("target")
                            for theme in stored_themes
                            if isinstance(theme, dict) and theme.get("project_id") == project_id
                        ),
                        None,
                    ),
                    replacement_project_id=(
                        str(replacement_id) if replacement_id is not None else None
                    ),
                    replacement_name=(
                        str(item["replacement_name"])
                        if item.get("replacement_name") is not None
                        else None
                    ),
                )
            )
            proposed_ids = [project_id]
            if decision is ThemeDecision.REPLACE and replacement_id is not None:
                proposed_ids = [str(replacement_id)]
            for proposed in proposed_ids:
                try:
                    project_uuid = uuid.UUID(proposed)
                except ValueError:
                    eligibility[proposed] = SuggestionEligibility(False, "missing")
                    continue
                row = rows.get(project_uuid)
                tree = tree_by_id.get(project_uuid)
                reason = self._eligibility_reason(row, tree)
                eligibility[proposed] = SuggestionEligibility(reason is None, reason)
        return build_suggestions(month, header.month, decisions, eligibility)

    @staticmethod
    def _eligibility_reason(row: ProjectLabelRow | None, tree: ConnectionTree | None) -> str | None:
        """Return the 003 eligibility reason for a next-month suggested theme."""
        if row is None or tree is None:
            return "missing"
        if row.orphaned_reason is not None:
            return "orphaned"
        if row.label == "ignored":
            return "ignored"
        if row.label != "theme" or label_of(tree.nodes, str(row.id)).value != "theme":
            return "relabelled"
        if not is_eligible(tree.nodes, str(row.id)):
            return "ignored"
        return None
