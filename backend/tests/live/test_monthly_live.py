"""Monthly planning and immutable reviews against a real, throw-away Vikunja."""

import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from httpx import AsyncClient

from tests.conftest import V1
from tests.live.conftest import RealVikunja

pytestmark = pytest.mark.live


async def test_live_monthly_cycle_keeps_stored_results_unchanged(
    tefteri: AsyncClient, real: RealVikunja
) -> None:
    tag = uuid.uuid4().hex[:8]

    async def make_project(title: str, parent: int | None = None) -> int:
        body: dict[str, Any] = {"title": f"{title} {tag}"}
        if parent is not None:
            body["parent_project_id"] = parent
        response = await real.client.put(f"{real.base}/projects", headers=real.headers, json=body)
        assert response.status_code == 201, response.text
        return int(response.json()["id"])

    async def make_task(project_id: int, title: str) -> int:
        response = await real.client.put(
            f"{real.base}/projects/{project_id}/tasks",
            headers=real.headers,
            json={"title": f"{title} {tag}"},
        )
        assert response.status_code == 201, response.text
        return int(response.json()["id"])

    alpha = await make_project("Monthly theme Alpha")
    beta = await make_project("Monthly theme Beta")
    orphan = await make_project("Monthly theme to delete")
    milestone_ids = [
        await make_project("Alpha milestone one", alpha),
        await make_project("Alpha milestone two", alpha),
        await make_project("Beta milestone", beta),
    ]
    task_ids = [
        await make_task(milestone_ids[0], "Ship Alpha one"),
        await make_task(milestone_ids[1], "Ship Alpha two"),
        await make_task(milestone_ids[2], "Ship Beta"),
    ]

    async def sync() -> None:
        response = await tefteri.post(f"{V1}/sync")
        assert response.status_code == 200, response.text
        outcomes = response.json()
        assert outcomes and all(item["outcome"] == "ok" for item in outcomes), outcomes

    await sync()
    tree = (await tefteri.get(f"{V1}/projects/classification")).json()
    ids_by_name = {
        project["name"]: project["id"]
        for connection in tree["connections"]
        for project in connection["projects"]
    }
    labels = {
        f"Monthly theme Alpha {tag}": "theme",
        f"Monthly theme Beta {tag}": "theme",
        f"Monthly theme to delete {tag}": "theme",
        f"Alpha milestone one {tag}": "milestone",
        f"Alpha milestone two {tag}": "milestone",
        f"Beta milestone {tag}": "milestone",
    }
    labeled = await tefteri.put(
        f"{V1}/projects/labels",
        json={
            "changes": [{"id": ids_by_name[name], "label": label} for name, label in labels.items()]
        },
    )
    assert labeled.status_code == 200, labeled.text

    today = datetime.now(UTC).date()
    monday = today - timedelta(days=today.weekday())
    candidates_response = await tefteri.get(f"{V1}/weekly/{monday}/candidates")
    assert candidates_response.status_code == 200, candidates_response.text
    candidates = {row["name"]: row["container_id"] for row in candidates_response.json()}
    for name in (
        f"Alpha milestone one {tag}",
        f"Alpha milestone two {tag}",
        f"Beta milestone {tag}",
    ):
        added = await tefteri.post(
            f"{V1}/weekly/{monday}/projects", json={"container_id": candidates[name]}
        )
        assert added.status_code == 201, added.text
    assert (await tefteri.post(f"{V1}/weekly/{monday}/spread")).status_code == 200
    assert (await tefteri.post(f"{V1}/weekly/{monday}/commit")).status_code == 200

    month = today.strftime("%Y-%m")
    focus = await tefteri.put(
        f"{V1}/monthly/{month}/focus",
        json={
            "entries": [
                {"project_id": ids_by_name[f"Monthly theme Alpha {tag}"], "target": 2},
                {"project_id": ids_by_name[f"Monthly theme Beta {tag}"], "target": 0},
                {"project_id": ids_by_name[f"Monthly theme to delete {tag}"], "target": 1},
            ]
        },
    )
    assert focus.status_code == 200, focus.text

    for task_id in task_ids:
        await real.update(task_id, done=True)
    await sync()

    alpha_project = (
        await real.client.get(f"{real.base}/projects/{alpha}", headers=real.headers)
    ).json()
    alpha_project["title"] = f"Monthly theme Alpha renamed {tag}"
    renamed = await real.client.post(
        f"{real.base}/projects/{alpha}", headers=real.headers, json=alpha_project
    )
    assert renamed.status_code == 200, renamed.text
    deleted = await real.client.delete(f"{real.base}/projects/{orphan}", headers=real.headers)
    assert deleted.status_code == 200, deleted.text
    await sync()

    stored = await tefteri.post(f"{V1}/monthly/{month}/review", json={})
    assert stored.status_code == 201, stored.text
    snapshot = stored.json()["snapshot"]
    themes = {theme["project_id"]: theme for theme in snapshot["themes"]}
    assert themes[ids_by_name[f"Monthly theme Alpha {tag}"]]["done"] == 2
    assert themes[ids_by_name[f"Monthly theme Beta {tag}"]]["done"] == 1
    assert themes[ids_by_name[f"Monthly theme to delete {tag}"]]["done"] == 0
    assert themes[ids_by_name[f"Monthly theme Alpha {tag}"]]["name"] == (
        f"Monthly theme Alpha renamed {tag}"
    )
    assert themes[ids_by_name[f"Monthly theme Alpha {tag}"]]["marker"] == "met"
    assert themes[ids_by_name[f"Monthly theme Beta {tag}"]]["marker"] == "beaten"
    assert themes[ids_by_name[f"Monthly theme to delete {tag}"]]["marker"] == "missed"
    assert themes[ids_by_name[f"Monthly theme to delete {tag}"]]["orphaned"]["reason"] == "missing"

    renamed_again = await real.client.get(f"{real.base}/projects/{alpha}", headers=real.headers)
    renamed_body = renamed_again.json()
    renamed_body["title"] = f"After review rename {tag}"
    update_after_store = await real.client.post(
        f"{real.base}/projects/{alpha}", headers=real.headers, json=renamed_body
    )
    assert update_after_store.status_code == 200, update_after_store.text
    delete_after_store = await real.client.delete(
        f"{real.base}/projects/{milestone_ids[0]}", headers=real.headers
    )
    assert delete_after_store.status_code == 200, delete_after_store.text
    await sync()

    reopened = await tefteri.get(f"{V1}/monthly/{month}/review")
    assert reopened.status_code == 200, reopened.text
    assert reopened.json()["stored"] is True
    assert reopened.json()["snapshot"] == snapshot
