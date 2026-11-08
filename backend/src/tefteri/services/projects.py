"""Projects of a task app: archive one."""

import uuid
from typing import cast

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.connection import Connection, SourceContainer
from tefteri.db.models.task import Task
from tefteri.db.models.weekly import WeeklyPlan, WeeklyPlanProject
from tefteri.domain.entities import Container
from tefteri.domain.enums import Capability, ConnectionKind, SyncState
from tefteri.domain.errors import NotSupported
from tefteri.domain.ports import TaskBackend
from tefteri.services.connections import ConnectionService
from tefteri.services.errors import Invalid, NotFound, guard


class ProjectService:
    """Change projects in the task app."""

    def __init__(self, connections: ConnectionService) -> None:
        """Use ``connections`` to reach each task app."""
        self._connections = connections

    async def archive(self, db: AsyncSession, user_id: uuid.UUID, container_id: uuid.UUID) -> str:
        """Archive a project in the task app, then forget it here. Returns its name.

        The task app keeps the project and can restore it. Its subprojects go with it. Tefteri
        marks their tasks as deleted in the app, as the next sync would, and drops the
        projects from draft plans. Committed plans keep the name of the project.

        A project that is in a committed plan with no look-back yet is refused: its tasks
        are what the look-back counts.
        """
        container = (
            await db.execute(
                select(SourceContainer).where(
                    SourceContainer.id == container_id, SourceContainer.user_id == user_id
                )
            )
        ).scalar_one_or_none()
        connection = await db.get(Connection, container.connection_id) if container else None
        if container is None or connection is None or connection.kind != ConnectionKind.TASKS.value:
            raise NotFound
        everything = list(
            (
                await db.execute(
                    select(SourceContainer).where(SourceContainer.connection_id == connection.id)
                )
            ).scalars()
        )
        family = _with_subprojects(container, everything)
        pending = (
            await db.execute(
                select(WeeklyPlanProject.name)
                .join(WeeklyPlan, WeeklyPlan.id == WeeklyPlanProject.plan_id)
                .where(
                    WeeklyPlanProject.container_id.in_([c.id for c in family]),
                    WeeklyPlan.user_id == user_id,
                    WeeklyPlan.status == "committed",
                    WeeklyPlan.reviewed_at.is_(None),
                )
            )
        ).first()
        if pending is not None:
            raise Invalid(
                f'"{pending[0]}" is part of a plan that you have not looked back at yet. '
                "Look back first, then archive it."
            )
        backend = cast(TaskBackend, await self._connections.backend_of_owner(db, connection))
        if Capability.ARCHIVE_PROJECTS not in backend.capabilities():
            await guard(connection, _unsupported())
        await guard(
            connection,
            backend.archive_container(
                Container(container.remote_id, container.name, container.parent_remote_id)
            ),
        )
        ids = [c.id for c in family]
        # The database sets these references to NULL when the projects go. Do the same in
        # the session, so that rows that are already loaded do not keep a stale id.
        for task in (await db.execute(select(Task).where(Task.container_id.in_(ids)))).scalars():
            task.sync_state = SyncState.DELETED_REMOTELY.value
            task.container_id = None
        for row, status in (
            await db.execute(
                select(WeeklyPlanProject, WeeklyPlan.status)
                .join(WeeklyPlan, WeeklyPlan.id == WeeklyPlanProject.plan_id)
                .where(WeeklyPlanProject.container_id.in_(ids))
            )
        ).all():
            if status == "draft":
                await db.delete(row)
            else:
                row.container_id = None
        await db.flush()
        for c in family:
            await db.delete(c)
        await db.flush()
        return container.name


def _with_subprojects(
    root: SourceContainer, everything: list[SourceContainer]
) -> list[SourceContainer]:
    """Return ``root`` and every project inside it, at any depth."""
    found = [root]
    remote_ids = {root.remote_id}
    grew = True
    while grew:
        grew = False
        for c in everything:
            if c.parent_remote_id in remote_ids and c.remote_id not in remote_ids:
                found.append(c)
                remote_ids.add(c.remote_id)
                grew = True
    return found


async def _unsupported() -> None:
    raise NotSupported(Capability.ARCHIVE_PROJECTS)
