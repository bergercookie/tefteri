"""Milestone projects: done-state, done by hand, close and return tasks, reopen (spec 004)."""

import uuid
from datetime import date, datetime

from fastapi import APIRouter, Request
from pydantic import BaseModel, Field

from tefteri.api.deps import CurrentUser, Db
from tefteri.services.errors import Invalid
from tefteri.services.milestone_close import MilestoneCloseService
from tefteri.services.milestones import MilestoneService, MilestoneView

router = APIRouter(prefix="/milestones", tags=["milestones"])


def _milestones(request: Request) -> MilestoneService:
    service: MilestoneService = request.app.state.milestone_service
    return service


def _closer(request: Request) -> MilestoneCloseService:
    service: MilestoneCloseService = request.app.state.milestone_close_service
    return service


def _now(request: Request) -> datetime:
    now: datetime = request.app.state.clock()
    return now


class ThemeOut(BaseModel):
    """The parent theme of a milestone."""

    id: uuid.UUID
    """The id of its label row, which is its id in the project API."""
    name: str


class RolloverOut(BaseModel):
    """One recommit of a milestone."""

    from_week: date
    to_week: date
    expected: bool
    """The marker of this one event."""


class CanCloseOut(BaseModel):
    """Whether the open tasks can go back to the theme."""

    available: bool
    reason: str | None
    """``no_theme``, ``theme_unusable``, ``not_supported`` or ``None``."""


class ClosureOut(BaseModel):
    """The newest close of a milestone."""

    id: uuid.UUID
    status: str
    """``moving``, ``closed`` or ``reopened``."""
    moved: int


class MilestoneOut(BaseModel):
    """A milestone project."""

    id: uuid.UUID
    project_id: uuid.UUID
    name: str
    done_state: str | None
    state: str
    """``active``, ``parked``, ``closed`` or ``done``."""
    theme: ThemeOut | None
    rollover_count: int
    needs_rescope: bool
    done_on: date | None
    done_theme_name: str | None
    """The theme when the milestone became done. A later change of theme never alters it."""
    done_by: str | None
    """``auto`` or ``user``."""
    orphaned: str | None
    """The reason the project left the task app (``missing`` or ``archived``), or ``None``."""
    rollovers: list[RolloverOut]
    open_tasks: int
    can_close: CanCloseOut
    last_closure: ClosureOut | None

    @classmethod
    def of(cls, v: MilestoneView) -> "MilestoneOut":
        """Build from the service view."""
        m = v.milestone
        return cls(
            id=m.id,
            project_id=m.project_id,
            name=v.project.name,
            done_state=m.done_state,
            state=m.state,
            theme=ThemeOut(id=v.theme.id, name=v.theme.name) if v.theme else None,
            rollover_count=m.rollover_count,
            needs_rescope=v.needs_rescope,
            done_on=m.done_on,
            done_theme_name=m.done_theme_name,
            done_by=m.done_by,
            orphaned=v.orphaned,
            rollovers=[
                RolloverOut(from_week=r.from_week, to_week=r.to_week, expected=r.expected)
                for r in v.rollovers
            ],
            open_tasks=v.open_tasks,
            can_close=CanCloseOut(available=v.can_close.available, reason=v.can_close.reason),
            last_closure=(
                ClosureOut(
                    id=v.last_closure.id,
                    status=v.last_closure.status,
                    moved=len(v.last_closure.moved),
                )
                if v.last_closure
                else None
            ),
        )


class DoneStateIn(BaseModel):
    """The new done-state."""

    done_state: str = Field(default="", max_length=2000)


class DoneIn(BaseModel):
    """Mark a milestone done by hand."""

    dry_run: bool = False
    """Write nothing and say what it would do."""


class DoneOut(BaseModel):
    """The effect of marking a milestone done by hand."""

    open_tasks: int
    message: str
    milestone: MilestoneOut | None = None
    """Absent for a ``dry_run``."""


class CloseIn(BaseModel):
    """Close a milestone and return its open tasks to the parent theme."""

    dry_run: bool = False
    """Write and move nothing. Say how many tasks would move and where."""
    confirm: bool = False
    """The user confirmed the number of tasks and the theme."""


class ClosePreviewOut(BaseModel):
    """What a close would do (``dry_run``)."""

    open_tasks: int
    theme: ThemeOut
    message: str


