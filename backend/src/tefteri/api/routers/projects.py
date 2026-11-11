"""Project classification (spec 003): labels, undo, rename, create, archive and restore."""

import uuid
from typing import Literal

from fastapi import APIRouter, Request
from pydantic import BaseModel, ConfigDict, Field

from tefteri.api.deps import CurrentUser, Db
from tefteri.api.schemas import UtcDatetime
from tefteri.domain.enums import ProjectLabel
from tefteri.services.classification import (
    Change,
    ClassificationService,
    ConnectionView,
    Effect,
    ProjectView,
)

router = APIRouter(prefix="/projects", tags=["projects"])


def _service(request: Request) -> ClassificationService:
    service: ClassificationService = request.app.state.classification_service
    return service


class ProposalOut(BaseModel):
    """The label that tefteri suggests, and why."""

    label: ProjectLabel
    reason: Literal["top_level", "nested", "was_committed", "inside_routine"]


class OrphanedOut(BaseModel):
    """A project that is no longer in the task app."""

    reason: Literal["missing", "archived"]
    at: UtcDatetime | None


class ProjectOut(BaseModel):
    """A project with its label, its proposal and the facts that the screen needs."""

    id: uuid.UUID
    connection_id: uuid.UUID
    name: str
    parent_id: uuid.UUID | None
    label: ProjectLabel | None
    """``None`` is unclassified: the proposal is only a suggestion then."""
    proposal: ProposalOut
    effective_label: ProjectLabel
    parent_theme_id: uuid.UUID | None
    """The nearest ancestor that is a theme; ``None`` is "no theme"."""
    unsorted: bool
    orphaned: OrphanedOut | None
    eligible: bool
    """A planning picker may list the project."""
    open_tasks: int
    subprojects: int
    in_committed_plan: bool

    @classmethod
    def of(cls, p: ProjectView) -> "ProjectOut":
        """Build from the service view."""
        row = p.row
        return cls(
            id=row.id,
            connection_id=row.connection_id,
            name=row.name,
            parent_id=p.parent_id,
            label=ProjectLabel(row.label) if row.label else None,
            proposal=ProposalOut(label=p.proposal.label, reason=p.proposal.reason),
            effective_label=p.effective_label,
            parent_theme_id=p.parent_theme_id,
            unsorted=p.unsorted,
            orphaned=(
                OrphanedOut(reason=row.orphaned_reason, at=row.orphaned_at)
                if row.orphaned_reason
                else None
            ),
            eligible=p.eligible,
            open_tasks=p.open_tasks,
            subprojects=p.subprojects,
            in_committed_plan=p.in_committed_plan,
        )


class ConnectionCapabilitiesOut(BaseModel):
    """The optional features of the task app."""

    rename: bool
    restore: bool
    move_tasks: bool


class ClassifiedConnectionOut(BaseModel):
    """The projects of one task connection, in tree order."""

    connection_id: uuid.UUID
    name: str
    status: str
    """``ok``, ``needs_attention`` or ``error``: the health of the connection at the last sync."""
    last_sync_outcome: str | None
    """Why the last sync failed (for example ``auth_expired``), or ``ok``."""
    capabilities: ConnectionCapabilitiesOut
    projects: list[ProjectOut]

    @classmethod
    def of(cls, v: ConnectionView) -> "ClassifiedConnectionOut":
        """Build from the service view."""
        return cls(
            connection_id=v.connection.id,
            name=v.connection.display_name,
            status=v.connection.status,
            last_sync_outcome=v.connection.last_sync_outcome,
            capabilities=ConnectionCapabilitiesOut(
                rename=v.rename, restore=v.restore, move_tasks=v.move_tasks
            ),
            projects=[ProjectOut.of(p) for p in v.projects],
        )


class ClassificationOut(BaseModel):
    """All projects with their labels."""

    connections: list[ClassifiedConnectionOut]
    unsorted_count: int


@router.get("/classification")
async def classification(
    request: Request, db: Db, user: CurrentUser, connection_id: uuid.UUID | None = None
) -> ClassificationOut:
    """Return the project tree of the user's task connections with labels and proposals.

    Without ``connection_id`` every task connection is included. Orphaned projects are in the
    list, with their stored name and the reason.
    """
    result = await _service(request).tree(db, user.id, connection_id)
    return ClassificationOut(
        connections=[ClassifiedConnectionOut.of(v) for v in result.connections],
        unsorted_count=result.unsorted_count,
    )


