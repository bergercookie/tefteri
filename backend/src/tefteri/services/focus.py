"""The monthly focus, as far as weekly planning needs to read it (spec 004, research R-14).

Weekly planning shows which themes are in the focus of the month, but the focus itself belongs
to a later feature (007). This module is the seam: ``FocusProvider`` is what planning reads, and
``NoFocus`` is the default until that feature exists. Feature 007 supplies a real provider and
changes only the wiring in ``main.py``.
"""

import uuid
from datetime import date
from typing import Protocol

from sqlalchemy.ext.asyncio import AsyncSession


class FocusProvider(Protocol):
    """Tells which theme projects are in the focus of a month."""

    async def themes_for_month(
        self, db: AsyncSession, user_id: uuid.UUID, month_start: date
    ) -> set[uuid.UUID] | None:
        """Return the ids of the focus themes of the month (the ids of their label rows).

        ``None`` means that no focus data exists for that month. Then planning highlights no
        theme, shows nothing as outside focus and shows no focus share.
        """
        ...


class NoFocus:
    """The default provider: there is no monthly focus yet. Feature 007 replaces it in main."""

    async def themes_for_month(
        self,
        db: AsyncSession,  # noqa: ARG002
        user_id: uuid.UUID,  # noqa: ARG002
        month_start: date,  # noqa: ARG002
    ) -> set[uuid.UUID] | None:
        """Return ``None``: no focus data."""
        return None
