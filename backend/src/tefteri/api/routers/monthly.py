"""Monthly planning and review routes (spec 007)."""

import re
import uuid
from datetime import date, datetime
from typing import Any

from fastapi import APIRouter, Query, Request, Response
from pydantic import BaseModel, Field

from tefteri.api.deps import CurrentUser, Db
from tefteri.domain.enums import (
    CountNote,
    FocusChangeKind,
    FocusChangeSource,
    FocusEntryStatus,
    KeyResultUpdate,
    MonthlyFlagCode,
    MonthState,
    OrphanReason,
    ProjectLabel,
    SkippedSuggestionReason,
    TargetMarker,
    ThemeDecision,
    ThemeSuggestionReason,
    TrendState,
    UpdateSource,
)
from tefteri.domain.monthly import CategoryCounts, off_plan_share, trend
from tefteri.services.errors import Invalid, NoSuchVersion
from tefteri.services.monthly_focus import FocusDraft, MonthlyFocusService
from tefteri.services.monthly_review import (
    MonthlyReviewService,
    ReviewRead,
    ReviewTrend,
)

router = APIRouter(prefix="/monthly", tags=["monthly planning"])
_MONTH_RE = re.compile(r"^[0-9]{4}-(0[1-9]|1[0-2])$")


def _month(value: str) -> date:
    """Parse the contract's strict YYYY-MM path format."""
    if _MONTH_RE.fullmatch(value) is None:
        raise Invalid("Month must use YYYY-MM.")
    try:
        return date.fromisoformat(f"{value}-01")
    except ValueError as exc:
        raise Invalid("Month must use YYYY-MM.") from exc


def _focus(request: Request) -> MonthlyFocusService:
    return request.app.state.monthly_focus_service


def _review(request: Request) -> MonthlyReviewService:
    return request.app.state.monthly_review_service


class FocusEntryIn(BaseModel):
    """A selected theme and the optional milestone-count target."""

    project_id: uuid.UUID
    target: Any = None


class FocusSaveIn(BaseModel):
    """The complete month focus or a no-write preview."""

    entries: list[FocusEntryIn]
    dry_run: bool = False


class FocusChangeIn(BaseModel):
    """One add, swap, remove or target update."""

    kind: FocusChangeKind
    out_project_id: uuid.UUID | None = None
    in_project_id: uuid.UUID | None = None
    target: Any = None
    dry_run: bool = False


class UndoIn(BaseModel):
    """The batch to undo."""

    batch_id: uuid.UUID


class KeyResultValueIn(BaseModel):
    """A key result value to include when finishing a review."""

    key_result_id: uuid.UUID
    value: float


class ThemeDecisionIn(BaseModel):
    """A month-end decision for a focused theme."""

    project_id: uuid.UUID
    decision: ThemeDecision
    replacement_project_id: uuid.UUID | None = None


class ReviewStoreIn(BaseModel):
    """Review decisions and optional values, or a no-write preview."""

    key_result_values: list[KeyResultValueIn] = Field(default_factory=list)
    decisions: list[ThemeDecisionIn] = Field(default_factory=list)
    confirm_new_version: bool = False
    dry_run: bool = False


class MakeCurrentIn(BaseModel):
    """Select a previously stored review version."""

    version: int = Field(ge=1)
    dry_run: bool = False


class OrphanOut(BaseModel):
    """Why a stored focus entry is no longer a live project."""

    reason: OrphanReason
    at: datetime


class MonthlyEntryOut(BaseModel):
    """One monthly focus entry and its result markers."""

    id: uuid.UUID
    project_id: uuid.UUID
    connection_id: uuid.UUID
    name: str
    target: int | None
    counts_from: date
    left_on: date | None
    status: FocusEntryStatus
    done: int
    earlier_not_counted: int
    marker: TargetMarker | None
    orphaned: OrphanOut | None
    label_changed: ProjectLabel | None
    linked_key_results: int
    last_month_done: int


class MonthlyKeyResultFlagOut(BaseModel):
    """A monthly key-result flag and its available actions or reasons."""

    code: MonthlyFlagCode
    actions: list[str] = Field(default_factory=list)
    reasons: list[dict[str, Any]] = Field(default_factory=list)


