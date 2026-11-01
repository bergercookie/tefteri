"""Settings validation and login throttling."""

from collections.abc import Callable
from datetime import UTC, datetime, timedelta

import pytest
from pydantic import ValidationError

from tefteri.auth.throttle import LoginThrottle, Throttled
from tefteri.config import Settings


def test_rejects_raw_password(make_settings: Callable[..., Settings]) -> None:
    with pytest.raises(ValidationError):
        make_settings(admin_password_hash="hunter2")


def test_accepts_argon2_hash(make_settings: Callable[..., Settings]) -> None:
    assert make_settings().admin_password_hash.startswith("$argon2")


def test_defaults(make_settings: Callable[..., Settings]) -> None:
    s = make_settings()
    assert (s.login_max_failures, s.login_window_seconds, s.login_block_seconds) == (5, 900, 900)
    assert s.session_lifetime_seconds == 8 * 3600


class Clock:
    def __init__(self) -> None:
        self.now = datetime(2026, 11, 1, tzinfo=UTC)

    def __call__(self) -> datetime:
        return self.now


def test_five_failures_block_for_fifteen_minutes() -> None:
    clock = Clock()
    t = LoginThrottle(5, 900, 900, clock)
    for _ in range(4):
        t.record_failure("a")
        t.check("a")
    t.record_failure("a")
    with pytest.raises(Throttled):
        t.check("a")
    clock.now += timedelta(minutes=14)
    with pytest.raises(Throttled):
        t.check("a")
    clock.now += timedelta(minutes=2)
    t.check("a")


def test_failures_outside_window_do_not_count() -> None:
    clock = Clock()
    t = LoginThrottle(5, 900, 900, clock)
    for _ in range(4):
        t.record_failure("a")
    clock.now += timedelta(minutes=16)
    t.record_failure("a")
    t.check("a")


def test_success_resets_and_keys_are_independent() -> None:
    t = LoginThrottle(2, 900, 900, Clock())
    t.record_failure("a")
    t.record_success("a")
    t.record_failure("a")
    t.check("a")
    t.record_failure("b")
    t.record_failure("b")
    with pytest.raises(Throttled):
        t.check("b")
    t.check("a")
