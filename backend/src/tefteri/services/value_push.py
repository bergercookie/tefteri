"""The inbound value push (spec 006, FR-010): tokens, digest only, and the push rules.

One token per user, only its SHA-256 digest is stored. The push route works without a session:
it holds the user of the token, but it cannot touch anything else. Too many pushes in a short
time are refused, and the same value twice is stored once.
"""

import math
import uuid
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from tefteri.db.models.key_result import KeyResult, KeyResultValue
from tefteri.db.models.push_token import ValuePushToken
from tefteri.db.models.user import User
from tefteri.domain.enums import GoalState, UpdateSource, ValueSource
from tefteri.security.tokens import digest_token, new_push_token, token_hint
from tefteri.services.key_results import KeyResultService

PUSH_PREFIX = "tfv_"
"""Every push token starts with this prefix."""

RATE_LIMIT = 60
"""At most this many pushes per minute per token."""

RATE_WINDOW = timedelta(minutes=1)

FUTURE_SLACK = timedelta(minutes=5)
"""A pushed time may be this much ahead of the server clock (clock skew)."""


class PushRejected(Exception):
    """A push was refused. ``status`` and ``code`` name the answer (contract, section 4)."""

    def __init__(
        self, status: int, code: str, message: str, retry_after: int | None = None
    ) -> None:
        """Store the HTTP status, the stable ``code``, the message and, for 429, the wait."""
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message
        self.retry_after = retry_after


@dataclass
class PushStatus:
    """The answer of ``GET /annual/push-token``."""

    exists: bool
    hint: str | None = None
    created_at: datetime | None = None
    last_used_at: datetime | None = None


@dataclass
class PushOutcome:
    """The answer of a push: whether a row was stored and the state it left behind."""

    stored: bool
    key_result_id: uuid.UUID
    value: float
    at: datetime
    current_value: float


