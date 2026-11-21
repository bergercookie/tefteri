"""What is work: the themes that the user marked, and everything under them.

A theme is work when the user marks it. A project or a task is work when its nearest theme (the
project itself, or the closest parent that is a theme) is work. A project under no theme is not
work. The projects of one task app are a tree, so the walk goes up through ``parent_remote_id``.
"""

import uuid
from typing import NamedTuple

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.connection import SourceContainer
from tefteri.db.models.project_label import ProjectLabel

MAX_DEPTH = 64
"""No real project tree is deeper. It also stops a loop in bad parent links."""


class _Key(NamedTuple):
    connection_id: uuid.UUID
    remote_id: str


class WorkScope:
    """Answers "is this project work?" for the projects of one user."""

    def __init__(self, rows: list[ProjectLabel], containers: list[SourceContainer]) -> None:
        """Index the label rows and the containers (the projects that tasks sit in)."""
        self._rows = {_Key(r.connection_id, r.remote_id): r for r in rows}
        self._by_id = {r.id: r for r in rows}
        self._label_of_container = {c.id: _Key(c.connection_id, c.remote_id) for c in containers}
        self._cache: dict[_Key, bool] = {}

    @classmethod
    async def load(cls, db: AsyncSession, user_id: uuid.UUID) -> "WorkScope":
        """Read the label rows and the containers of the user."""
        rows = list(
            (
                await db.execute(select(ProjectLabel).where(ProjectLabel.user_id == user_id))
            ).scalars()
        )
        containers = list(
            (
                await db.execute(select(SourceContainer).where(SourceContainer.user_id == user_id))
            ).scalars()
        )
        return cls(rows, containers)

    @staticmethod
    def own(row: ProjectLabel) -> bool:
        """The theme is marked as work. Only a theme can be."""
        return bool(row.is_work) and row.label == "theme"

    def _of_key(self, key: _Key) -> bool:
        if key in self._cache:
            return self._cache[key]
        seen: set[str] = set()
        node: ProjectLabel | None = self._rows.get(key)
        result = False
        while node is not None and node.remote_id not in seen and len(seen) < MAX_DEPTH:
            seen.add(node.remote_id)
            if node.label == "theme":
                result = self.own(node)
                break
            node = (
                self._rows.get(_Key(node.connection_id, node.parent_remote_id))
                if node.parent_remote_id
                else None
            )
        self._cache[key] = result
        return result

    def of_label(self, label_id: uuid.UUID | None) -> bool:
        """Is the project with this label row id work?"""
        row = self._by_id.get(label_id) if label_id is not None else None
        return row is not None and self._of_key(_Key(row.connection_id, row.remote_id))

    def of_container(self, container_id: uuid.UUID | None) -> bool:
        """Is the project (container) that a task sits in work?"""
        key = self._label_of_container.get(container_id) if container_id is not None else None
        return key is not None and self._of_key(key)

    def of_row(self, row: ProjectLabel) -> bool:
        """Is the project of this label row work?"""
        return self._of_key(_Key(row.connection_id, row.remote_id))
