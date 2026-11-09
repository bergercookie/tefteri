"""Small lookups that several routers share."""

import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.connection import SourceContainer


async def container_colors(db: AsyncSession, user_id: uuid.UUID) -> dict[uuid.UUID, str]:
    """Return the color of each calendar that has one, by container id.

    It is the color that the user chose in the calendar app (Google Calendar).
    """
    rows = await db.execute(
        select(SourceContainer.id, SourceContainer.color).where(
            SourceContainer.user_id == user_id, SourceContainer.color.is_not(None)
        )
    )
    return {container_id: color for container_id, color in rows if color}
