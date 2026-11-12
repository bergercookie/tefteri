"""The inbound value push (spec 006, FR-010): tokens, digest only, and the push rules.

One token per user, only its SHA-256 digest is stored. The push route works without a session:
it holds the user of the token, but it cannot touch anything else. Too many pushes in a short
time are refused, and the same value twice is stored once.
"""

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
from tefteri.domain.enums import GoalState, ValueSource
from tefteri.security.tokens import digest_token, new_push_token, token_hint
from tefteri.services.key_results import KeyResultService

PUSH_PREFIX = "tfv_"
"""Every push token starts with this prefix."""

RATE_LIMIT = 60
"""At most this many pushes per minute per token."""

RATE_WINDOW = timedelta(minutes=1)


class PushRejected(Exception):
    """A push was refused. ``status`` and ``code`` name the answer (contract, section 4)."""

    def __init__(self, status: int, code: str, message: str) -> None:
        """Store the HTTP status, the stable ``code`` and the message for the user."""
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message


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
    key_result_id: uuid.UUID | None = None
    value: float | None = None
    at: datetime | None = None
    current_value: float | None = None


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
            exc = PushRejected(429, "rate_limited", "Too many pushes in one minute.")
            exc.retry_after = retry
            raise exc
        seen.append(now)
        self._seen[token] = seen

    async def push(
        self,
        db: AsyncSession,
        token: str,
        key_result_id: uuid.UUID,
        value: float,
        at: datetime | None,
        *,
        value_tolerance: float = 0.0,
    ) -> PushOutcome:
        """Store an automatic value sent by the owner's tool (FR-010).

        The token says who pushes; the key result must belong to that user and be automatic.
        The same value for the same time is stored once. A rejected push stores nothing.
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
        if row.update_source != "automatic":
            raise PushRejected(
                409, "not_automatic", "A manual key result takes its values by hand."
            )
        now = self._clock()
        if at is None:
            at = now
        if at.tzinfo is None or at.tzinfo.utcoffset(at) is None:
            raise PushRejected(422, "invalid", "The time of the value needs a time zone.")
        if at > now + timedelta(minutes=5):
            raise PushRejected(422, "invalid", "The time of the value is in the future.")
        if value != value or value in (float("inf"), float("-inf")):
            raise PushRejected(422, "invalid", "The value must be a finite number.")
        same = (
            await db.execute(
                select(KeyResultValue).where(
                    KeyResultValue.key_result_id == key_result_id,
                    KeyResultValue.source == ValueSource.AUTOMATIC.value,
                    KeyResultValue.at == at,
                    KeyResultValue.value == value,
                )
            )
        ).scalar_one_or_none()
        if same is not None:
            return PushOutcome(
                stored=False, key_result_id=key_result_id, value=value, at=at, current_value=value
            )
        user = await db.get(User, user_id)
        zone = ZoneInfo(user.timezone if user else "UTC")
        await self._key_results._insert_value(
            db,
            row,
            value=value,
            at=at,
            on_date=at.astimezone(zone).date(),
            source=ValueSource.AUTOMATIC,
        )
        token_row = (
            await db.execute(
                select(ValuePushToken).where(ValuePushToken.token_hash == digest_token(token))
            )
        ).scalar_one()
        token_row.last_used_at = now
        await db.flush()
        return PushOutcome(
            stored=True, key_result_id=key_result_id, value=value, at=at, current_value=value
        )
