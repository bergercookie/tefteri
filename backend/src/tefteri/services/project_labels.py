"""Shared database steps for project labels (spec 003): rows, history, orphans, trees.

``sync``, ``projects``, ``weekly`` and ``classification`` all use these functions, so the rules
for the rows live in one place. Nothing here deletes a label row or edits a history row.
"""

import uuid
from collections.abc import Iterable
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.connection import Connection, SourceContainer
from tefteri.db.models.project_label import ProjectLabel as ProjectLabelRow
from tefteri.db.models.project_label import ProjectLabelHistory
from tefteri.db.models.weekly import WeeklyPlan, WeeklyPlanProject
from tefteri.domain.classification import ProjectNode
from tefteri.domain.entities import Container
from tefteri.domain.enums import ConnectionKind, OrphanReason, ProjectLabel


def aware(value: datetime) -> datetime:
    """Return ``value`` as UTC. SQLite gives back naive times."""
    return value if value.tzinfo else value.replace(tzinfo=UTC)


async def _rows_by_remote(db: AsyncSession, connection_id: uuid.UUID) -> dict[str, ProjectLabelRow]:
    return {
        r.remote_id: r
        for r in (
            await db.execute(
                select(ProjectLabelRow).where(ProjectLabelRow.connection_id == connection_id)
            )
        ).scalars()
    }


async def ensure_row(
    db: AsyncSession,
    connection: Connection,
    remote_id: str,
    name: str,
    parent_remote_id: str | None,
) -> ProjectLabelRow:
    """Return the label row of a project, adding an unclassified one when there is none."""
    row = (
        await db.execute(
            select(ProjectLabelRow).where(
                ProjectLabelRow.connection_id == connection.id,
                ProjectLabelRow.remote_id == remote_id,
            )
        )
    ).scalar_one_or_none()
    if row is None:
        row = ProjectLabelRow(
            user_id=connection.user_id,
            connection_id=connection.id,
            remote_id=remote_id,
            name=name,
            parent_remote_id=parent_remote_id,
        )
        db.add(row)
        await db.flush()
    return row


async def reconcile(
    db: AsyncSession, connection: Connection, listed: Iterable[Container], now: datetime
) -> None:
    """Bring the label rows of a task connection in line with the projects the app lists.

    A new project gets an unclassified row. A listed project gets its title and parent updated,
    and its orphan mark cleared (FR-009, FR-011). A live row whose project is no longer listed is
    marked orphaned with the reason ``missing`` (FR-010). A row is never deleted and its label
    is never changed here, so a rename or a move keeps the label (FR-014).
    """
    rows = await _rows_by_remote(db, connection.id)
    seen: set[str] = set()
    for container in listed:
        seen.add(container.remote_id)
        row = rows.get(container.remote_id)
        if row is None:
            row = ProjectLabelRow(
                user_id=connection.user_id,
                connection_id=connection.id,
                remote_id=container.remote_id,
                name=container.name,
                parent_remote_id=container.parent_id,
            )
            db.add(row)
            rows[container.remote_id] = row
            continue
        row.name = container.name
        row.parent_remote_id = container.parent_id
        row.orphaned_reason = None
        row.orphaned_at = None
    for remote_id, row in rows.items():
        if remote_id not in seen and row.orphaned_reason is None:
            row.orphaned_reason = OrphanReason.MISSING.value
            row.orphaned_at = now
    await db.flush()


def mark_orphaned(row: ProjectLabelRow, reason: OrphanReason, now: datetime) -> None:
    """Mark a project as no longer in the task app. Its label and history stay."""
    row.orphaned_reason = reason.value
    row.orphaned_at = now


def clear_orphan(row: ProjectLabelRow) -> None:
    """Clear the orphan mark of a project that is back."""
    row.orphaned_reason = None
    row.orphaned_at = None


