"""Planning checklists: a list of items for each period type, ticked once per period."""

import uuid
from dataclasses import dataclass
from datetime import date

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.checklist import ChecklistProgress
from tefteri.db.models.user import User
from tefteri.domain.periods import PeriodType, period_start
from tefteri.services.errors import Invalid, NotFound

MAX_ITEMS = 50
"""A checklist holds at most this many items."""
MAX_ITEM_LENGTH = 200
"""An item is at most this many characters long."""

KINDS = (PeriodType.WEEK, PeriodType.MONTH, PeriodType.YEAR)


def clean_items(items: list[str]) -> list[str]:
    """Trim the items, drop the empty ones and the repeats (case does not count).

    Items are told apart by their text, so a repeat could not be ticked on its own.
    """
    seen: dict[str, str] = {}
    for item in items:
        text = " ".join(item.split())
        if text:
            seen.setdefault(text.casefold(), text)
    return list(seen.values())


@dataclass(frozen=True)
class Item:
    """One item of a checklist and whether it is ticked in the period."""

    text: str
    checked: bool


@dataclass(frozen=True)
class Checklist:
    """The checklist of one period."""

    kind: PeriodType
    start: date
    items: list[Item]

    @property
    def done(self) -> int:
        """How many items are ticked."""
        return sum(1 for i in self.items if i.checked)


class ChecklistService:
    """Read the checklist of a period and tick its items."""

    async def _user(self, db: AsyncSession, user_id: uuid.UUID) -> User:
        user = await db.get(User, user_id)
        if user is None:
            raise NotFound
        return user

    async def _row(
        self, db: AsyncSession, user_id: uuid.UUID, kind: PeriodType, start: date
    ) -> ChecklistProgress | None:
        return (
            await db.execute(
                select(ChecklistProgress).where(
                    ChecklistProgress.user_id == user_id,
                    ChecklistProgress.period_type == kind.value,
                    ChecklistProgress.period_start == start,
                )
            )
        ).scalar_one_or_none()

    async def get(
        self, db: AsyncSession, user_id: uuid.UUID, kind: PeriodType, day: date
    ) -> Checklist:
        """Return the checklist of the period of type ``kind`` that holds ``day``.

        The items are the user's current list. A tick for an item that is no longer in the list
        is ignored.
        """
        user = await self._user(db, user_id)
        start = period_start(kind, day)
        row = await self._row(db, user_id, kind, start)
        ticked = set(row.checked) if row else set()
        items = clean_items(list(user.checklists.get(kind.value, [])))
        return Checklist(kind, start, [Item(t, t in ticked) for t in items])

    async def tick(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        kind: PeriodType,
        day: date,
        text: str,
        checked: bool,
    ) -> Checklist:
        """Tick or untick one item in the period and return the checklist."""
        current = await self.get(db, user_id, kind, day)
        if text not in {i.text for i in current.items}:
            raise Invalid("That item is not in the checklist. Reload the page.")
        row = await self._row(db, user_id, kind, current.start)
        if row is None:
            row = ChecklistProgress(
                user_id=user_id, period_type=kind.value, period_start=current.start, checked=[]
            )
            db.add(row)
        # Keep only the ticks of items that are still in the list.
        keep = {i.text for i in current.items if i.checked and i.text != text}
        if checked:
            keep.add(text)
        row.checked = sorted(keep)
        await db.flush()
        return await self.get(db, user_id, kind, day)