class MonthlyKeyResultOut(BaseModel):
    """An annual key result relevant to this month's focus."""

    id: uuid.UUID
    goal_id: uuid.UUID
    goal_title: str
    metric: str
    start_value: float
    current_value: float
    current_at: datetime | None
    target: float
    deadline: date
    update_source: UpdateSource
    past_deadline: bool
    theme_ids: list[uuid.UUID]
    flags: list[MonthlyKeyResultFlagOut]


class MonthlyPlanOut(BaseModel):
    """The planning read model for one month."""

    month: str
    start: date
    end: date
    state: MonthState
    planning_year: int
    focus_known: bool
    count_note: CountNote | None
    entries: list[MonthlyEntryOut]
    key_results: list[MonthlyKeyResultOut]
    themes_without_key_result: list[uuid.UUID]
    review: dict[str, Any]
    earlier_format: bool


class FocusEffectOut(BaseModel):
    """A no-write preview or explanation of a monthly focus change."""

    added: list[dict[str, Any]]
    removed: list[dict[str, Any]]
    targets_changed: list[dict[str, Any]]
    counts_from: date
    finished_earlier_in_month: int
    finished_earlier: list[dict[str, Any]]
    weekly_commitments_unchanged: int
    out_keeps_results: bool
    message: str


class FocusSavePreviewOut(BaseModel):
    """The effect of saving a focus without writing it."""

    effect: FocusEffectOut
    count_note: CountNote | None


class FocusSaveResultOut(BaseModel):
    """The saved month focus and its soft count guidance."""

    focus: MonthlyPlanOut
    count_note: CountNote | None


class FocusChangePreviewOut(BaseModel):
    """The effect of a proposed in-month change."""

    effect: FocusEffectOut


class FocusChangeResultOut(BaseModel):
    """The applied focus change and updated monthly plan."""

    batch_id: uuid.UUID
    effect: FocusEffectOut
    focus: MonthlyPlanOut


class FocusUndoOut(BaseModel):
    """The effect of undoing a focus change."""

    undone: FocusChangeKind
    focus: MonthlyPlanOut


class TrendOut(BaseModel):
    """Display-only comparison of this month's category counts."""

    state: TrendState
    previous: list[dict[str, Any]]
    share: float | None
    note: str | None = None


class ReviewMilestoneOut(BaseModel):
    """A completed milestone captured in a review snapshot."""

    milestone_id: uuid.UUID
    name: str
    done_on: date


class ReviewThemeOut(BaseModel):
    """A focus theme and its immutable monthly milestone results."""

    project_id: uuid.UUID
    name: str
    target: int | None
    counts_from: date
    left_on: date | None
    status: FocusEntryStatus
    orphaned: dict[str, Any] | None
    label_changed: ProjectLabel | None
    done: int
    marker: TargetMarker
    milestones: list[ReviewMilestoneOut]
    earlier_not_counted: list[ReviewMilestoneOut]
    key_result_ids: list[uuid.UUID]


class ReviewChangeOut(BaseModel):
    """A focus change recorded in a review snapshot."""

    kind: FocusChangeKind
    on: date
    out_project_id: uuid.UUID | None
    out_name: str | None
    in_project_id: uuid.UUID | None
    in_name: str | None
    target_before: int | None
    target_after: int | None
    undone: bool


class ReviewOutsideFocusOut(ReviewMilestoneOut):
    """A completed milestone not counted under a focused theme."""

    theme_project_id: uuid.UUID | None
    theme_name: str | None


class ReviewCategoriesOut(BaseModel):
    """Category counts supplied by the feature-005 month summary."""

    goal_aligned: int
    maintenance: int
    off_plan: int
    hidden: int


class ReviewKeyResultOut(BaseModel):
    """An annual key result's values and status captured at month end."""

    key_result_id: uuid.UUID
    goal_id: uuid.UUID
    goal_title: str
    metric: str
    update_source: UpdateSource
    start_value: float
    base_value: float
    latest_value: float
    latest_at: datetime | None
    change: float
    status: KeyResultUpdate
    entered_in_review: bool
    after_month_end: bool
    target: float
    deadline: date
    past_deadline: bool
    retired: bool
    theme_ids: list[uuid.UUID]
    shared: bool
    flags: list[MonthlyFlagCode]


class ReviewDecisionOut(BaseModel):
    """A saved month-end theme decision."""

    project_id: uuid.UUID
    name: str
    decision: ThemeDecision
    replacement_project_id: uuid.UUID | None
    replacement_name: str | None