class PushTokenService:
    """Issue, rotate, revoke and authenticate the push token, and accept pushes."""

    def __init__(
        self,
        key_results: KeyResultService,
        clock: Callable[[], datetime] = lambda: datetime.now(UTC),
    ) -> None:
        """``key_results`` stores the values; ``clock`` is injectable for tests."""
        self._key_results = key_results
        self._clock = clock
        self._seen: dict[str, list[datetime]] = {}
        """Accepted pushes per token hash, for the rate limit (in memory)."""

    async def status(self, db: AsyncSession, user_id: uuid.UUID) -> PushStatus:
        """Return whether a push token exists and when it was last used (FR-010)."""
        row = (
            await db.execute(select(ValuePushToken).where(ValuePushToken.user_id == user_id))
        ).scalar_one_or_none()
        if row is None:
            return PushStatus(exists=False)
        return PushStatus(
            exists=True,
            hint=row.hint,
            created_at=row.created_at,
            last_used_at=row.last_used_at,
        )

    async def issue(self, db: AsyncSession, user_id: uuid.UUID) -> tuple[str, str]:
        """Issue or rotate the push token. The plain token is returned exactly once (R-07)."""
        token = new_push_token()
        row = (
            await db.execute(select(ValuePushToken).where(ValuePushToken.user_id == user_id))
        ).scalar_one_or_none()
        if row is None:
            row = ValuePushToken(
                user_id=user_id,
                token_hash=digest_token(token),
                hint=token_hint(token),
                created_at=self._clock(),
            )
            db.add(row)
        else:
            row.token_hash = digest_token(token)
            row.hint = token_hint(token)
            row.created_at = self._clock()
        await db.flush()
        return token, row.hint

    async def revoke(self, db: AsyncSession, user_id: uuid.UUID) -> None:
        """Delete the push token. A later push is refused with ``invalid_push_token``."""
        await db.execute(delete(ValuePushToken).where(ValuePushToken.user_id == user_id))
        await db.flush()

    async def user_of(self, db: AsyncSession, token: str) -> uuid.UUID | None:
        """Return the user of a valid token, or ``None`` (R-07)."""
        row = (
            await db.execute(
                select(ValuePushToken).where(ValuePushToken.token_hash == digest_token(token))
            )
        ).scalar_one_or_none()
        return row.user_id if row else None

    def _throttle(self, token: str) -> None:
        """Refuse the 61st push of a minute with 429 (R-07)."""
        now = self._clock()
        window_start = now - RATE_WINDOW
        seen = [at for at in self._seen.get(token, []) if at > window_start]
        if len(seen) >= RATE_LIMIT:
            self._seen[token] = seen
            retry = int((seen[0] + RATE_WINDOW - now).total_seconds()) + 1
            raise PushRejected(
                429, "rate_limited", "Too many pushes in one minute. Try again later.", retry
            )
        seen.append(now)
        self._seen[token] = seen

    async def push(
        self,
        db: AsyncSession,
        token: str,
        key_result_id: uuid.UUID,
        value: object,
        at: object,
    ) -> PushOutcome:
        """Store an automatic value sent by the owner's tool (FR-010, contract section 4).

        The token says who pushes; the key result must belong to that user and be automatic.
        ``value`` must be a finite JSON number (not a string, a boolean or null) and ``at`` an
        ISO 8601 time with a zone, not more than five minutes in the future. The same value for
        the same time is stored once. A rejected push stores nothing: the caller rolls back.
        """
        user_id = await self.user_of(db, token)
        if user_id is None:
            raise PushRejected(401, "invalid_push_token", "The push token is not valid.")
        self._throttle(digest_token(token))
        row = await db.get(KeyResult, key_result_id)
        if row is None or row.user_id != user_id:
            raise PushRejected(404, "not_found", "There is no such key result.")
        if row.status == GoalState.RETIRED.value:
            raise PushRejected(409, "retired", "A retired key result accepts no new value.")
        if row.update_source != UpdateSource.AUTOMATIC.value:
            raise PushRejected(
                409, "not_automatic", "Only a key result marked automatic accepts a push."
            )
        number = _finite_number(value)
        now = self._clock()
        stamp = _stamp(at, now)
        same = (
            await db.execute(
                select(KeyResultValue).where(
                    KeyResultValue.key_result_id == key_result_id,
                    KeyResultValue.source == ValueSource.AUTOMATIC.value,
                    KeyResultValue.value == number,
                )
            )
        ).scalars()
        if any(_same_instant(existing.at, stamp) for existing in same):
            current = self._key_results.current(row, await self._key_results.entries(db, row))
            return PushOutcome(
                stored=False,
                key_result_id=key_result_id,
                value=number,
                at=stamp,
                current_value=current,
            )
        user = await db.get(User, user_id)
        zone = ZoneInfo(user.timezone if user else "UTC")
        await self._key_results._insert_value(
            db,
            row,
            value=number,
            at=stamp,
            on_date=stamp.astimezone(zone).date(),
            source=ValueSource.AUTOMATIC,
        )
        token_row = (
            await db.execute(
                select(ValuePushToken).where(ValuePushToken.token_hash == digest_token(token))
            )
        ).scalar_one()
        token_row.last_used_at = now
        await db.flush()
        current = self._key_results.current(row, await self._key_results.entries(db, row))
        return PushOutcome(
            stored=True, key_result_id=key_result_id, value=number, at=stamp, current_value=current
        )


def _finite_number(value: object) -> float:
    """Return ``value`` as a float when it is a finite JSON number, else refuse with 422."""
    if isinstance(value, bool) or not isinstance(value, int | float):
        raise PushRejected(422, "invalid", "The value must be a number.")
    number = float(value)
    if not math.isfinite(number):
        raise PushRejected(422, "invalid", "The value must be a finite number.")
    return number


def _stamp(at: object, now: datetime) -> datetime:
    """Parse the time of a pushed value: ISO 8601 with a zone, not in the future (R-07)."""
    if not isinstance(at, str) or not at.strip():
        raise PushRejected(422, "invalid", "Give the time of the value, with a time zone.")
    raw = at.strip()
    if raw.endswith(("Z", "z")):
        raw = raw[:-1] + "+00:00"
    try:
        stamp = datetime.fromisoformat(raw)
    except ValueError as exc:
        raise PushRejected(422, "invalid", "The time of the value is not ISO 8601.") from exc
    if stamp.tzinfo is None or stamp.utcoffset() is None:
        raise PushRejected(422, "invalid", "The time of the value needs a time zone.")
    if stamp > now + FUTURE_SLACK:
        raise PushRejected(422, "invalid", "The time of the value is in the future.")
    return stamp


def _same_instant(stored: datetime, stamp: datetime) -> bool:
    """Compare a stored time (naive UTC on SQLite) with an aware one."""
    if stored.tzinfo is None:
        stored = stored.replace(tzinfo=UTC)
    return stored == stamp
