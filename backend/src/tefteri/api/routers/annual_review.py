"""Annual review routes (spec 008): the review and its notes."""

import uuid
from datetime import date
from typing import Any, cast

from fastapi import APIRouter, Request
from pydantic import BaseModel, Field

from tefteri.api.deps import CurrentUser, Db
from tefteri.api.schemas import UtcDatetime
from tefteri.domain.annual_plan import today_in
from tefteri.domain.enums import (
    DeadlineState,
    GoalState,
    KeyResultOutcome,
    MonthStatus,
    OrphanReason,
    ReviewEmptyReason,
    ThemeHint,
    YearState,
)
from tefteri.services.annual_review import AnnualReviewService
from tefteri.services.errors import Invalid
from tefteri.services.review_notes import ReviewNoteService

router = APIRouter(prefix="/annual-review", tags=["annual review"])


def _review(request: Request) -> AnnualReviewService:
    return cast(AnnualReviewService, request.app.state.annual_review_service)


def _notes(request: Request) -> ReviewNoteService:
    return cast(ReviewNoteService, request.app.state.review_note_service)


def _year(value: int) -> int:
    if not 2000 <= value <= 2100:
        raise Invalid("A review year is from 2000 to 2100.")
    return value


class RulesOut(BaseModel):
    """The one hit rule and the threshold of the hint rules."""

    hit: str
    differ_threshold: float


class MonthOut(BaseModel):
    """One month of the year and its snapshot status."""

    month: str
    status: MonthStatus
    version: int | None
    taken_at: UtcDatetime | None
    schema_version: int | None
    action: str | None


class CoverageOut(BaseModel):
    """The months that hold a snapshot and the months that are missing."""

    stored: int
    expected: int
    missing: list[str]


class EmptyOut(BaseModel):
    """Why the review has no data to show, and the action that helps."""

    reason: ReviewEmptyReason
    actions: list[str] = Field(default_factory=list)


class NoteOut(BaseModel):
    """The stored note of the year or of one goal."""

    id: uuid.UUID
    body: str
    updated_at: UtcDatetime


class ChangeOut(BaseModel):
    """One target, deadline or retirement change from the plan history."""

    kind: str
    field: str | None
    old_value: str | None
    new_value: str | None
    at: UtcDatetime


class FlagReasonOut(BaseModel):
    """Why a key result has no usable theme."""

    project_id: uuid.UUID | None
    name: str | None
    state: str


class KeyResultFlagOut(BaseModel):
    """A warning on a key result, with the actions that help."""

    code: str
    reasons: list[FlagReasonOut] = Field(default_factory=list)
    actions: list[str] = Field(default_factory=list)


class GoalFlagOut(BaseModel):
    """A warning on a goal."""

    code: str
    actions: list[str] = Field(default_factory=list)


class DeadlineLineOut(BaseModel):
    """Whether the key result was reached by its deadline."""

    state: DeadlineState
    value: float | None
    month: str | None


class SeriesPointOut(BaseModel):
    """One month of the twelve point series."""

    month: str
    status: MonthStatus
    value: float | None
    not_stored: bool


class PeakOut(BaseModel):
    """The best value of the series, shown when it differs from the last value."""

    value: float
    month: str


class MovedOut(BaseModel):
    """A live value entered after the last snapshot of a past year."""

    value: float
    at: UtcDatetime


class MovementOut(BaseModel):
    """The movement of a key result over one theme link."""

    from_value: float = Field(alias="from")
    to_value: float = Field(alias="to")
    fraction: float
    months: int

    model_config = {"populate_by_name": True}


class OrphanedOut(BaseModel):
    """Why a theme is no longer a live project."""

    reason: OrphanReason
    at: UtcDatetime | None


class RangeOut(BaseModel):
    """One active period of a theme link."""

    from_date: date = Field(alias="from")
    to_date: date | None = Field(alias="to")
    months: list[str]

    model_config = {"populate_by_name": True}


class ThemeMilestoneOut(BaseModel):
    """One milestone of a theme, with its stored completion date."""

    milestone_id: str | None
    name: str
    done_on: date
    month: str
    in_focus: bool


class ThemeOut(BaseModel):
    """One linked theme and what it did for the key result."""

    project_id: uuid.UUID | None
    connection_id: uuid.UUID | None
    connection_name: str | None
    name: str
    label: str | None
    orphaned: OrphanedOut | None
    ranges: list[RangeOut]
    shipped: int
    shipped_outside_focus: int
    target_sum: int | None
    months_with_target: int
    movement: MovementOut | None
    hint: ThemeHint | None
    milestones: list[ThemeMilestoneOut]


