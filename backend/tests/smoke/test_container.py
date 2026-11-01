"""Smoke test for the server image: start it, then check health, version and sign-in.

Set ``TEFTERI_SMOKE_IMAGE`` (``just deploy::smoke`` does) to run it; without it the test
is skipped. Needs Docker.
"""

import os
import shutil
import subprocess
import time
import uuid
from collections.abc import Iterator

import httpx
import pytest

from tefteri.auth.passwords import hash_password

IMAGE = os.environ.get("TEFTERI_SMOKE_IMAGE")
PASSWORD = "smoke test password"

pytestmark = pytest.mark.skipif(
    not IMAGE or shutil.which("docker") is None, reason="TEFTERI_SMOKE_IMAGE or docker missing"
)


def _docker(*args: str) -> str:
    return subprocess.run(
        ["docker", *args], check=True, capture_output=True, text=True
    ).stdout.strip()


@pytest.fixture(scope="module")
def server() -> Iterator[str]:
    """Run the image on a free port and return its base URL."""
    name = f"tefteri-smoke-{uuid.uuid4().hex[:8]}"
    _docker(
        "run",
        "-d",
        "--name",
        name,
        "-p",
        "127.0.0.1::8000",
        "-e",
        "TEFTERI_ADMIN_USERNAME=admin",
        "-e",
        f"TEFTERI_ADMIN_PASSWORD_HASH={hash_password(PASSWORD)}",
        "-e",
        "TEFTERI_SECRET_KEY=smoke-test-secret-key",
        str(IMAGE),
    )
    try:
        port = _docker("port", name, "8000/tcp").splitlines()[0].rsplit(":", 1)[1]
        url = f"http://127.0.0.1:{port}"
        deadline = time.monotonic() + 60
        while True:
            try:
                if httpx.get(f"{url}/health", timeout=2).status_code == 200:
                    break
            except httpx.TransportError:
                pass
            if time.monotonic() > deadline:
                raise AssertionError("server did not start:\n" + _docker("logs", name))
            time.sleep(0.5)
        yield url
    finally:
        subprocess.run(["docker", "rm", "-f", name], check=False, capture_output=True)


def test_health_and_version(server: str) -> None:
    assert httpx.get(f"{server}/health").json() == {"status": "ok"}
    assert httpx.get(f"{server}/version").json()["version"] not in ("", "unknown")


def test_admin_signs_in_on_the_migrated_database(server: str) -> None:
    r = httpx.post(f"{server}/api/v1/auth/login", json={"username": "admin", "password": PASSWORD})
    assert r.status_code == 200, r.text
    headers = {"Authorization": f"Bearer {r.json()['token']}"}
    me = httpx.get(f"{server}/api/v1/auth/me", headers=headers)
    assert me.json()["is_admin"] is True
    # Tables from the newest migration exist.
    plans = httpx.get(f"{server}/api/v1/reviews/history", headers=headers)
    assert plans.status_code == 200 and plans.json() == []


def test_wrong_password_is_refused(server: str) -> None:
    r = httpx.post(f"{server}/api/v1/auth/login", json={"username": "admin", "password": "x"})
    assert r.status_code == 401
