"""Shared write steps for the plan history and the theme links (spec 006).

``annual_plan`` and ``key_results`` both use these functions, so the rules for the history
live in one place. Every user action writes one batch: one ``batch_id`` for all of its
``plan_changes`` rows (R-05). Nothing here edits or deletes a history row, and a link row is
never deleted: removing or replacing one ends it with a date and a reason (FR-013).
"""

import uuid
from collections.abc import Iterable, Sequence
from dataclasses import dataclass, field
from datetime import datetime, timedelta

from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.key_result import KeyResultTheme, PlanChange
from tefteri.domain.enums import LinkEndReason, PlanChangeKind


@dataclass
class RetireEffect:
    """What retiring a goal or a key result changes (FR-021, FR-032)."""

    key_results_retired: int = 0
    links_ended: int = 0
    flags_removed: list[str] = field(default_factory=list)
    history_kept: bool = True


@dataclass(frozen=True)
class ThemeEntry:
    """One project of a link effect, as the answer shows it.

    ``state`` is set on the skipped entries of a restore (FR-021).
    """

    project_id: uuid.UUID
    name: str
    state: str | None = None


@dataclass
class LinkSetEffect:
    """What changing the links of a key result does (FR-013)."""

    added: list[ThemeEntry] = field(default_factory=list)
    ended: list[ThemeEntry] = field(default_factory=list)
    flags_removed: list[str] = field(default_factory=list)
    flags_added: list[str] = field(default_factory=list)


def change(
    user_id: uuid.UUID,
    year: int,
    kind: PlanChangeKind,
    *,
    goal_id: uuid.UUID | None = None,
    key_result_id: uuid.UUID | None = None,
    link_id: uuid.UUID | None = None,
    field_name: str | None = None,
    old_value: str | None = None,
    new_value: str | None = None,
    reason: str | None = None,
) -> PlanChange:
    """Build one history row. The caller sets ``batch_id`` and ``source`` on the batch write."""
    return PlanChange(
        user_id=user_id,
        year=year,
        goal_id=goal_id,
        key_result_id=key_result_id,
        link_id=link_id,
        kind=kind.value,
        field=field_name,
        old_value=old_value,
        new_value=new_value,
        reason=reason,
    )


async def write_batch(
    db: AsyncSession,
    changes: Iterable[PlanChange],
    *,
    batch_id: uuid.UUID | None,
    source: str,
    now: datetime,
) -> None:
    """Append the history rows of one user action. Nothing is written for an empty batch.

    The rows of one batch get strictly increasing ``at`` stamps, so the time order of the
    history is always clear, even when everything happens in the same instant.
    """
    at = now
    for row in changes:
        row.batch_id = batch_id
        row.source = source
        row.at = at
        at = at + MICROSECOND
        db.add(row)
    await db.flush()


MICROSECOND = timedelta(microseconds=1)
"""One step of the ``at`` stamps inside a batch, so the time order stays clear."""


async def start_link(
    db: AsyncSession,
    user_id: uuid.UUID,
    key_result_id: uuid.UUID,
    project_id: uuid.UUID,
    year: int,
    *,
    now: datetime,
    batch_id: uuid.UUID | None,
    source: str,
) -> KeyResultTheme:
    """Record that a key result is served by a theme project, from now on (FR-011)."""
    link = KeyResultTheme(
        user_id=user_id,
        key_result_id=key_result_id,
        project_id=project_id,
        year=year,
        started_at=now,
        batch_id=batch_id,
    )
    db.add(link)
    await db.flush()
    await write_batch(
        db,
        [
            change(
                user_id,
                year,
                PlanChangeKind.LINK_ADDED,
                key_result_id=key_result_id,
                link_id=link.id,
                new_value=None,
            )
        ],
        batch_id=batch_id,
        source=source,
        now=now,
    )
    return link


async def end_link(
    db: AsyncSession,
    link: KeyResultTheme,
    reason: LinkEndReason,
    *,
    now: datetime,
    batch_id: uuid.UUID | None,
    source: str,
) -> None:
    """End a link with a date and a reason; the row is kept (FR-013)."""
    link.ended_at = now
    link.end_reason = reason.value
    link.batch_id = batch_id
    await db.flush()
    await write_batch(
        db,
        [
            change(
                link.user_id,
                link.year,
                PlanChangeKind.LINK_REMOVED,
                key_result_id=link.key_result_id,
                link_id=link.id,
            )
        ],
        batch_id=batch_id,
        source=source,
        now=now,
    )


async def end_links(
    db: AsyncSession,
    links: Sequence[KeyResultTheme],
    reason: LinkEndReason,
    *,
    now: datetime,
    batch_id: uuid.UUID | None,
    source: str,
) -> int:
    """End several links in one batch. Returns how many ended."""
    for link in links:
        link.ended_at = now
        link.end_reason = reason.value
        link.batch_id = batch_id
    if links:
        await db.flush()
    await write_batch(
        db,
        [
            change(
                link.user_id,
                link.year,
                PlanChangeKind.LINK_REMOVED,
                key_result_id=link.key_result_id,
                link_id=link.id,
            )
            for link in links
        ],
        batch_id=batch_id,
        source=source,
        now=now,
    )
    return len(links)
