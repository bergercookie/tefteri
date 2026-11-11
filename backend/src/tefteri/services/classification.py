"""Project classification (spec 003): the tree with labels, saving, undo, rename, create, archive.

A label is stored only in tefteri, keyed on the identity of the project in the task app. The
public id of a project in the API is the id of its label row (``ProjectLabel.id``), which also
exists for an orphaned project. Every change of a label adds a history entry, and nothing edits
or deletes one. Every write to the task app happens first, and tefteri records its own change
only when that write worked.
"""

import uuid
from collections import Counter
from collections.abc import Callable, Sequence
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import cast

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.connection import Connection, SourceContainer
from tefteri.db.models.project_label import ProjectLabel as ProjectLabelRow
from tefteri.db.models.project_label import ProjectLabelHistory
from tefteri.db.models.task import Task
from tefteri.domain.classification import (
    Proposal,
    is_eligible,
    label_of,
    parent_theme,
    proposal_of,
)
from tefteri.domain.entities import Container
from tefteri.domain.enums import Capability, OrphanReason, ProjectLabel, SyncState
from tefteri.domain.errors import NotSupported
from tefteri.domain.ports import TaskBackend
from tefteri.services.connections import ConnectionService
from tefteri.services.errors import Conflict, Invalid, NotFound, guard
from tefteri.services.project_labels import (
    ConnectionTree,
    clear_orphan,
    ensure_row,
    load_trees,
    write_labels,
)
from tefteri.services.projects import ProjectService
from tefteri.services.sync import SyncService

SOURCES = ("user", "suggestion")
"""Where a save comes from: the user's own choice, or an accepted proposal."""


@dataclass
class ProjectView:
    """One project of the tree, with everything the screen shows about it."""

    row: ProjectLabelRow
    parent_id: uuid.UUID | None
    proposal: Proposal
    effective_label: ProjectLabel
    parent_theme_id: uuid.UUID | None
    eligible: bool
    open_tasks: int
    subprojects: int
    in_committed_plan: bool

    @property
    def unsorted(self) -> bool:
        """The project has no label and is still live."""
        return self.row.label is None and self.row.orphaned_reason is None


@dataclass
class ConnectionView:
    """The projects of one task connection."""

    connection: Connection
    rename: bool
    restore: bool
    move_tasks: bool
    projects: list[ProjectView] = field(default_factory=list)


@dataclass
class Classification:
    """The answer of ``tree``."""

    connections: list[ConnectionView]
    unsorted_count: int


@dataclass(frozen=True)
class Change:
    """One requested label change. ``label=None`` puts the project back to unclassified."""

    project_id: uuid.UUID
    label: ProjectLabel | None


@dataclass(frozen=True)
class Effect:
    """What a save changes, for the preview and the result (FR-023)."""

    changed: int
    by_change: list[tuple[str, str, int]]
    """``(from, to, count)``; ``none`` stands for no label."""
    in_committed_plan: int


@dataclass(frozen=True)
class SaveResult:
    """The effect of a save and, when something was written, the id of its batch."""

    batch_id: uuid.UUID | None
    effect: Effect


