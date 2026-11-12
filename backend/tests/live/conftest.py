"""Fixtures for the live tests: a real Vikunja, a user on it and a tefteri app wired to it.

These tests are not part of `just test`. Run them with `just backend::live-vikunja`, which
starts a throw-away Vikunja (see `scripts/vikunja-dev.sh`). To use another server, set
``TEFTERI_LIVE_VIKUNJA_URL`` and optionally ``TEFTERI_LIVE_VIKUNJA_TOKEN`` (a token of a user
on that server). Without a token, the tests register a new user, so the server must allow it.
Do not point them at a server with real data: they create users, projects and tasks.
"""

import contextlib
import os
import shutil
import socket
import subprocess
import sys
import time
import uuid
from collections.abc import AsyncIterator, Callable, Iterator
from pathlib import Path
from typing import Any

import httpx
import pytest
from httpx import ASGITransport, AsyncClient

from tefteri.adapters.vikunja import VikunjaTaskBackend
from tefteri.auth.passwords import hash_password
from tefteri.config import Settings
from tefteri.main import create_app
from tests.conftest import ADMIN_PASSWORD, V1

pytestmark = pytest.mark.live


@pytest.fixture(scope="session")
def vikunja_url() -> str:
    """Base URL of the Vikunja under test, without ``/api/v1``."""
    url = os.environ.get("TEFTERI_LIVE_VIKUNJA_URL", "").rstrip("/")
    if not url:
        pytest.skip("set TEFTERI_LIVE_VIKUNJA_URL, or run `just backend::live-vikunja`")
    return url


@pytest.fixture(scope="session")
def vikunja_token(vikunja_url: str) -> str:
    """A token for a user on that Vikunja (a new user unless a token is given)."""
    given = os.environ.get("TEFTERI_LIVE_VIKUNJA_TOKEN")
    if given:
        return given
    name = f"live-{uuid.uuid4().hex[:10]}"
    password = "live test password 1"
    with httpx.Client(base_url=f"{vikunja_url}/api/v1", timeout=20) as client:
        registered = client.post(
            "/register",
            json={"username": name, "email": f"{name}@example.com", "password": password},
        )
        assert registered.status_code == 200, f"cannot register a user: {registered.text}"
        login = client.post("/login", json={"username": name, "password": password})
        assert login.status_code == 200, login.text
        return str(login.json()["token"])


@pytest.fixture(scope="session")
def vikunja_info(vikunja_url: str) -> dict[str, Any]:
    """What the server says about itself (version and limits)."""
    info: dict[str, Any] = httpx.get(f"{vikunja_url}/api/v1/info", timeout=20).json()
    return info


class RealVikunja:
    """Direct calls to Vikunja, the way another client (the Vikunja web app) writes to it."""

    def __init__(self, client: httpx.AsyncClient, url: str, token: str) -> None:
        self.client = client
        self.url = url
        self.base = f"{url}/api/v1"
        self.headers = {"Authorization": f"Bearer {token}"}

    async def inbox(self) -> str:
        """Id of the first real project of the user."""
        projects = (await self.client.get(f"{self.base}/projects", headers=self.headers)).json()
        return str(next(p["id"] for p in projects if int(p["id"]) > 0))

    async def create(self, title: str, **fields: Any) -> dict[str, Any]:
        """Create a task in the first project, as the Vikunja web app does."""
        r = await self.client.put(
            f"{self.base}/projects/{await self.inbox()}/tasks",
            headers=self.headers,
            json={"title": title, **fields},
        )
        assert r.status_code == 201, r.text
        task: dict[str, Any] = r.json()
        return task

    async def get(self, task_id: object) -> dict[str, Any]:
        """The task as Vikunja stores it now."""
        r = await self.client.get(f"{self.base}/tasks/{task_id}", headers=self.headers)
        assert r.status_code == 200, r.text
        task: dict[str, Any] = r.json()
        return task

    async def update(self, task_id: object, **fields: Any) -> dict[str, Any]:
        """Change a task like the Vikunja web app: read it, change fields, write it all back."""
        task = await self.get(task_id)
        task.update(fields)
        r = await self.client.post(f"{self.base}/tasks/{task_id}", headers=self.headers, json=task)
        assert r.status_code == 200, r.text
        updated: dict[str, Any] = r.json()
        return updated


@pytest.fixture
async def real(vikunja_url: str, vikunja_token: str) -> AsyncIterator[RealVikunja]:
    async with httpx.AsyncClient(timeout=30) as client:
        yield RealVikunja(client, vikunja_url, vikunja_token)