class CloseDoneOut(BaseModel):
    """The result of a close that worked."""

    milestone: MilestoneOut
    moved: int
    closure_id: uuid.UUID


class NotMovedBackOut(BaseModel):
    """A task that could not be moved back by a reopen."""

    task_id: uuid.UUID
    title: str
    reason: str
    """``changed`` (edited since), ``moved`` (moved again), ``missing`` (gone) or ``failed``."""


class ReopenOut(BaseModel):
    """The result of a reopen. A task that did not move back never fails it."""

    milestone: MilestoneOut
    moved_back: int
    not_moved_back: list[NotMovedBackOut]


async def _out(
    request: Request, db: Db, user_id: uuid.UUID, milestone_id: uuid.UUID
) -> MilestoneOut:
    service = _milestones(request)
    milestone = await service.get(db, user_id, milestone_id)
    return MilestoneOut.of(await service.view(db, user_id, milestone))


@router.get("/{milestone_id}")
async def get_milestone(
    milestone_id: uuid.UUID, request: Request, db: Db, user: CurrentUser
) -> MilestoneOut:
    """Return one milestone with its theme, rollovers and close options. 404 if not the user's."""
    return await _out(request, db, user.id, milestone_id)


@router.patch("/{milestone_id}")
async def set_done_state(
    milestone_id: uuid.UUID, body: DoneStateIn, request: Request, db: Db, user: CurrentUser
) -> MilestoneOut:
    """Set or change the done-state (422 ``done_state_required`` when blank)."""
    await _milestones(request).set_done_state(db, user.id, milestone_id, body.done_state)
    return await _out(request, db, user.id, milestone_id)


@router.post("/{milestone_id}/done")
async def mark_done(
    milestone_id: uuid.UUID, body: DoneIn, request: Request, db: Db, user: CurrentUser
) -> DoneOut:
    """Mark a milestone done by hand. Open tasks stay where they are.

    The done day is today of the user. 422 ``not_unfinished`` if it is done or closed already.
    """
    service = _milestones(request)
    milestone = await service.get(db, user.id, milestone_id)
    effect = await service.mark_done(
        db, user.id, user.timezone, milestone, _now(request), dry_run=body.dry_run
    )
    return DoneOut(
        open_tasks=effect.open_tasks,
        message=effect.message,
        milestone=None if body.dry_run else await _out(request, db, user.id, milestone_id),
    )


@router.post("/{milestone_id}/close")
async def close_milestone(
    milestone_id: uuid.UUID, body: CloseIn, request: Request, db: Db, user: CurrentUser
) -> ClosePreviewOut | CloseDoneOut:
    """Close a milestone and move its open tasks to the parent theme.

    ``dry_run`` says how many tasks would move. ``confirm`` moves them one by one and closes the
    milestone after the last one. Neither is 422 ``confirm_required``. A failure part way is a
    502 that lists the tasks already moved (``moved``) and ``remaining``. Calling again finishes.
    """
    closer = _closer(request)
    if body.dry_run:
        preview = await closer.preview(db, user.id, milestone_id)
        return ClosePreviewOut(
            open_tasks=preview.open_tasks,
            theme=ThemeOut(id=preview.theme.id, name=preview.theme.name),
            message=preview.message,
        )
    if not body.confirm:
        raise Invalid(
            "Confirm the close: it moves the open tasks to the theme.", code="confirm_required"
        )
    done = await closer.close(db, user.id, milestone_id, _now(request))
    return CloseDoneOut(
        milestone=await _out(request, db, user.id, milestone_id),
        moved=done.moved,
        closure_id=done.closure.id,
    )


@router.post("/{milestone_id}/reopen")
async def reopen_milestone(
    milestone_id: uuid.UUID, request: Request, db: Db, user: CurrentUser
) -> ReopenOut:
    """Make a closed or done milestone active again.

    A closed milestone gets back the tasks of its newest close that were not changed since. The
    others are listed, and the reopen still works.
    """
    result = await _closer(request).reopen(db, user.id, milestone_id, _now(request))
    return ReopenOut(
        milestone=await _out(request, db, user.id, milestone_id),
        moved_back=result.moved_back,
        not_moved_back=[
            NotMovedBackOut(task_id=n.task_id, title=n.title, reason=n.reason)
            for n in result.not_moved_back
        ],
    )