class MonthlySnapshotOut(BaseModel):
    """Immutable version-one snapshot payload."""

    schema_version: int
    month: date
    month_end: date
    taken_at: datetime
    themes: list[ReviewThemeOut]
    changes: list[ReviewChangeOut]
    outside_focus: list[ReviewOutsideFocusOut]
    categories: ReviewCategoriesOut
    key_results: list[ReviewKeyResultOut]
    decisions: list[ReviewDecisionOut]


class ReviewVersionOut(BaseModel):
    """A stored review version and whether it is current."""

    version: int
    taken_at: datetime
    current: bool


class MonthlyReviewOut(BaseModel):
    """Stored snapshot or live draft with display-only trend information."""

    month: str
    stored: bool
    draft: bool
    version: int | None
    current_version: int | None
    taken_at: datetime | None
    versions: list[ReviewVersionOut]
    snapshot: MonthlySnapshotOut
    trend: TrendOut
    categories_note: str | None


class ReviewEffectOut(BaseModel):
    """A decision's user-facing effect line."""

    project_id: uuid.UUID
    decision: ThemeDecision
    message: str


class ReviewStorePreviewOut(BaseModel):
    """A review save preview with its effects and proposed version."""

    snapshot: MonthlySnapshotOut
    effects: list[ReviewEffectOut]
    will_create_version: int


class ReviewStoreResultOut(BaseModel):
    """A stored review snapshot and values written to key-result series."""

    version: int
    snapshot: MonthlySnapshotOut
    values_written: list[dict[str, str]]


class MakeCurrentPreviewOut(BaseModel):
    """A no-write explanation of selecting an earlier snapshot."""

    message: str


class ThemeOptionOut(BaseModel):
    """One eligible theme and its picker hints."""

    project_id: uuid.UUID
    connection_id: uuid.UUID
    connection_name: str
    name: str
    in_focus: bool
    left_this_month: bool
    last_month_done: int
    key_result_ids: list[uuid.UUID]


class TaskConnectionOptionOut(BaseModel):
    """A task-app connection available for creating a theme."""

    id: uuid.UUID
    name: str
    can_create: bool


class ThemePickerOut(BaseModel):
    """Eligible themes, unsorted-project count and theme-creation connections."""

    themes: list[ThemeOptionOut]
    unsorted_count: int
    task_connections: list[TaskConnectionOptionOut]


class ThemeSuggestionOut(BaseModel):
    """One carried or replacement theme suggestion."""

    project_id: uuid.UUID
    name: str
    target: int | None
    reason: ThemeSuggestionReason
    replaces: dict[str, Any] | None


class SkippedSuggestionOut(BaseModel):
    """A prior theme excluded from suggestions and its reason."""

    project_id: uuid.UUID
    name: str
    reason: SkippedSuggestionReason


class SuggestionsOut(BaseModel):
    """Saved-review suggestions and themes that could not be carried forward."""

    from_month: str | None
    suggestions: list[ThemeSuggestionOut]
    skipped: list[SkippedSuggestionOut]


class FocusHistoryEntryOut(BaseModel):
    """One focus-change history item."""

    batch_id: uuid.UUID
    kind: FocusChangeKind
    on: date
    out_name: str | None
    in_name: str | None
    target_before: int | None
    target_after: int | None
    source: FocusChangeSource
    undone: bool
    can_undo: bool


class FocusHistoryOut(BaseModel):
    """Chronological focus-change history."""

    month: str
    changes: list[FocusHistoryEntryOut]


def _trend_output(value: ReviewTrend) -> dict[str, Any]:
    state = TrendState(value.state)
    return {
        "state": state,
        "share": value.share,
        "previous": list(value.previous),
        "note": "not enough history" if state is TrendState.NOT_ENOUGH_HISTORY else None,
    }


async def _plan_payload(
    request: Request,
    db: Db,
    user: CurrentUser,
    month: date,
) -> dict[str, Any]:
    """Add snapshot and legacy status to the focus service's planning read model."""
    plan = await _focus(request).plan(db, user.id, month, tz=user.timezone)
    versions = await _review(request).versions(db, user.id, month)
    current = next((version.version for version in versions if version.current), None)
    legacy = await request.app.state.annual_service.legacy_goals(
        db, user.id, period_type="month", period_start=month
    )
    return {
        **plan.__dict__,
        "month": plan.month.strftime("%Y-%m"),
        "review": {
            "stored": current is not None,
            "current_version": current,
            "versions": len(versions),
        },
        "earlier_format": bool(legacy),
    }


