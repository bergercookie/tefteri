"""Smoke test for the server image: start it, then check health, version, web client and sign-in.

Set ``TEFTERI_SMOKE_IMAGE`` (``just deploy::smoke`` does) to run it; without it the test
is skipped. Needs Docker.
"""

import subprocess
import uuid
from collections.abc import Iterator

import httpx
import pytest

from tefteri.auth.passwords import hash_password
from tests.smoke.conftest import IMAGE, PASSWORD, docker, needs_image, wait_for_health

pytestmark = needs_image


@pytest.fixture(scope="module")
def server() -> Iterator[str]:
    """Run the image on a free port and return its base URL."""
    name = f"tefteri-smoke-{uuid.uuid4().hex[:8]}"
    docker(
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
        port = docker("port", name, "8000/tcp").splitlines()[0].rsplit(":", 1)[1]
        url = f"http://127.0.0.1:{port}"
        wait_for_health(url, lambda: docker("logs", name))
        yield url
    finally:
        subprocess.run(["docker", "rm", "-f", name], check=False, capture_output=True)


def test_health_and_version(server: str) -> None:
    assert httpx.get(f"{server}/health").json() == {"status": "ok"}
    assert httpx.get(f"{server}/version").json()["version"] not in ("", "unknown")


def test_serves_the_web_client(server: str) -> None:
    index = httpx.get(f"{server}/")
    assert index.status_code == 200 and "flutter_bootstrap.js" in index.text
    assert httpx.get(f"{server}/flutter_bootstrap.js").status_code == 200


def test_admin_signs_in_on_the_migrated_database(server: str) -> None:
    r = httpx.post(f"{server}/api/v1/auth/login", json={"username": "admin", "password": PASSWORD})
    assert r.status_code == 200, r.text
    headers = {"Authorization": f"Bearer {r.json()['token']}"}
    me = httpx.get(f"{server}/api/v1/auth/me", headers=headers)
    assert me.json()["is_admin"] is True
    # Tables from the newest migrations exist.
    review = httpx.get(f"{server}/api/v1/annual-review/2026", headers=headers)
    assert review.status_code == 200


def test_wrong_password_is_refused(server: str) -> None:
    r = httpx.post(f"{server}/api/v1/auth/login", json={"username": "admin", "password": "x"})
    assert r.status_code == 401
