"""Planning checklists: the list for a week, month or year and what is ticked in it."""

from datetime import date

from fastapi import APIRouter, Request
from pydantic import BaseModel, ConfigDict, Field

from tefteri.api.deps import CurrentUser, Db
from tefteri.domain.periods import PeriodType
from tefteri.services.checklists import MAX_ITEM_LENGTH, Checklist, ChecklistService

router = APIRouter(prefix="/checklists", tags=["checklists"])


def _service(request: Request) -> ChecklistService:
    service: ChecklistService = request.app.state.checklist_service
    return service


class ChecklistPartOut(BaseModel):
    """A run of words in an item; ``url`` is set when the run is a link."""

    text: str
    url: str | None = None


class ChecklistItemOut(BaseModel):
    """One item and whether it is ticked in this period."""

    text: str
    checked: bool
    parts: list[ChecklistPartOut] = Field(default_factory=list)
    """The runs that build the text, with links. Empty for a local item."""


class ChecklistOut(BaseModel):
    """The checklist of one period."""

    period_type: PeriodType
    period_start: date
    items: list[ChecklistItemOut]
    """The user's list for this kind of planning. Empty when they have not defined one."""
    done: int
    total: int
    source: str | None = None
    """The note path that the list comes from; ``None`` for the user's local list."""
    source_url: str | None = None
    """The address of that note in the notes app, to open it."""

    @classmethod
    def of(cls, c: Checklist) -> "ChecklistOut":
        """Build from the checklist."""
        return cls(
            period_type=c.kind,
            period_start=c.start,
            items=[
                ChecklistItemOut(
                    text=i.text,
                    checked=i.checked,
                    parts=[ChecklistPartOut(text=part.text, url=part.url) for part in i.parts],
                )
                for i in c.items
            ],
            done=c.done,
            total=len(c.items),
            source=c.source,
            source_url=c.source_url,
        )


class TickIn(BaseModel):
    """Tick or untick one item."""

    model_config = ConfigDict(extra="forbid")

    text: str = Field(min_length=1, max_length=MAX_ITEM_LENGTH)
    checked: bool


@router.get("/{kind}/{day}")
async def get_checklist(
    kind: PeriodType, day: date, request: Request, db: Db, user: CurrentUser
) -> ChecklistOut:
    """Return the checklist of the week, month or year that holds ``day``.

    The ticks belong to that period: the next period starts with a clean list. When the
    checklist comes from the notes app, it is read from the note on every call.
    """
    return ChecklistOut.of(await _service(request).get(db, user.id, kind, day))


@router.put("/{kind}/{day}/items")
async def tick_item(
    kind: PeriodType, day: date, body: TickIn, request: Request, db: Db, user: CurrentUser
) -> ChecklistOut:
    """Tick or untick one item of the checklist of that period."""
    return ChecklistOut.of(
        await _service(request).tick(db, user.id, kind, day, body.text, body.checked)
    )