async def write_labels(
    db: AsyncSession,
    changes: Iterable[tuple[ProjectLabelRow, ProjectLabel | None]],
    *,
    now: datetime,
    batch_id: uuid.UUID | None,
    source: str,
) -> None:
    """Set the label of each project and append one history entry for it.

    The entry of a project starts strictly after its previous entry, so the order of the
    history is always clear, even when two saves happen in the same instant.
    """
    pending = list(changes)
    if not pending:
        return
    latest = {
        project_id: aware(at)
        for project_id, at in (
            await db.execute(
                select(ProjectLabelHistory.project_id, func.max(ProjectLabelHistory.from_at))
                .where(ProjectLabelHistory.project_id.in_([row.id for row, _ in pending]))
                .group_by(ProjectLabelHistory.project_id)
            )
        ).all()
    }
    for row, label in pending:
        at = now
        before = latest.get(row.id)
        if before is not None and at <= before:
            at = before + timedelta(microseconds=1)
        row.label = label.value if label is not None else None
        row.label_changed_at = at
        db.add(
            ProjectLabelHistory(
                project_id=row.id,
                label=row.label,
                from_at=at,
                batch_id=batch_id,
                source=source,
            )
        )
    await db.flush()


@dataclass
class ConnectionTree:
    """The projects of one task connection, ready for the rules of ``domain.classification``."""

    connection: Connection
    rows: list[ProjectLabelRow]
    nodes: dict[str, ProjectNode]
    """By ``str(row.id)``."""
    key_by_remote: dict[str, str] = field(default_factory=dict)
    in_committed_plan: set[str] = field(default_factory=set)
    """Keys of the projects in a committed plan that has no look-back yet."""


async def load_trees(
    db: AsyncSession, user_id: uuid.UUID, connection_id: uuid.UUID | None = None
) -> list[ConnectionTree]:
    """Load the project tree of each task connection of the user.

    A project that the app listed before the labels existed, or that was just created, gets
    its unclassified row here, so a caller never misses a live project.
    """
    query = select(Connection).where(
        Connection.user_id == user_id, Connection.kind == ConnectionKind.TASKS.value
    )
    if connection_id is not None:
        query = query.where(Connection.id == connection_id)
    connections = list((await db.execute(query.order_by(Connection.created_at))).scalars())
    ids = [c.id for c in connections]
    containers = list(
        (
            await db.execute(select(SourceContainer).where(SourceContainer.connection_id.in_(ids)))
        ).scalars()
    )
    committed: set[uuid.UUID] = set()
    pending_plan: set[uuid.UUID] = set()
    for container_id, reviewed_at in (
        await db.execute(
            select(WeeklyPlanProject.container_id, WeeklyPlan.reviewed_at)
            .join(WeeklyPlan, WeeklyPlan.id == WeeklyPlanProject.plan_id)
            .where(
                WeeklyPlan.user_id == user_id,
                WeeklyPlan.status == "committed",
                WeeklyPlanProject.container_id.is_not(None),
            )
        )
    ).all():
        if container_id is None:
            continue
        committed.add(container_id)
        if reviewed_at is None:
            pending_plan.add(container_id)
    committed_remote = {(c.connection_id, c.remote_id) for c in containers if c.id in committed}
    pending_remote = {(c.connection_id, c.remote_id) for c in containers if c.id in pending_plan}
    trees = []
    for connection in connections:
        rows = await _rows_by_remote(db, connection.id)
        for c in containers:
            if c.connection_id == connection.id and c.remote_id not in rows:
                rows[c.remote_id] = await ensure_row(
                    db, connection, c.remote_id, c.name, c.parent_remote_id
                )
        ordered = sorted(rows.values(), key=lambda r: (r.name.casefold(), r.remote_id))
        key_by_remote = {r.remote_id: str(r.id) for r in ordered}
        nodes = {
            str(r.id): ProjectNode(
                key=str(r.id),
                parent_key=key_by_remote.get(r.parent_remote_id or ""),
                label=ProjectLabel(r.label) if r.label else None,
                was_committed=(connection.id, r.remote_id) in committed_remote,
                orphaned=r.orphaned_reason is not None,
            )
            for r in ordered
        }
        trees.append(
            ConnectionTree(
                connection,
                ordered,
                nodes,
                key_by_remote,
                {str(r.id) for r in ordered if (connection.id, r.remote_id) in pending_remote},
            )
        )
    return trees
