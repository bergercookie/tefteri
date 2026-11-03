"""Shared helpers for the smoke tests against the server image."""

import os
import shutil
import subprocess
import time
from collections.abc import Callable

import httpx
import pytest

IMAGE = os.environ.get("TEFTERI_SMOKE_IMAGE")
PASSWORD = "smoke test password"

needs_image = pytest.mark.skipif(
    not IMAGE or shutil.which("docker") is None, reason="TEFTERI_SMOKE_IMAGE or docker missing"
)


def docker(*args: str) -> str:
    return subprocess.run(
        ["docker", *args], check=True, capture_output=True, text=True
    ).stdout.strip()


def wait_for_health(url: str, logs: Callable[[], str], timeout: float = 60) -> None:
    """Poll ``/health`` until it answers; fail with the server logs after ``timeout`` seconds."""
    deadline = time.monotonic() + timeout
    while True:
        try:
            if httpx.get(f"{url}/health", timeout=2).status_code == 200:
                return
        except httpx.TransportError:
            pass
        if time.monotonic() > deadline:
            raise AssertionError("server did not start:\n" + logs())
        time.sleep(0.5)