@router.get("/snapshots")
async def get_snapshots(
    request: Request,
    db: Db,
    user: CurrentUser,
    year: int = Query(ge=1, le=9998),
) -> dict[str, Any]:
    """Expose current stored snapshots for feature 008."""
    return {
        "year": year,
        "snapshots": await _review(request).current_snapshots(db, user.id, year),
    }


@router.get("/{month}", response_model=MonthlyPlanOut)
async def get_month(
    month: str,
    request: Request,
    db: Db,
    user: CurrentUser,
) -> dict[str, Any]:
    """Return one month's focus, key results and snapshot status."""
    return await _plan_payload(request, db, user, _month(month))


@router.get("/{month}/themes", response_model=ThemePickerOut)
async def get_themes(
    month: str,
    request: Request,
    db: Db,
    user: CurrentUser,
    q: str | None = None,
    connection_id: uuid.UUID | None = None,
) -> object:
    """Return eligible themes and task connections for the picker."""
    return await _focus(request).themes(
        db, user.id, _month(month), q=q, connection_id=connection_id
    )


@router.get("/{month}/suggestions", response_model=SuggestionsOut)
async def get_suggestions(
    month: str,
    request: Request,
    db: Db,
    user: CurrentUser,
) -> object:
    """Suggest themes from the latest earlier stored review."""
    result = await _review(request).suggestions(db, user.id, _month(month))
    return {
        "from_month": result.from_month.strftime("%Y-%m") if result.from_month else None,
        "suggestions": result.suggestions,
        "skipped": result.skipped,
    }


@router.put(
    "/{month}/focus",
    response_model=FocusSavePreviewOut | FocusSaveResultOut,
)
async def save_focus(
    month: str,
    body: FocusSaveIn,
    request: Request,
    db: Db,
    user: CurrentUser,
) -> dict[str, Any]:
    """Save or preview the complete focus for one month."""
    start = _month(month)
    result = await _focus(request).save_plan(
        db,
        user.id,
        start,
        [FocusDraft(entry.project_id, entry.target) for entry in body.entries],
        dry_run=body.dry_run,
        tz=user.timezone,
    )
    if body.dry_run:
        return {"effect": result.effect, "count_note": result.count_note}
    if result.focus is None:
        raise RuntimeError("The monthly focus service returned no saved plan.")
    return {
        "focus": await _plan_payload(request, db, user, start),
        "count_note": result.count_note,
    }


@router.post(
    "/{month}/changes",
    response_model=FocusChangePreviewOut | FocusChangeResultOut,
)
async def change_focus(
    month: str,
    body: FocusChangeIn,
    request: Request,
    db: Db,
    user: CurrentUser,
) -> dict[str, Any]:
    """Preview or apply one in-month focus change."""
    start = _month(month)
    result = await _focus(request).change(
        db,
        user.id,
        start,
        kind=body.kind,
        out_project_id=body.out_project_id,
        in_project_id=body.in_project_id,
        target=body.target,
        dry_run=body.dry_run,
        tz=user.timezone,
    )
    if body.dry_run:
        return {"effect": result.effect}
    if result.focus is None:
        raise RuntimeError("The monthly focus service returned no saved plan.")
    return {
        "batch_id": result.batch_id,
        "effect": result.effect,
        "focus": await _plan_payload(request, db, user, start),
    }


@router.post("/{month}/changes/undo", response_model=FocusUndoOut)
async def undo_focus_change(
    month: str,
    body: UndoIn,
    request: Request,
    db: Db,
    user: CurrentUser,
) -> dict[str, Any]:
    """Undo one focus-change batch."""
    result = await _focus(request).undo(db, user.id, _month(month), body.batch_id, tz=user.timezone)
    return {
        "undone": result.undone,
        "focus": await _plan_payload(request, db, user, _month(month)),
    }


@router.get("/{month}/history", response_model=FocusHistoryOut)
async def get_focus_history(
    month: str,
    request: Request,
    db: Db,
    user: CurrentUser,
) -> object:
    """Return the chronological focus-change log."""
    history = await _focus(request).history(db, user.id, _month(month), tz=user.timezone)
    return {
        "month": history.month.strftime("%Y-%m"),
        "changes": history.changes,
    }


