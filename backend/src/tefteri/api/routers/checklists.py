"""Planning checklists: the list for a week, month or year and what is ticked in it."""

from datetime import date

from fastapi import APIRouter
from pydantic import BaseModel, ConfigDict, Field

from tefteri.api.deps import CurrentUser, Db
from tefteri.domain.periods import PeriodType
from tefteri.services.checklists import MAX_ITEM_LENGTH, Checklist, ChecklistService

router = APIRouter(prefix="/checklists", tags=["checklists"])
_service = ChecklistService()


class ChecklistItemOut(BaseModel):
    """One item and whether it is ticked in this period."""

    text: str
    checked: bool


class ChecklistOut(BaseModel):
    """The checklist of one period."""

    period_type: PeriodType
    period_start: date
    items: list[ChecklistItemOut]
    """The user's list for this kind of planning. Empty when they have not defined one."""
    done: int
    total: int

    @classmethod
    def of(cls, c: Checklist) -> "ChecklistOut":
        """Build from the checklist."""
        return cls(
            period_type=c.kind,
            period_start=c.start,
            items=[ChecklistItemOut(text=i.text, checked=i.checked) for i in c.items],
            done=c.done,
            total=len(c.items),
        )


class TickIn(BaseModel):
    """Tick or untick one item."""

    model_config = ConfigDict(extra="forbid")

    text: str = Field(min_length=1, max_length=MAX_ITEM_LENGTH)
    checked: bool


@router.get("/{kind}/{day}")
async def get_checklist(kind: PeriodType, day: date, db: Db, user: CurrentUser) -> ChecklistOut:
    """Return the checklist of the week, month or year that holds ``day``.

    The ticks belong to that period: the next period starts with a clean list.
    """
    return ChecklistOut.of(await _service.get(db, user.id, kind, day))


@router.put("/{kind}/{day}/items")
async def tick_item(
    kind: PeriodType, day: date, body: TickIn, db: Db, user: CurrentUser
) -> ChecklistOut:
    """Tick or untick one item of the checklist of that period."""
    return ChecklistOut.of(await _service.tick(db, user.id, kind, day, body.text, body.checked))
