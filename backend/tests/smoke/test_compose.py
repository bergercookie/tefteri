"""Smoke test for ``just deploy::up``: deploy/compose.yaml with a .env made from .env.example.

It runs the real compose file under its own project name, .env and port, so a running
deployment is not touched. Set ``TEFTERI_SMOKE_IMAGE`` (``just deploy::smoke`` does) to run it.
"""

import os
import shutil
import subprocess
import uuid
from collections.abc import Iterator
from pathlib import Path

import httpx
import pytest

from tefteri.auth.passwords import hash_password
from tests.smoke.conftest import IMAGE, PASSWORD, needs_image, wait_for_health

pytestmark = needs_image

DEPLOY = Path(__file__).resolve().parents[3] / "deploy"
# Publish on a free port instead of 8000; everything else comes from compose.yaml.
OVERRIDE = """\
services:
  tefteri:
    ports: !override
      - "127.0.0.1::8000"
"""


def _env_from_example() -> str:
    """Fill in only the values that deployment.md says you must set, inside their quotes."""
    values = {
        "TEFTERI_ADMIN_PASSWORD_HASH": hash_password(PASSWORD),
        "TEFTERI_SECRET_KEY": "smoke-test-secret-key",
    }
    lines = (DEPLOY / ".env.example").read_text().splitlines()
    for key, value in values.items():
        # The quotes stop compose from expanding the `$` signs in the Argon2 hash.
        assert f"{key}=''" in lines, f"{key}='' missing from .env.example"
        lines[lines.index(f"{key}=''")] = f"{key}='{value}'"
    return "\n".join(lines) + "\n"


@pytest.fixture(scope="module")
def server(tmp_path_factory: pytest.TempPathFactory) -> Iterator[str]:
    """Run `docker compose up -d` (as `just deploy::up` does) and return the base URL."""
    project = tmp_path_factory.mktemp("compose")
    shutil.copy(DEPLOY / "compose.yaml", project / "compose.yaml")
    (project / "compose.override.yaml").write_text(OVERRIDE)
    (project / ".env").write_text(_env_from_example())
    name = f"tefteri-smoke-{uuid.uuid4().hex[:8]}"
    # TEFTERI_IMAGE in the environment selects the image, like setting it in .env.
    environ = {**os.environ, "TEFTERI_IMAGE": str(IMAGE)}
    environ.pop("POSTGRES_PASSWORD", None)

    def compose(*args: str) -> str:
        files = ["-f", "compose.yaml", "-f", "compose.override.yaml"]
        return subprocess.run(
            ["docker", "compose", "-p", name, *files, *args],
            cwd=project,
            env=environ,
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

    try:
        try:
            compose("up", "-d")
        except subprocess.CalledProcessError as exc:
            raise AssertionError(f"docker compose up failed:\n{exc.stderr}") from exc
        port = compose("port", "tefteri", "8000").rsplit(":", 1)[1]
        url = f"http://127.0.0.1:{port}"
        wait_for_health(url, lambda: compose("logs"))
        yield url
    finally:
        subprocess.run(
            ["docker", "compose", "-p", name, "-f", "compose.yaml", "down", "-v"],
            cwd=project,
            env=environ,
            check=False,
            capture_output=True,
        )


def test_serves_api_and_web_client(server: str) -> None:
    assert httpx.get(f"{server}/health").json() == {"status": "ok"}
    assert "flutter_bootstrap.js" in httpx.get(f"{server}/").text


def test_admin_signs_in(server: str) -> None:
    r = httpx.post(f"{server}/api/v1/auth/login", json={"username": "admin", "password": PASSWORD})
    assert r.status_code == 200, r.text
