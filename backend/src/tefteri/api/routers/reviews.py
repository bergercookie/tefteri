"""Plan reviews (planned versus completed), retrospectives and plan history."""

import uuid
from datetime import date, datetime
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Request
from pydantic import BaseModel

from tefteri.api.deps import CurrentUser, Db
from tefteri.api.schemas import NoteOut
from tefteri.db.models.goal import Plan
from tefteri.db.models.note import Note
from tefteri.db.models.review import PeriodReview
from tefteri.domain.periods import PeriodType, period_end
from tefteri.services.context import load_maps
from tefteri.services.goals import GoalService
from tefteri.services.reviews import ReviewService

router = APIRouter(tags=["reviews"])


def _reviews(request: Request) -> ReviewService:
    service: ReviewService = request.app.state.review_service
    return service


def _goals(request: Request) -> GoalService:
    service: GoalService = request.app.state.goal_service
    return service


class ReviewItemOut(BaseModel):
    """A planned goal or task and whether it was completed when the review was generated."""

    type: str
    id: uuid.UUID
    title: str
    completed: bool


class ReviewOut(BaseModel):
    """The review of one plan: a snapshot taken at ``generated_at``."""

    plan_id: uuid.UUID
    plan_title: str
    period_type: str
    period_start: date
    period_end: date
    period_ended: bool
    generated_at: datetime
    planned_count: int
    completed_count: int
    items: list[ReviewItemOut]
    carried_over: list[uuid.UUID]
    retrospective: NoteOut | None


class ReviewSummaryOut(BaseModel):
    """Counts of a stored review, for the plan history."""

    generated_at: datetime
    planned_count: int
    completed_count: int
    has_retrospective: bool


class PlanHistoryOut(BaseModel):
    """A plan in the history, with its review when one was generated."""

    plan_id: uuid.UUID
    title: str
    period_type: str
    period_start: date
    period_end: date
    period_ended: bool
    review: ReviewSummaryOut | None


class RetrospectiveIn(BaseModel):
    """The retrospective text."""

    body: str


def _ended(plan: Plan, tz: str) -> tuple[date, bool]:
    end = period_end(PeriodType(plan.period_type), plan.period_start)
    return end, end <= datetime.now(ZoneInfo(tz)).date()


async def _out(
    db: Db, user_id: uuid.UUID, tz: str, plan: Plan, review: PeriodReview, note: Note | None
) -> ReviewOut:
    end, ended = _ended(plan, tz)
    return ReviewOut(
        plan_id=plan.id,
        plan_title=plan.title,
        period_type=plan.period_type,
        period_start=plan.period_start,
        period_end=end,
        period_ended=ended,
        generated_at=review.generated_at,
        planned_count=review.planned_count,
        completed_count=review.completed_count,
        items=[ReviewItemOut.model_validate(i) for i in review.items],
        carried_over=[uuid.UUID(i) for i in review.carried_over],
        retrospective=NoteOut.of(note, await load_maps(db, user_id)) if note else None,
    )


@router.get("/plans/{plan_id}/review")
async def get_review(
    plan_id: uuid.UUID, request: Request, db: Db, user: CurrentUser, refresh: bool = False
) -> ReviewOut:
    """Return the plan's review; generate it the first time or when ``refresh`` is true."""
    plan = await _goals(request).plan(db, user.id, plan_id)
    service = _reviews(request)
    review = await service.review(db, user.id, plan, user.timezone, refresh=refresh)
    note = await service.retrospective(db, user.id, review)
    return await _out(db, user.id, user.timezone, plan, review, note)


@router.put("/plans/{plan_id}/review/retrospective")
async def save_retrospective(
    plan_id: uuid.UUID, body: RetrospectiveIn, request: Request, db: Db, user: CurrentUser
) -> ReviewOut:
    """Save the retrospective as a note in the note app and link it to the plan's review."""
    plan = await _goals(request).plan(db, user.id, plan_id)
    review, note = await _reviews(request).save_retrospective(
        db, user.id, plan, user.timezone, body.body
    )
    return await _out(db, user.id, user.timezone, plan, review, note)


@router.get("/reviews/history")
async def plan_history(request: Request, db: Db, user: CurrentUser) -> list[PlanHistoryOut]:
    """List all plans, newest period first, each with its review summary when there is one."""
    plans = await _goals(request).plans(db, user.id)
    result = []
    for plan, review in await _reviews(request).history(db, user.id, plans):
        end, ended = _ended(plan, user.timezone)
        result.append(
            PlanHistoryOut(
                plan_id=plan.id,
                title=plan.title,
                period_type=plan.period_type,
                period_start=plan.period_start,
                period_end=end,
                period_ended=ended,
                review=ReviewSummaryOut(
                    generated_at=review.generated_at,
                    planned_count=review.planned_count,
                    completed_count=review.completed_count,
                    has_retrospective=review.retrospective_note_id is not None,
                )
                if review
                else None,
            )
        )
    return result
