"""Review notes: create, replace and delete the only data an annual review writes (spec 008)."""

import uuid
from collections.abc import Callable
from datetime import UTC, date, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.goal import Goal
from tefteri.db.models.review_note import ReviewNote
from tefteri.domain.annual_plan import year_state
from tefteri.services.errors import Conflict, Invalid, NotFound

MAX_BODY = 2000


class ReviewNoteService:
    """One note per user, year and scope, with no soft delete (R-08)."""

    def __init__(self, clock: Callable[[], datetime] = lambda: datetime.now(UTC)) -> None:
        """Keep the injected clock."""
        self._clock = clock

    async def put(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        year: int,
        *,
        goal_id: uuid.UUID | None,
        body: str,
        today: date,
    ) -> ReviewNote:
        """Create or replace a note, or raise ``invalid``/``not_found``/``future_year``."""
        if not 2000 <= year <= 2100:
            raise Invalid("A review year is from 2000 to 2100.")
        if year_state(year, today) == "future":
            raise Conflict("future_year", "A future year has no review yet.")
        text = body.strip()
        if not text:
            raise Invalid("The note must not be empty.")
        if len(text) > MAX_BODY:
            raise Invalid("The note must be 2000 characters or fewer.")
        if goal_id is not None:
            goal = await db.get(Goal, goal_id)
            if (
                goal is None
                or goal.user_id != user_id
                or goal.period_type != "year"
                or goal.period_start.year != year
            ):
                raise NotFound
        existing = await self._find(db, user_id, year, goal_id)
        now = self._clock()
        if existing is None:
            note = ReviewNote(
                user_id=user_id,
                year=year,
                goal_id=goal_id,
                body=text,
                created_at=now,
                updated_at=now,
            )
            db.add(note)
        else:
            existing.body = text
            existing.updated_at = now
            note = existing
        await db.flush()
        return note

    async def delete(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        year: int,
        *,
        goal_id: uuid.UUID | None,
    ) -> ReviewNote:
        """Remove a note and return what was removed, so the client can undo (R-08)."""
        note = await self._find(db, user_id, year, goal_id)
        if note is None:
            raise NotFound
        await db.delete(note)
        await db.flush()
        return note

    async def for_year(
        self, db: AsyncSession, user_id: uuid.UUID, year: int
    ) -> dict[uuid.UUID | None, ReviewNote]:
        """Return the year note and every goal note of the year by goal id."""
        rows = list(
            (
                await db.execute(
                    select(ReviewNote).where(
                        ReviewNote.user_id == user_id, ReviewNote.year == year
                    )
                )
            ).scalars()
        )
        return {row.goal_id: row for row in rows}

    async def _find(
        self, db: AsyncSession, user_id: uuid.UUID, year: int, goal_id: uuid.UUID | None
    ) -> ReviewNote | None:
        query = select(ReviewNote).where(
            ReviewNote.user_id == user_id, ReviewNote.year == year
        )
        query = query.where(
            ReviewNote.goal_id.is_(None) if goal_id is None else ReviewNote.goal_id == goal_id
        )
        return (await db.execute(query)).scalar_one_or_none()
