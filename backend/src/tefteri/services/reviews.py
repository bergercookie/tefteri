"""Period reviews: planned versus completed, carried-over items and retrospectives."""

import uuid
from dataclasses import asdict, dataclass
from datetime import date

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.base import utcnow
from tefteri.db.models.goal import Goal, Plan
from tefteri.db.models.note import Note
from tefteri.db.models.review import PeriodReview
from tefteri.db.models.task import Task
from tefteri.db.repositories.items import NoteRepository
from tefteri.domain.periods import PeriodType
from tefteri.services.goals import compute_progress
from tefteri.services.notes import NoteService


@dataclass(frozen=True)
class ReviewItem:
    """One planned goal or task and whether it was completed."""

    type: str  # 'goal' | 'task'
    id: str
    title: str
    completed: bool


@dataclass(frozen=True)
class ReviewSummary:
    """Planned versus completed for one period."""

    planned_count: int
    completed_count: int
    items: list[ReviewItem]
    carried_over: list[str]


def compute_review(
    period_type: PeriodType, start: date, goals: list[Goal], tasks: list[Task], tz: str
) -> ReviewSummary:
    """Return what was planned for a period and what of it was completed.

    Planned goals are the period's own goals, except dropped ones. A goal counts as completed
    when its status is ``done`` or its computed progress is 1. Single tasks are not part of a
    review: they only feed the progress of their goals. Carried over are the goals that were not
    completed. ``tz`` stays for callers; it no longer changes the result.
    """
    progress = compute_progress(goals, tasks)
    own = [
        g
        for g in goals
        if g.period_type == period_type.value and g.period_start == start and g.status != "dropped"
    ]
    items = [
        ReviewItem("goal", str(g.id), g.title, g.status == "done" or progress[g.id] >= 1.0)
        for g in sorted(own, key=lambda g: g.title)
    ]
    return ReviewSummary(
        planned_count=len(items),
        completed_count=sum(1 for i in items if i.completed),
        items=items,
        carried_over=[i.id for i in items if not i.completed],
    )


class ReviewService:
    """Generate, keep and refresh plan reviews; save retrospectives to the note app."""

    def __init__(self, notes: NoteService) -> None:
        """Use ``notes`` to write retrospectives to the note app."""
        self._notes = notes

    async def find(self, db: AsyncSession, user_id: uuid.UUID, plan: Plan) -> PeriodReview | None:
        """Return the stored review of ``plan``, if any."""
        return (
            await db.execute(
                select(PeriodReview).where(
                    PeriodReview.plan_id == plan.id, PeriodReview.user_id == user_id
                )
            )
        ).scalar_one_or_none()

    async def review(
        self, db: AsyncSession, user_id: uuid.UUID, plan: Plan, tz: str, *, refresh: bool = False
    ) -> PeriodReview:
        """Return the review of ``plan``; compute and store it when missing or on ``refresh``."""
        review = await self.find(db, user_id, plan)
        if review is not None and not refresh:
            return review
        goals = list((await db.execute(select(Goal).where(Goal.user_id == user_id))).scalars())
        tasks = list((await db.execute(select(Task).where(Task.user_id == user_id))).scalars())
        summary = compute_review(PeriodType(plan.period_type), plan.period_start, goals, tasks, tz)
        if review is None:
            review = PeriodReview(user_id=user_id, plan_id=plan.id)
            db.add(review)
        review.generated_at = utcnow()
        review.planned_count = summary.planned_count
        review.completed_count = summary.completed_count
        review.items = [asdict(i) for i in summary.items]
        review.carried_over = summary.carried_over
        await db.flush()
        return review

    async def retrospective(
        self, db: AsyncSession, user_id: uuid.UUID, review: PeriodReview
    ) -> Note | None:
        """Return the cached retrospective note of a review, if any."""
        if review.retrospective_note_id is None:
            return None
        return await NoteRepository(db, user_id).get(review.retrospective_note_id)

    async def save_retrospective(
        self, db: AsyncSession, user_id: uuid.UUID, plan: Plan, tz: str, body: str
    ) -> tuple[PeriodReview, Note]:
        """Write the retrospective to the note app (create or update) and link it to the review.

        Nothing is stored when the note app fails.
        """
        review = await self.review(db, user_id, plan, tz)
        note = await self.retrospective(db, user_id, review)
        if note is None:
            note = await self._notes.create(
                db,
                user_id,
                title=f"Retrospective: {plan.title}",
                body=body,
                kind="retrospective",
            )
            review.retrospective_note_id = note.id
        else:
            note = await self._notes.update(db, user_id, note, body=body)
        await db.flush()
        return review, note

    async def history(
        self, db: AsyncSession, user_id: uuid.UUID, plans: list[Plan]
    ) -> list[tuple[Plan, PeriodReview | None]]:
        """Pair each plan with its stored review (or ``None``), keeping the order of ``plans``."""
        reviews: dict[uuid.UUID, PeriodReview] = {
            r.plan_id: r
            for r in (
                await db.execute(select(PeriodReview).where(PeriodReview.user_id == user_id))
            ).scalars()
        }
        return [(p, reviews.get(p.id)) for p in plans]