class ClassificationService:
    """Read and change the labels of the projects of the user's task connections."""

    def __init__(
        self,
        connections: ConnectionService,
        projects: ProjectService,
        sync: SyncService,
        clock: Callable[[], datetime] = lambda: datetime.now(UTC),
    ) -> None:
        """Use ``connections`` to reach task apps and ``projects`` to archive.

        ``sync`` reads the projects again after a restore. ``clock`` is injectable for tests.
        """
        self._connections = connections
        self._projects = projects
        self._sync = sync
        self._clock = clock

    # -- reading ------------------------------------------------------------------------------

    async def tree(
        self, db: AsyncSession, user_id: uuid.UUID, connection_id: uuid.UUID | None = None
    ) -> Classification:
        """Return the projects of every task connection (or one) in tree order.

        Each project has its stored label, its proposal, its effective label, its parent theme
        and whether a planning picker may list it. ``unsorted_count`` counts the live projects
        with no label.
        """
        if connection_id is not None:
            connection = await self._connections.get(db, user_id, connection_id)
            if connection is None or connection.kind != "tasks":
                raise NotFound
        views = []
        for tree in await load_trees(db, user_id, connection_id):
            view = ConnectionView(tree.connection, *await self._flags(db, tree.connection))
            view.projects = await self._projects_of(db, tree)
            views.append(view)
        return Classification(views, sum(1 for v in views for p in v.projects if p.unsorted))

    async def project(
        self, db: AsyncSession, user_id: uuid.UUID, project_id: uuid.UUID
    ) -> ProjectView:
        """Return one project of the user."""
        row = await self._own(db, user_id, project_id)
        for view in (await self.tree(db, user_id, row.connection_id)).connections:
            for project in view.projects:
                if project.row.id == project_id:
                    return project
        raise NotFound

    async def _flags(self, db: AsyncSession, connection: Connection) -> tuple[bool, bool, bool]:
        """Return whether the task app can rename projects, restore them and move tasks."""
        try:
            backend = await self._connections.backend_of_owner(db, connection)
            caps = backend.capabilities()
        except Exception:  # noqa: BLE001 - a connection that cannot be built offers none
            return False, False, False
        return (
            Capability.RENAME_PROJECTS in caps,
            Capability.RESTORE_PROJECTS in caps,
            Capability.MOVE_TASKS in caps,
        )

    async def _projects_of(self, db: AsyncSession, tree: ConnectionTree) -> list[ProjectView]:
        containers = {
            c.id: c.remote_id
            for c in (
                await db.execute(
                    select(SourceContainer).where(
                        SourceContainer.connection_id == tree.connection.id
                    )
                )
            ).scalars()
        }
        open_by_remote: Counter[str] = Counter()
        for (container_id,) in await db.execute(
            select(Task.container_id).where(
                Task.connection_id == tree.connection.id,
                Task.status == "open",
                Task.sync_state != SyncState.DELETED_REMOTELY.value,
                Task.container_id.is_not(None),
            )
        ):
            if container_id in containers:
                open_by_remote[containers[container_id]] += 1
        children: dict[str, list[str]] = {}
        for row in tree.rows:
            parent = tree.nodes[str(row.id)].parent_key
            if parent is not None:
                children.setdefault(parent, []).append(str(row.id))
        by_key = {str(r.id): r for r in tree.rows}

        def descendants(key: str) -> int:
            seen: set[str] = {key}
            stack = [key]
            count = 0
            while stack:
                for child in children.get(stack.pop(), []):
                    if child not in seen and by_key[child].orphaned_reason is None:
                        seen.add(child)
                        stack.append(child)
                        count += 1
            return count

        views = {}
        for row in tree.rows:
            key = str(row.id)
            parent = tree.nodes[key].parent_key
            theme = parent_theme(tree.nodes, key)
            views[key] = ProjectView(
                row=row,
                parent_id=uuid.UUID(parent) if parent else None,
                proposal=proposal_of(tree.nodes, key),
                effective_label=label_of(tree.nodes, key),
                parent_theme_id=uuid.UUID(theme) if theme else None,
                eligible=is_eligible(tree.nodes, key),
                open_tasks=open_by_remote[row.remote_id],
                subprojects=descendants(key),
                in_committed_plan=key in tree.in_committed_plan,
            )
        ordered: list[ProjectView] = []
        seen: set[str] = set()

        def walk(key: str) -> None:
            if key in seen:
                return
            seen.add(key)
            ordered.append(views[key])
            for child in children.get(key, []):
                walk(child)

        for row in tree.rows:  # sorted by name: roots, and then the rest in case of a cycle
            if tree.nodes[str(row.id)].parent_key is None:
                walk(str(row.id))
        for row in tree.rows:
            walk(str(row.id))
        return ordered

    async def _own(
        self, db: AsyncSession, user_id: uuid.UUID, project_id: uuid.UUID
    ) -> ProjectLabelRow:
        row = await db.get(ProjectLabelRow, project_id)
        if row is None or row.user_id != user_id:
            raise NotFound
        return row

    # -- labels -------------------------------------------------------------------------------

    async def save(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        changes: Sequence[Change],
        *,
        dry_run: bool = False,
        source: str = "user",
    ) -> SaveResult:
        """Set labels, or only say what that would do (``dry_run``).

        One code path computes the effect, so the preview and the save cannot disagree. A save
        adds one history entry for each project whose label really changes, all with the same
        ``batch_id`` that ``undo`` takes. A change to the label a project already has does
        nothing. When one project appears twice, the last change counts.
        """
        if source not in SOURCES:
            raise Invalid(f"Unknown source: {source}")
        wanted: dict[uuid.UUID, ProjectLabel | None] = {}
        for change in changes:
            wanted[change.project_id] = change.label
        rows = {pid: await self._own(db, user_id, pid) for pid in wanted}
        todo = [
            (row, wanted[pid])
            for pid, row in rows.items()
            if (ProjectLabel(row.label) if row.label else None) != wanted[pid]
        ]
        pending = set()
        for tree in await load_trees(db, user_id):
            pending |= {k for k in tree.in_committed_plan}
        counts = Counter(
            (row.label or "none", label.value if label else "none") for row, label in todo
        )
        effect = Effect(
            changed=len(todo),
            by_change=[(a, b, n) for (a, b), n in sorted(counts.items())],
            in_committed_plan=sum(1 for row, _ in todo if str(row.id) in pending),
        )
        if dry_run or not todo:
            return SaveResult(None, effect)
        batch_id = uuid.uuid4()
        await write_labels(db, todo, now=self._clock(), batch_id=batch_id, source=source)
        return SaveResult(batch_id, effect)

    async def undo(self, db: AsyncSession, user_id: uuid.UUID, batch_id: uuid.UUID) -> int:
        """Give the projects of a save the labels they had before it. Returns how many.

        Undo adds new history entries and never edits the old ones. The entries of an undo carry
        the id of the batch they undo, so a second undo of the same batch is refused.
        """
        entries = list(
            (
                await db.execute(
                    select(ProjectLabelHistory, ProjectLabelRow)
                    .join(ProjectLabelRow, ProjectLabelRow.id == ProjectLabelHistory.project_id)
                    .where(
                        ProjectLabelHistory.batch_id == batch_id,
                        ProjectLabelRow.user_id == user_id,
                    )
                )
            ).all()
        )
        if not entries:
            raise NotFound
        if any(h.source == "undo" for h, _ in entries):
            raise Conflict("already_undone", "This change was already undone.")
        todo: list[tuple[ProjectLabelRow, ProjectLabel | None]] = []
        for entry, row in entries:
            earlier = (
                await db.execute(
                    select(ProjectLabelHistory)
                    .where(
                        ProjectLabelHistory.project_id == row.id,
                        ProjectLabelHistory.from_at < entry.from_at,
                    )
                    .order_by(ProjectLabelHistory.from_at.desc())
                    .limit(1)
                )
            ).scalar_one_or_none()
            todo.append((row, ProjectLabel(earlier.label) if earlier and earlier.label else None))
        await write_labels(db, todo, now=self._clock(), batch_id=batch_id, source="undo")
        return len(todo)

    # -- writes to the task app ---------------------------------------------------------------

    async def _backend(self, db: AsyncSession, connection: Connection) -> TaskBackend:
        return cast(TaskBackend, await self._connections.backend_of_owner(db, connection))

    async def rename(
        self, db: AsyncSession, user_id: uuid.UUID, project_id: uuid.UUID, name: str
    ) -> ProjectView:
        """Rename a project in the task app first, then here (FR-013).

        When the task app refuses or cannot rename, nothing changes here. A project that is no
        longer in the task app cannot be renamed.
        """
        title = name.strip()
        if not title:
            raise Invalid("Give the project a name.")
        row = await self._own(db, user_id, project_id)
        connection = await db.get(Connection, row.connection_id)
        if row.orphaned_reason is not None or connection is None:
            raise NotFound
        backend = await self._backend(db, connection)
        if Capability.RENAME_PROJECTS not in backend.capabilities():
            await guard(connection, _unsupported(Capability.RENAME_PROJECTS))
        await guard(
            connection,
            backend.rename_container(
                Container(row.remote_id, row.name, row.parent_remote_id), title
            ),
        )
        row.name = title
        container = await _container_of(db, row)
        if container is not None:
            container.name = title
        await db.flush()
        return await self.project(db, user_id, project_id)

    async def create_and_label(
        self,
        db: AsyncSession,
        user_id: uuid.UUID,
        connection_id: uuid.UUID,
        name: str,
        parent_id: uuid.UUID | None,
        label: ProjectLabel,
        *,
        source: str = "user",
    ) -> ProjectView:
        """Create a project in the task app and label it (the shared rule of FR-024).

        The project is written to the task app first. The label is recorded only when that
        worked. When recording fails afterwards, the next sync finds the project and proposes a
        label for it.
        """
        title = name.strip()
        if not title:
            raise Invalid("Give the project a name.")
        connection = await self._connections.get(db, user_id, connection_id)
        if connection is None or connection.kind != "tasks":
            raise NotFound
        parent_row = await self._own(db, user_id, parent_id) if parent_id else None
        if parent_row is not None and (
            parent_row.connection_id != connection.id or parent_row.orphaned_reason is not None
        ):
            raise Invalid("The project to put it in is not in this task app any more.")
        backend = await self._backend(db, connection)
        parent = (
            Container(parent_row.remote_id, parent_row.name, parent_row.parent_remote_id)
            if parent_row
            else None
        )
        if parent is not None and Capability.SUBPROJECTS not in backend.capabilities():
            await guard(connection, _unsupported(Capability.SUBPROJECTS))
        remote = await guard(connection, backend.create_container(title, parent))
        parent_remote = remote.parent_id or (parent_row.remote_id if parent_row else None)
        db.add(
            SourceContainer(
                user_id=user_id,
                connection_id=connection.id,
                remote_id=remote.remote_id,
                name=remote.name,
                parent_remote_id=parent_remote,
                color=remote.color,
            )
        )
        row = await ensure_row(db, connection, remote.remote_id, remote.name, parent_remote)
        await write_labels(
            db, [(row, label)], now=self._clock(), batch_id=uuid.uuid4(), source=source
        )
        return await self.project(db, user_id, row.id)

    async def archive(
        self, db: AsyncSession, user_id: uuid.UUID, project_id: uuid.UUID
    ) -> ProjectView:
        """Archive a project in the task app.

        Tefteri keeps it as orphaned with the reason ``archived``, with its label, and restores
        it on request (FR-010, FR-027).
        """
        row = await self._own(db, user_id, project_id)
        container = await _container_of(db, row)
        if row.orphaned_reason is not None or container is None:
            raise Invalid("This project is not in your task app any more.")
        await self._projects.archive(db, user_id, container.id)
        return await self.project(db, user_id, project_id)

    async def restore(
        self, db: AsyncSession, user_id: uuid.UUID, project_id: uuid.UUID
    ) -> ProjectView:
        """Bring an archived project back in the task app first, then clear its orphan mark.

        The subprojects that went with it come back too. Each one is cleared only after the
        task app restored it, so a failure half way leaves the rest as it was.
        """
        row = await self._own(db, user_id, project_id)
        connection = await db.get(Connection, row.connection_id)
        if row.orphaned_reason != OrphanReason.ARCHIVED.value or connection is None:
            raise Invalid("Only a project that you archived from tefteri can be restored.")
        backend = await self._backend(db, connection)
        if Capability.RESTORE_PROJECTS not in backend.capabilities():
            await guard(connection, _unsupported(Capability.RESTORE_PROJECTS))
        family = await self._archived_family(db, row)
        for member in family:
            await guard(
                connection,
                backend.restore_container(
                    Container(member.remote_id, member.name, member.parent_remote_id)
                ),
            )
            clear_orphan(member)
            await db.flush()
        await self._sync.sync_connection(db, connection)
        return await self.project(db, user_id, project_id)

    async def _archived_family(
        self, db: AsyncSession, root: ProjectLabelRow
    ) -> list[ProjectLabelRow]:
        """Return ``root`` and the archived projects inside it, parents before children."""
        rows = list(
            (
                await db.execute(
                    select(ProjectLabelRow).where(
                        ProjectLabelRow.connection_id == root.connection_id,
                        ProjectLabelRow.orphaned_reason == OrphanReason.ARCHIVED.value,
                    )
                )
            ).scalars()
        )
        family = [root]
        known = {root.remote_id}
        grew = True
        while grew:
            grew = False
            for r in rows:
                if r.parent_remote_id in known and r.remote_id not in known:
                    family.append(r)
                    known.add(r.remote_id)
                    grew = True
        return family


async def _container_of(db: AsyncSession, row: ProjectLabelRow) -> SourceContainer | None:
    return (
        await db.execute(
            select(SourceContainer).where(
                SourceContainer.connection_id == row.connection_id,
                SourceContainer.remote_id == row.remote_id,
            )
        )
    ).scalar_one_or_none()


async def _unsupported(capability: Capability) -> None:
    raise NotSupported(capability)