class ChangeIn(BaseModel):
    """One label change. ``label=null`` puts the project back to unclassified."""

    id: uuid.UUID
    label: ProjectLabel | None


class LabelsIn(BaseModel):
    """A bulk label change."""

    changes: list[ChangeIn] = Field(max_length=1000)
    dry_run: bool = False
    """Write nothing and only return the effect."""
    source: Literal["user", "suggestion"] = "user"
    """``suggestion`` when the user accepted the proposals."""


class ByChangeOut(BaseModel):
    """How many projects go from one label to another."""

    model_config = ConfigDict(populate_by_name=True)

    from_: str = Field(alias="from")
    to: str
    count: int


class EffectOut(BaseModel):
    """What a bulk change does (FR-023)."""

    changed: int
    by_change: list[ByChangeOut]
    in_committed_plan: int

    @classmethod
    def of(cls, e: Effect) -> "EffectOut":
        """Build from the service result."""
        return cls(
            changed=e.changed,
            by_change=[ByChangeOut(from_=a, to=b, count=n) for a, b, n in e.by_change],
            in_committed_plan=e.in_committed_plan,
        )


class LabelsOut(BaseModel):
    """The effect of a bulk change and, when it was written, its batch id for undo."""

    batch_id: uuid.UUID | None
    effect: EffectOut


@router.put("/labels")
async def set_labels(body: LabelsIn, request: Request, db: Db, user: CurrentUser) -> LabelsOut:
    """Set the labels of several projects at once, or preview that (``dry_run``).

    A real save adds one history entry for each project that changes, all with one
    ``batch_id``. 404 when a project is not the user's.
    """
    saved = await _service(request).save(
        db,
        user.id,
        [Change(c.id, c.label) for c in body.changes],
        dry_run=body.dry_run,
        source=body.source,
    )
    return LabelsOut(batch_id=saved.batch_id, effect=EffectOut.of(saved.effect))


class UndoIn(BaseModel):
    """The save to undo."""

    batch_id: uuid.UUID


class UndoOut(BaseModel):
    """How many projects got their earlier label back."""

    restored: int


@router.post("/labels/undo")
async def undo_labels(body: UndoIn, request: Request, db: Db, user: CurrentUser) -> UndoOut:
    """Undo a save: add history entries that restore the earlier labels.

    404 when the batch is not the user's, 409 (``already_undone``) when it was undone before.
    """
    restored = await _service(request).undo(db, user.id, body.batch_id)
    return UndoOut(restored=restored)


class RenameIn(BaseModel):
    """The new name of a project."""

    name: str = Field(min_length=1, max_length=255)


@router.patch("/{project_id}")
async def rename_project(
    project_id: uuid.UUID, body: RenameIn, request: Request, db: Db, user: CurrentUser
) -> ProjectOut:
    """Rename a project in the task app first, then here.

    409 ``not_supported`` when the task app cannot rename; 502 when the task app fails (nothing
    changes); 404 for an orphaned project.
    """
    return ProjectOut.of(await _service(request).rename(db, user.id, project_id, body.name))


class ProjectIn(BaseModel):
    """A project to create in the task app and label."""

    connection_id: uuid.UUID
    name: str = Field(min_length=1, max_length=255)
    parent_id: uuid.UUID | None = None
    label: ProjectLabel


@router.post("", status_code=201)
async def create_project(
    body: ProjectIn, request: Request, db: Db, user: CurrentUser
) -> ProjectOut:
    """Create a project in the task app, then record its label (FR-024).

    When the task app fails nothing is recorded and the answer is the error.
    """
    made = await _service(request).create_and_label(
        db, user.id, body.connection_id, body.name, body.parent_id, body.label
    )
    return ProjectOut.of(made)


@router.post("/{project_id}/archive")
async def archive_project(
    project_id: uuid.UUID, request: Request, db: Db, user: CurrentUser
) -> ProjectOut:
    """Archive a project in the task app. Tefteri keeps it as orphaned (``archived``)."""
    return ProjectOut.of(await _service(request).archive(db, user.id, project_id))


@router.post("/{project_id}/restore")
async def restore_project(
    project_id: uuid.UUID, request: Request, db: Db, user: CurrentUser
) -> ProjectOut:
    """Restore an archived project in the task app first, then clear its orphaned mark.

    409 ``not_supported`` or 502 when the task app cannot; the project stays as it was.
    """
    return ProjectOut.of(await _service(request).restore(db, user.id, project_id))
