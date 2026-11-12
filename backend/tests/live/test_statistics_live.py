"""The real tefteri server against a real Vikunja: work categories and statistics (spec 005).

Not part of `just test`. Run with `just backend::live-vikunja` (see ``conftest.py``).

The server runs as a separate uvicorn process on a free port, with a file database made by the
real migrations. Every request goes over a real socket with ``httpx``, so a response that fails
its schema (a ``Literal`` that missed a new value crashed the real API once, and the unit tests
had not caught it) shows up here as a failed request.

The reason ``no_project`` cannot be made with a real Vikunja (a task always has a project), so
the e2e tests cover it. All other reasons are made here.
"""

import os
import socket
import subprocess
import sys
import time
import uuid
from collections.abc import Iterator
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

import httpx
import pytest

from tefteri.auth.passwords import hash_password
from tests.conftest import ADMIN_PASSWORD, V1
from tests.live.conftest import RealVikunja

pytestmark = pytest.mark.live

CATEGORIES = ("goal_aligned", "maintenance", "off_plan", "hidden")
REASONS = {
    "committed_milestone",
    "maintenance_label",
    "inside_routine",
    "milestone_not_committed",
    "theme",
    "unclassified",
    "ignored",
    "ignored_ancestor",
}


@pytest.fixture
def server(tmp_path: Path) -> Iterator[str]:
    """Start the real app with uvicorn on a free port and a file database; stop it after."""
    env = {
        **os.environ,
        "TEFTERI_DATABASE_URL": f"sqlite+aiosqlite:///{tmp_path / 'live.db'}",
        "TEFTERI_CREATE_SCHEMA": "true",
        "TEFTERI_ADMIN_PASSWORD_HASH": hash_password(ADMIN_PASSWORD),
        "TEFTERI_SECRET_KEY": "live-secret-key-0123456789",
        "TEFTERI_SYNC_INTERVAL_MINUTES": "0",
    }
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        free_tcp_port = int(probe.getsockname()[1])
    log = (tmp_path / "uvicorn.log").open("w")
    proc = subprocess.Popen(  # noqa: S603 - fixed arguments
        [
            sys.executable,
            "-m",
            "uvicorn",
            "tefteri.main:create_app",
            "--factory",
            "--port",
            str(free_tcp_port),
        ],
        env=env,
        stdout=log,
        stderr=subprocess.STDOUT,
    )
    url = f"http://127.0.0.1:{free_tcp_port}"
    try:
        for _ in range(100):
            try:
                if httpx.get(f"{url}/health", timeout=1).status_code == 200:
                    break
            except httpx.HTTPError:
                time.sleep(0.2)
        else:
            pytest.fail(f"the server did not start: {(tmp_path / 'uvicorn.log').read_text()}")
        yield url
    finally:
        proc.terminate()
        proc.wait(timeout=15)
        log.close()


