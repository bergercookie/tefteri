"""Move a planned task, then sync: the new due date must stay (real adapter, stateful fake)."""

from collections.abc import AsyncIterator
from datetime import UTC, datetime

import httpx
import pytest
import respx
from httpx import ASGITransport, AsyncClient

from tefteri.adapters.vikunja import VikunjaTaskBackend
from tefteri.domain.enums import ConnectionKind
from tefteri.main import create_app
from tefteri.services.connections import AdapterRegistry
from tests.conftest import ADMIN_PASSWORD, V1
from tests.fakes.http.vikunja import FakeVikunja


@pytest.fixture
async def stack(make_settings) -> AsyncIterator[tuple[AsyncClient, FakeVikunja]]:  # type: ignore[no-untyped-def]
    with respx.mock(assert_all_called=False) as router:
        server = FakeVikunja()
        server.mount(router)
        async with httpx.AsyncClient() as http:
            registry = AdapterRegistry()
            registry.register(
                "vikunja",
                ConnectionKind.TASKS,
                lambda s, c: VikunjaTaskBackend(
                    http, s["base_url"], c["token"], s.get("timezone", "UTC")
                ),
            )
            app = create_app(make_settings(), registry=registry)
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
                        "display_name": "Home tasks",
                        "default_context": "life",
                        "settings": {"base_url": server.base_url},
                        "credentials": {"token": server.token},
                    },
                )
                assert made.status_code == 201, made.text
                yield api, server


def _due(server: FakeVikunja, title: str) -> datetime | None:
    task = next(t for t in server.tasks.values() if t["title"] == title)
    value = task["due_date"]
    return value if value is None else value.astimezone(UTC)


async def test_a_moved_task_keeps_its_new_due_date_after_sync(
    stack: tuple[AsyncClient, FakeVikunja],
) -> None:
    api, server = stack
    await api.post(f"{V1}/sync")
    conn = (await api.get(f"{V1}/connections")).json()[0]["id"]
    created = await api.post(
        f"{V1}/tasks",
        json={
            "connection_id": conn,
            "title": "Write report",
            "due_at": "2026-11-04T09:00:00+00:00",
        },
    )
    assert created.status_code == 201, created.text
    task_id = created.json()["id"]
    assert _due(server, "Write report") == datetime(2026, 11, 4, 9, tzinfo=UTC)
    await api.post(f"{V1}/sync")

    first = await api.put(
        f"{V1}/tasks/{task_id}/schedule", json={"start": "2026-11-04T13:00:00+00:00"}
    )
    assert first.status_code == 200, first.text
    assert _due(server, "Write report") == datetime(2026, 11, 4, 14, tzinfo=UTC)

    second = await api.put(
        f"{V1}/tasks/{task_id}/schedule", json={"start": "2026-11-05T10:00:00+00:00"}
    )
    assert second.status_code == 200, second.text
    assert _due(server, "Write report") == datetime(2026, 11, 5, 11, tzinfo=UTC)

    synced = await api.post(f"{V1}/sync")
    assert all(r["outcome"] == "ok" for r in synced.json()), synced.text
    after = (await api.get(f"{V1}/tasks/{task_id}")).json()
    assert after["due_at"].startswith("2026-11-05T11:00:00"), after["due_at"]
    assert _due(server, "Write report") == datetime(2026, 11, 5, 11, tzinfo=UTC)


async def test_when_vikunja_keeps_the_old_date_the_user_sees_an_error_at_once(
    stack: tuple[AsyncClient, FakeVikunja], monkeypatch: pytest.MonkeyPatch
) -> None:
    api, server = stack
    await api.post(f"{V1}/sync")
    conn = (await api.get(f"{V1}/connections")).json()[0]["id"]
    created = await api.post(
        f"{V1}/tasks",
        json={
            "connection_id": conn,
            "title": "Write report",
            "due_at": "2026-11-04T09:00:00+00:00",
        },
    )
    task_id = created.json()["id"]
    await api.post(f"{V1}/sync")

    original = server._write  # noqa: SLF001 - make the fake ignore a changed due date

    def keep_due(task: dict, body: dict) -> None:  # type: ignore[type-arg]
        due = task["due_date"]
        original(task, body)
        task["due_date"] = due

    monkeypatch.setattr(server, "_write", keep_due)
    moved = await api.put(
        f"{V1}/tasks/{task_id}/schedule", json={"start": "2026-11-05T10:00:00+00:00"}
    )
    assert moved.status_code == 502
    assert moved.json()["code"] == "not_saved" and "Home tasks" in moved.json()["detail"]
    assert "did not keep the change" in moved.json()["detail"]
    # nothing in tefteri claims the new time, and a sync agrees with Vikunja
    assert (
        (await api.get(f"{V1}/tasks/{task_id}")).json()["due_at"].startswith("2026-11-04T09:00:00")
    )
    await api.post(f"{V1}/sync")
    assert (
        (await api.get(f"{V1}/tasks/{task_id}")).json()["due_at"].startswith("2026-11-04T09:00:00")
    )
