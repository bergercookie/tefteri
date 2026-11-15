"""The monthly focus, as far as weekly planning needs to read it (spec 004, research R-14).

Weekly planning shows which themes are in the focus of the month. The focus itself belongs to
monthly planning (spec 007, ``services.monthly_focus``). This module is the seam:
``FocusProvider`` is what weekly planning reads. ``MonthlyFocusService`` is the real provider,
and ``main.py`` wires it. ``NoFocus`` is the fallback for code that has no provider, for example
a test.
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
    """The fallback provider: it knows no focus. ``main.py`` wires the real one (spec 007)."""

    async def themes_for_month(
        self,
        db: AsyncSession,  # noqa: ARG002
        user_id: uuid.UUID,  # noqa: ARG002
        month_start: date,  # noqa: ARG002
    ) -> set[uuid.UUID] | None:
        """Return ``None``: no focus data."""
        return None
