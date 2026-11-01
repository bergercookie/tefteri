"""Login throttling: too many recent failures block further attempts for a while."""

from collections.abc import Callable
from datetime import UTC, datetime, timedelta


class Throttled(Exception):
    """Raised when a login attempt is blocked."""

    def __init__(self, retry_after: int) -> None:
        """Store the seconds until the block ends."""
        super().__init__(f"too many failed logins; retry in {retry_after}s")
        self.retry_after = retry_after


class LoginThrottle:
    """Per-key failure counter (in memory).

    ``max_failures`` failures within ``window`` seconds block the key for ``block`` seconds.
    """

    def __init__(
        self,
        max_failures: int,
        window: int,
        block: int,
        clock: Callable[[], datetime] = lambda: datetime.now(UTC),
    ) -> None:
        """Configure limits and the (injectable) clock."""
        self._max = max_failures
        self._window = timedelta(seconds=window)
        self._block = timedelta(seconds=block)
        self._clock = clock
        self._failures: dict[str, list[datetime]] = {}
        self._blocked_until: dict[str, datetime] = {}

    def check(self, key: str) -> None:
        """Raise ``Throttled`` if ``key`` is currently blocked."""
        now = self._clock()
        until = self._blocked_until.get(key)
        if until is not None:
            if now < until:
                raise Throttled(int((until - now).total_seconds()) + 1)
            del self._blocked_until[key]
            self._failures.pop(key, None)

    def record_failure(self, key: str) -> None:
        """Record a failed attempt, starting a block when the limit is reached."""
        now = self._clock()
        recent = [t for t in self._failures.get(key, []) if now - t < self._window]
        recent.append(now)
        self._failures[key] = recent
        if len(recent) >= self._max:
            self._blocked_until[key] = now + self._block

    def record_success(self, key: str) -> None:
        """Forget failures after a successful login."""
        self._failures.pop(key, None)
        self._blocked_until.pop(key, None)