class KeyResultOut(BaseModel):
    """One key result of the review, its result and its themes."""

    id: uuid.UUID
    metric: str
    start_value: float
    target: float
    direction: str
    deadline: date
    update_source: str
    status: str
    retired_at: UtcDatetime | None
    outcome: KeyResultOutcome
    last_value: float | None
    last_month: str | None
    last_at: UtcDatetime | None
    deadline_line: DeadlineLineOut
    series: list[SeriesPointOut]
    peak: PeakOut | None
    moved_after_snapshot: MovedOut | None
    current_value: float
    changes: list[ChangeOut]
    flags: list[KeyResultFlagOut]
    themes: list[ThemeOut]


class GoalCountsOut(BaseModel):
    """The outcomes of the key results of one goal."""

    hit: int
    missed: int
    no_value: int
    retired: int
    in_progress: int


class GoalOut(BaseModel):
    """One goal of the year with its key results."""

    id: uuid.UUID
    title: str
    status: GoalState
    retired_at: UtcDatetime | None
    retired_reason: str | None
    counts: GoalCountsOut
    flags: list[GoalFlagOut]
    note: NoteOut | None
    key_results: list[KeyResultOut]


class CategoryCountsOut(BaseModel):
    """The three work categories."""

    goal_aligned: int
    maintenance: int
    off_plan: int


class SplitMonthOut(BaseModel):
    """One month row of the year split."""

    month: str
    status: MonthStatus
    counts: CategoryCountsOut | None
    hidden: int | None
    percentages: CategoryCountsOut | None
    not_stored: bool


class SplitOut(BaseModel):
    """The year split of work categories from stored counts."""

    months_covered: int
    counts: CategoryCountsOut
    total: int
    hidden: int
    percentages: CategoryCountsOut
    months: list[SplitMonthOut]
    trend_note: str | None


class DrillDownOut(BaseModel):
    """The live statistics call of feature 005."""

    live: bool
    route: str
    query: dict[str, str]


class NextYearOut(BaseModel):
    """What annual planning offers for the next year."""

    year: int
    from_year: int
    available: bool
    has_plan: bool
    unmet_key_results: int
    links: int


class MilestonesShippedOut(BaseModel):
    """The distinct milestones over the snapshots of the year."""

    count: int
    months_covered: int


class AnnualReviewOut(BaseModel):
    """The whole read-only review of one planning year."""

    year: int
    state: YearState
    in_progress: bool
    rules: RulesOut
    months: list[MonthOut]
    coverage: CoverageOut
    empty: EmptyOut | None
    goals: list[GoalOut]
    milestones_shipped: MilestonesShippedOut
    split: SplitOut
    drill_down: DrillDownOut
    next_year: NextYearOut
    year_note: NoteOut | None


class NotePutIn(BaseModel):
    """The text of a year or goal note."""

    goal_id: uuid.UUID | None = None
    body: str


class NoteWriteOut(BaseModel):
    """The stored note after a write."""

    id: uuid.UUID
    year: int
    goal_id: uuid.UUID | None
    body: str
    updated_at: UtcDatetime


class NoteDeletedOut(BaseModel):
    """The text that a delete removed, so the client can offer undo."""

    deleted: NoteWriteOut


@router.get("/{year}", response_model=AnnualReviewOut)
async def get_annual_review(
    request: Request,
    db: Db,
    user: CurrentUser,
    year: int,
) -> dict[str, Any]:
    """Return the review of one year. It opens in every state of the data."""
    return await _review(request).review(db, user.id, _year(year))


@router.put("/{year}/notes", response_model=NoteWriteOut)
async def put_annual_review_note(
    request: Request,
    db: Db,
    user: CurrentUser,
    year: int,
    body: NotePutIn,
) -> dict[str, Any]:
    """Create or replace the note of the year or of one goal."""
    year = _year(year)
    today = today_in(user.timezone, request.app.state.clock())
    note = await _notes(request).put(
        db,
        user.id,
        year,
        goal_id=body.goal_id,
        body=body.body,
        today=today,
    )
    return {
        "id": note.id,
        "year": note.year,
        "goal_id": note.goal_id,
        "body": note.body,
        "updated_at": note.updated_at,
    }


@router.delete("/{year}/notes", response_model=NoteDeletedOut)
async def delete_annual_review_note(
    request: Request,
    db: Db,
    user: CurrentUser,
    year: int,
    goal_id: uuid.UUID | None = None,
) -> dict[str, Any]:
    """Delete a note and return the text that was lost."""
    year = _year(year)
    note = await _notes(request).delete(db, user.id, year, goal_id=goal_id)
    return {
        "deleted": {
            "id": note.id,
            "year": note.year,
            "goal_id": note.goal_id,
            "body": note.body,
            "updated_at": note.updated_at,
        }
    }