@router.get("/{month}/review", response_model=MonthlyReviewOut)
async def get_review(
    month: str,
    request: Request,
    db: Db,
    user: CurrentUser,
    version: int | None = Query(default=None, ge=1),
) -> dict[str, Any]:
    """Return the stored review or an unsaved live draft."""
    start = _month(month)
    service = _review(request)
    result = await service.review(db, user.id, start, version=version, tz=user.timezone)
    versions = await service.versions(db, user.id, start)
    if isinstance(result, ReviewRead):
        raw_categories = result.snapshot.get("categories")
        counts_raw = raw_categories if isinstance(raw_categories, dict) else {}
        counts = CategoryCounts(
            goal_aligned=int(counts_raw.get("goal_aligned", 0)),
            maintenance=int(counts_raw.get("maintenance", 0)),
            off_plan=int(counts_raw.get("off_plan", 0)),
            hidden=int(counts_raw.get("hidden", 0)),
        )
        earlier_counts = []
        previous = []
        reader = request.app.state.monthly_category_counts_reader
        for offset in (1, 2):
            year, month_number = start.year, start.month - offset
            while month_number <= 0:
                year -= 1
                month_number += 12
            previous_start = date(year, month_number, 1)
            earlier = await reader.month_counts(db, user.id, previous_start)
            if earlier is not None:
                earlier_counts.append(earlier)
            previous.append(
                {
                    "month": previous_start.strftime("%Y-%m"),
                    "share": off_plan_share(earlier) if earlier is not None else None,
                }
            )
        current_share = off_plan_share(counts)
        state = trend(counts, earlier_counts)
        trend_body = {
            "state": state,
            "share": current_share,
            "previous": previous,
            "note": ("not enough history" if state is TrendState.NOT_ENOUGH_HISTORY else None),
        }
        snapshot = result.snapshot
        stored = True
        draft = False
        selected_version = result.version
        current_version = result.current_version
        taken_at = result.taken_at
        categories_note = None if counts.total or counts.hidden else "no_data"
    else:
        versions = []
        snapshot = result.snapshot
        stored = False
        draft = True
        selected_version = None
        current_version = None
        taken_at = None
        trend_body = _trend_output(result.trend)
        categories_note = result.categories_note
    return {
        "month": start.strftime("%Y-%m"),
        "stored": stored,
        "draft": draft,
        "version": selected_version,
        "current_version": current_version,
        "taken_at": taken_at,
        "versions": versions,
        "snapshot": snapshot,
        "trend": trend_body,
        "categories_note": categories_note,
    }


@router.post(
    "/{month}/review",
    status_code=201,
    response_model=ReviewStorePreviewOut | ReviewStoreResultOut,
)
async def store_review(
    month: str,
    body: ReviewStoreIn,
    request: Request,
    response: Response,
    db: Db,
    user: CurrentUser,
) -> dict[str, Any]:
    """Preview or store a review and its immutable snapshot version."""
    start = _month(month)
    result = await _review(request).store(
        db,
        user.id,
        start,
        tz=user.timezone,
        key_result_values={row.key_result_id: row.value for row in body.key_result_values},
        decisions=[
            {
                "project_id": row.project_id,
                "decision": row.decision,
                "replacement_project_id": row.replacement_project_id,
            }
            for row in body.decisions
        ],
        confirm_new_version=body.confirm_new_version,
        dry_run=body.dry_run,
    )
    if body.dry_run:
        response.status_code = 200
        return {
            "snapshot": result.snapshot,
            "effects": result.effects,
            "will_create_version": result.will_create_version,
        }
    return {
        "version": result.version,
        "snapshot": result.snapshot,
        "values_written": result.values_written,
    }


@router.post(
    "/{month}/review/current",
    response_model=MakeCurrentPreviewOut | MonthlyReviewOut,
)
async def make_review_current(
    month: str,
    body: MakeCurrentIn,
    request: Request,
    db: Db,
    user: CurrentUser,
) -> dict[str, Any]:
    """Preview or select a stored snapshot version."""
    start = _month(month)
    service = _review(request)
    if body.dry_run:
        versions = await service.versions(db, user.id, start)
        if not any(item.version == body.version for item in versions):
            raise NoSuchVersion
        current_version = next((item.version for item in versions if item.current), body.version)
        return {
            "message": (
                f"Version {body.version} becomes the current version. "
                f"Version {current_version} "
                "stays in the history."
            )
        }
    await service.make_current(db, user.id, start, body.version)
    return await get_review(month, request, db, user, version=None)