@pytest.fixture
async def adapter(
    vikunja_url: str, vikunja_token: str
) -> AsyncIterator[Callable[[str], VikunjaTaskBackend]]:
    """Builds the real Vikunja adapter for a time zone."""
    async with httpx.AsyncClient(timeout=30) as client:

        def build(timezone: str = "UTC") -> VikunjaTaskBackend:
            return VikunjaTaskBackend(client, vikunja_url, vikunja_token, timezone)

        yield build


@pytest.fixture
async def tefteri(
    vikunja_url: str, vikunja_token: str, make_settings: Callable[..., Settings]
) -> AsyncIterator[AsyncClient]:
    """A tefteri app, signed in as its administrator, with a connection to the live Vikunja.

    Each test gets a new app with an empty database, so tests cannot see each other's rows.
    Set the time zone of the tefteri user with ``await tefteri.patch(...)`` if a test needs it.
    """
    app = create_app(make_settings())
    async with (
        app.router.lifespan_context(app),
        AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as api,
    ):
        login = await api.post(
            f"{V1}/auth/login", json={"username": "admin", "password": ADMIN_PASSWORD}
        )
        api.headers["Authorization"] = f"Bearer {login.json()['token']}"
        made = await api.post(
            f"{V1}/connections",
            json={
                "provider": "vikunja",
                "display_name": "Live Vikunja",
                "settings": {"base_url": vikunja_url},
                "credentials": {"token": vikunja_token},
            },
        )
        assert made.status_code == 201, made.text
        yield api


@pytest.fixture
def monthly_http_server_url() -> Iterator[str]:
    """Run the migrated app on a temporary local database and a free TCP port."""
    backend_dir = Path(__file__).resolve().parents[2]
    data_dir = backend_dir / ".live-test-data" / f"monthly-{uuid.uuid4().hex}"
    data_dir.mkdir(parents=True)
    env = {
        **os.environ,
        "TEFTERI_DATABASE_URL": f"sqlite+aiosqlite:///{data_dir / 'monthly-live.db'}",
        "TEFTERI_CREATE_SCHEMA": "false",
        "TEFTERI_ADMIN_PASSWORD_HASH": hash_password(ADMIN_PASSWORD),
        "TEFTERI_SECRET_KEY": "monthly-live-secret-key-012345",
        "TEFTERI_SYNC_INTERVAL_MINUTES": "0",
    }
    try:
        migrated = subprocess.run(
            [sys.executable, "-m", "alembic", "upgrade", "head"],
            cwd=backend_dir,
            env=env,
            capture_output=True,
            check=False,
            text=True,
        )
        assert migrated.returncode == 0, migrated.stdout + migrated.stderr

        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            port = int(probe.getsockname()[1])
        log_path = data_dir / "monthly-uvicorn.log"
        with log_path.open("w") as log:
            proc = subprocess.Popen(  # noqa: S603 - fixed arguments
                [
                    sys.executable,
                    "-m",
                    "uvicorn",
                    "tefteri.main:create_app",
                    "--factory",
                    "--host",
                    "127.0.0.1",
                    "--port",
                    str(port),
                ],
                cwd=backend_dir,
                env=env,
                stdout=log,
                stderr=subprocess.STDOUT,
            )
            base_url = f"http://127.0.0.1:{port}"
            try:
                for _ in range(100):
                    try:
                        if httpx.get(f"{base_url}/health", timeout=1).status_code == 200:
                            break
                    except httpx.HTTPError:
                        time.sleep(0.2)
                else:
                    pytest.fail(f"the server did not start: {log_path.read_text()}")
                yield base_url
            finally:
                proc.terminate()
                proc.wait(timeout=15)
    finally:
        shutil.rmtree(data_dir, ignore_errors=True)
        with contextlib.suppress(OSError):
            data_dir.parent.rmdir()


@pytest.fixture
async def monthly_http_server(
    monthly_http_server_url: str, vikunja_url: str, vikunja_token: str
) -> AsyncIterator[AsyncClient]:
    """Connect the live Vikunja to the migrated server and return an authenticated client."""
    async with AsyncClient(base_url=f"{monthly_http_server_url}{V1}", timeout=60) as api:
        login = await api.post(
            "/auth/login", json={"username": "admin", "password": ADMIN_PASSWORD}
        )
        assert login.status_code == 200, login.text
        api.headers["Authorization"] = f"Bearer {login.json()['token']}"
        connected = await api.post(
            "/connections",
            json={
                "provider": "vikunja",
                "display_name": "Live Vikunja",
                "settings": {"base_url": vikunja_url},
                "credentials": {"token": vikunja_token},
            },
        )
        assert connected.status_code == 201, connected.text
        yield api