async def test_the_real_server_counts_every_category_and_keeps_them_stable(
    server: str, real: RealVikunja, vikunja_url: str, vikunja_token: str
) -> None:
    tag = uuid.uuid4().hex[:6]

    async def make_project(title: str, parent: int | None = None) -> int:
        body: dict[str, Any] = {"title": f"{title} {tag}"}
        if parent:
            body["parent_project_id"] = parent
        r = await real.client.put(f"{real.base}/projects", headers=real.headers, json=body)
        assert r.status_code == 201, r.text
        return int(r.json()["id"])

    async def make_task(pid: int, title: str) -> int:
        r = await real.client.put(
            f"{real.base}/projects/{pid}/tasks", headers=real.headers, json={"title": title}
        )
        assert r.status_code == 201, r.text
        return int(r.json()["id"])

    async def finish(task_id: int) -> None:
        await real.update(task_id, done=True)

    theme = await make_project("Theme")
    mile = await make_project("Milestone", theme)
    mile2 = await make_project("Milestone two", theme)
    routine = await make_project("Routine")
    kid = await make_project("Routine kid", routine)
    ignored = await make_project("Ignored")
    ignored_kid = await make_project("Ignored kid", ignored)
    plain = await make_project("Unlabelled")
    names = {
        mile: ["goal a", "goal b", "goal c"],
        mile2: ["not committed"],
        routine: ["routine a", "routine b"],
        kid: ["inside routine"],
        ignored: ["ignored a"],
        ignored_kid: ["ignored kid"],
        plain: ["unsorted a"],
        theme: ["theme task"],
    }
    task_ids = {
        n: await make_task(project_id, f"{n} {tag}") for project_id, ns in names.items() for n in ns
    }

    async with httpx.AsyncClient(base_url=f"{server}{V1}", timeout=60) as api:
        login = await api.post(
            "/auth/login", json={"username": "admin", "password": ADMIN_PASSWORD}
        )
        assert login.status_code == 200, login.text
        api.headers["Authorization"] = f"Bearer {login.json()['token']}"
        made = await api.post(
            "/connections",
            json={
                "provider": "vikunja",
                "display_name": "Live Vikunja",
                "settings": {"base_url": vikunja_url},
                "credentials": {"token": vikunja_token},
            },
        )
        assert made.status_code == 201, made.text

        async def sync() -> None:
            results = (await api.post("/sync")).json()
            assert all(r["outcome"] == "ok" for r in results), results

        tree = (await api.get("/projects/classification")).json()
        label_id = {p["name"]: p["id"] for c in tree["connections"] for p in c["projects"]}
        labels = {
            f"Theme {tag}": "theme",
            f"Milestone {tag}": "milestone",
            f"Milestone two {tag}": "milestone",
            f"Routine {tag}": "maintenance",
            f"Ignored {tag}": "ignored",
        }
        saved = await api.put(
            "/projects/labels",
            json={"changes": [{"id": label_id[n], "label": label} for n, label in labels.items()]},
        )
        assert saved.status_code == 200, saved.text

        today = datetime.now(UTC).date()
        monday = today - timedelta(days=today.weekday())
        candidates = {
            c["name"]: c["container_id"]
            for c in (await api.get(f"/weekly/{monday}/candidates")).json()
        }
        added = await api.post(
            f"/weekly/{monday}/projects", json={"container_id": candidates[f"Milestone {tag}"]}
        )
        assert added.status_code == 201, added.text
        assert (await api.post(f"/weekly/{monday}/spread")).status_code == 200
        assert (await api.post(f"/weekly/{monday}/commit")).status_code == 200

        async def stats(period: str) -> dict[str, Any]:
            r = await api.get("/statistics", params={"period": period, "day": str(today)})
            assert r.status_code == 200, r.text
            body: dict[str, Any] = r.json()
            return body

        async def listing(period: str, category: str, order: str) -> list[dict[str, Any]]:
            items: list[dict[str, Any]] = []
            cursor = None
            while True:
                params: dict[str, Any] = {
                    "period": period,
                    "day": str(today),
                    "category": category,
                    "order": order,
                    "limit": 3,
                }
                if cursor:
                    params["cursor"] = cursor
                r = await api.get("/statistics/tasks", params=params)
                assert r.status_code == 200, r.text
                body = r.json()
                items += body["items"]
                assert body["total"] >= len(items)
                cursor = body["next_cursor"]
                if not cursor:
                    assert body["total"] == len(items)
                    return items

        await sync()
        before = {p: await stats(p) for p in ("week", "month", "year")}

        # Three tasks are completed in the task app, the rest in tefteri (recorded at once).
        in_app = ["goal a", "goal b", "routine a", "inside routine", "ignored a", "ignored kid"]
        in_app += ["unsorted a", "theme task", "not committed"]
        for n in in_app:
            await finish(task_ids[n])
        await sync()
        mine = {t["title"]: t for t in (await api.get("/tasks", params={"due": "all"})).json()}
        for n in ("goal c", "routine b"):
            r = await api.post(f"/tasks/{mine[f'{n} {tag}']['id']}/complete")
            assert r.status_code == 200, r.text

        expected = {"goal_aligned": 3, "maintenance": 3, "off_plan": 3}
        for period in ("week", "month", "year"):
            s = await stats(period)
            assert s["available"] is True and s["sync"]["outcome"] == "ok"
            assert set(s["counts"]) == set(expected)
            for key, count in expected.items():
                assert s["counts"][key] - before[period]["counts"][key] == count, (period, key)
            assert s["hidden"] - before[period]["hidden"] == 2
            assert s["unsorted"] - before[period]["unsorted"] == 1
            assert s["total"] == sum(s["counts"].values())
            assert sum(s["percentages"].values()) == 100
            for key in expected:
                assert sum(p["counts"][key] for p in s["parts"]) == s["counts"][key], (period, key)
            assert sum(p["hidden"] for p in s["parts"]) == s["hidden"]
            assert s["total"] + s["hidden"] == (
                before[period]["total"] + before[period]["hidden"] + 11
            )
            for category in CATEGORIES:
                want = s["hidden"] if category == "hidden" else s["counts"][category]
                for order in ("newest", "project"):
                    items = await listing(period, category, order)
                    assert len(items) == want, (period, category, order)
                    assert {i["category"] for i in items} == ({category} if want else set())

        # Every reason except no_project came through the real routes without a schema error.
        decided: dict[str, tuple[str, str, str | None]] = {}
        for category in CATEGORIES:
            for item in await listing("week", category, "newest"):
                if item["title"].endswith(tag):
                    decided[item["title"].removesuffix(f" {tag}")] = (
                        item["category"],
                        item["reason"],
                        item["project"]["name"],
                    )
        assert len(decided) == 11, decided
        assert {r for _, r, _ in decided.values()} == REASONS
        assert decided["goal c"][:2] == ("goal_aligned", "committed_milestone")
        progress = (await stats("week"))["progress"]
        assert progress is not None and progress["committed"] >= 3

        # A relabel, a rename and a move change nothing that is stored.
        relabelled = await api.put(
            "/projects/labels",
            json={
                "changes": [
                    {"id": label_id[f"Milestone {tag}"], "label": "ignored"},
                    {"id": label_id[f"Routine {tag}"], "label": "theme"},
                ]
            },
        )
        assert relabelled.status_code == 200, relabelled.text
        project = (
            await real.client.get(f"{real.base}/projects/{mile}", headers=real.headers)
        ).json()
        project["title"] = f"Renamed {tag}"
        renamed = await real.client.post(
            f"{real.base}/projects/{mile}", headers=real.headers, json=project
        )
        assert renamed.status_code == 200, renamed.text
        await real.update(task_ids["goal a"], project_id=plain)
        await sync()
        after: dict[str, tuple[str, str, str | None]] = {}
        for category in CATEGORIES:
            for item in await listing("week", category, "newest"):
                if item["title"].endswith(tag):
                    after[item["title"].removesuffix(f" {tag}")] = (
                        item["category"],
                        item["reason"],
                        item["project"]["name"],
                    )
        assert after == decided
