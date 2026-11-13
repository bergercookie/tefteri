"""Every monthly API route over TCP against the real server and Vikunja."""

import uuid
from datetime import date, datetime, timedelta
from typing import Any, TypeVar

import pytest
from httpx import AsyncClient, Response
from pydantic import BaseModel

from tefteri.api.routers.monthly import (
    FocusChangePreviewOut,
    FocusChangeResultOut,
    FocusHistoryOut,
    FocusSavePreviewOut,
    FocusSaveResultOut,
    FocusUndoOut,
    MakeCurrentPreviewOut,
    MonthlyPlanOut,
    MonthlyReviewOut,
    MonthlySnapshotOut,
    ReviewStorePreviewOut,
    ReviewStoreResultOut,
    SuggestionsOut,
    ThemePickerOut,
)
from tests.live.conftest import RealVikunja

pytestmark = pytest.mark.live
ModelT = TypeVar("ModelT", bound=BaseModel)


class SnapshotItemOut(BaseModel):
    month: str
    version: int
    taken_at: datetime
    snapshot: MonthlySnapshotOut


class SnapshotsOut(BaseModel):
    year: int
    snapshots: list[SnapshotItemOut]


async def test_every_monthly_route_over_tcp_parses_all_seeded_enums(
    monthly_http_server: AsyncClient, real: RealVikunja
) -> None:
    api = monthly_http_server
    tag = uuid.uuid4().hex[:8]
    today = date.today()
    month = today.strftime("%Y-%m")
    next_month = date(today.year + (today.month == 12), today.month % 12 + 1, 1)
    next_month_text = next_month.strftime("%Y-%m")
    previous_month = date(
        today.year - (today.month == 1), 12 if today.month == 1 else today.month - 1, 1
    )
    year = today.year

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

    names = ("Theme A", "Theme B", "Theme C", "Theme D", "Theme E", "Theme F", "Theme G")
    remote_themes = {name: await make_project(name) for name in names}
    remote_milestones = {
        "Milestone A": await make_project("Milestone A", remote_themes["Theme A"]),
        "Milestone B": await make_project("Milestone B", remote_themes["Theme B"]),
    }
    task_ids = {
        "Milestone A": await make_task(remote_milestones["Milestone A"], "Finish A"),
        "Milestone B": await make_task(remote_milestones["Milestone B"], "Finish B"),
    }

    async def sync() -> None:
        response = await api.post("/sync")
        assert response.status_code == 200, response.text
        outcomes = response.json()
        assert outcomes and all(item["outcome"] == "ok" for item in outcomes), outcomes

    await sync()
    classification = (await api.get("/projects/classification")).json()
    project_ids = {
        project["name"]: project["id"]
        for connection in classification["connections"]
        for project in connection["projects"]
    }
    labels = [{"id": project_ids[f"{name} {tag}"], "label": "theme"} for name in names] + [
        {"id": project_ids[f"{name} {tag}"], "label": "milestone"} for name in remote_milestones
    ]
    labeled = await api.put("/projects/labels", json={"changes": labels})
    assert labeled.status_code == 200, labeled.text

    monday = today - timedelta(days=today.weekday())
    weekly_candidates = (await api.get(f"/weekly/{monday}/candidates")).json()
    candidates = {row["name"]: row["container_id"] for row in weekly_candidates}
    for name in remote_milestones:
        added_week = await api.post(
            f"/weekly/{monday}/projects",
            json={"container_id": candidates[f"{name} {tag}"]},
        )
        assert added_week.status_code == 201, added_week.text
    assert (await api.post(f"/weekly/{monday}/spread")).status_code == 200
    assert (await api.post(f"/weekly/{monday}/commit")).status_code == 200
    for task_id in task_ids.values():
        await real.update(task_id, done=True)
    await sync()

    a, b, c, d, e, f, g = (project_ids[f"{name} {tag}"] for name in names)

    async def parsed(
        response: Response, model: type[ModelT], statuses: tuple[int, ...] = (200,)
    ) -> ModelT:
        assert response.status_code in statuses, response.text
        return model.model_validate(response.json())

    plan = await parsed(await api.get(f"/monthly/{month}"), MonthlyPlanOut)
    assert plan.focus_known is False
    past_plan = await parsed(await api.get(f"/monthly/{previous_month:%Y-%m}"), MonthlyPlanOut)
    future_plan = await parsed(await api.get(f"/monthly/{next_month_text}"), MonthlyPlanOut)
    assert {past_plan.state.value, plan.state.value, future_plan.state.value} == {
        "past",
        "current",
        "future",
    }
    picker = await parsed(await api.get(f"/monthly/{month}/themes"), ThemePickerOut)
    assert {str(theme.project_id) for theme in picker.themes} >= {str(a), str(b), str(c), str(d)}
    await parsed(
        await api.get(
            f"/monthly/{month}/themes",
            params={"q": "Theme A", "connection_id": str(picker.themes[0].connection_id)},
        ),
        ThemePickerOut,
    )
    await parsed(await api.get(f"/monthly/{month}/suggestions"), SuggestionsOut)

    # Exercise all count-note variants without changing the saved current-month focus.
    for entries, note in (
        ([], "empty"),
        ([{"project_id": a, "target": None}], "below"),
        ([{"project_id": project_ids[f"{name} {tag}"], "target": None} for name in names], "above"),
    ):
        focus_preview = await parsed(
            await api.put(
                f"/monthly/{next_month_text}/focus",
                json={"entries": entries, "dry_run": True},
            ),
            FocusSavePreviewOut,
        )
        assert focus_preview.count_note == note

    initial = await parsed(
        await api.put(
            f"/monthly/{month}/focus",
            json={
                "entries": [
                    {"project_id": a, "target": 0},
                    {"project_id": b, "target": 0},
                    {"project_id": c, "target": 1},
                    {"project_id": d, "target": None},
                ]
            },
        ),
        FocusSaveResultOut,
    )
    assert initial.focus.focus_known

    # Seed manual key results in both update states, and link them to live focus themes.
    goals = await api.post(
        f"/annual/{year}/goals/bulk",
        json={
            "goals": [
                {
                    "title": f"Updated goal {tag}",
                    "key_results": [
                        {
                            "metric": f"Updated metric {tag}",
                            "start_value": 0,
                            "target": 10,
                            "deadline": f"{year}-12-31",
                            "theme_ids": [str(a)],
                        }
                    ],
                },
                {
                    "title": f"Not updated goal {tag}",
                    "key_results": [
                        {
                            "metric": f"Not updated metric {tag}",
                            "start_value": 0,
                            "target": 10,
                            "deadline": f"{year}-12-31",
                            "theme_ids": [str(b)],
                        }
                    ],
                },
            ]
        },
    )
    assert goals.status_code == 201, goals.text
    updated_id = goals.json()["goals"][0]["key_results"][0]["id"]
    written = await api.post(f"/annual/key-results/{updated_id}/values", json={"value": 2})
    assert written.status_code == 201, written.text

    target_preview = await parsed(
        await api.post(
            f"/monthly/{month}/changes",
            json={"kind": "target", "out_project_id": a, "target": 1, "dry_run": True},
        ),
        FocusChangePreviewOut,
    )
    assert target_preview.effect.message
    target_change = await parsed(
        await api.post(
            f"/monthly/{month}/changes",
            json={"kind": "target", "out_project_id": a, "target": 1},
        ),
        FocusChangeResultOut,
    )
    swapped = await parsed(
        await api.post(
            f"/monthly/{month}/changes",
            json={"kind": "swap", "out_project_id": d, "in_project_id": e, "target": 1},
        ),
        FocusChangeResultOut,
    )
    added_change = await parsed(
        await api.post(
            f"/monthly/{month}/changes",
            json={"kind": "add", "in_project_id": f, "target": None},
        ),
        FocusChangeResultOut,
    )
    removed = await parsed(
        await api.post(
            f"/monthly/{month}/changes",
            json={"kind": "remove", "out_project_id": c},
        ),
        FocusChangeResultOut,
    )
    assert target_change.batch_id != swapped.batch_id != added_change.batch_id != removed.batch_id

    temporary = project_ids[f"Theme G {tag}"]
    undoable = await parsed(
        await api.post(
            f"/monthly/{month}/changes",
            json={"kind": "add", "in_project_id": temporary, "target": None},
        ),
        FocusChangeResultOut,
    )
    await parsed(
        await api.post(
            f"/monthly/{month}/changes/undo",
            json={"batch_id": str(undoable.batch_id)},
        ),
        FocusUndoOut,
    )

    # Preserve the old focus entries while making one orphaned and another relabelled.
    project_c = remote_themes["Theme C"]
    deleted = await real.client.delete(f"{real.base}/projects/{project_c}", headers=real.headers)
    assert deleted.status_code == 200, deleted.text
    relabelled = await api.put(
        "/projects/labels", json={"changes": [{"id": d, "label": "maintenance"}]}
    )
    assert relabelled.status_code == 200, relabelled.text
    await sync()

    history = await parsed(await api.get(f"/monthly/{month}/history"), FocusHistoryOut)
    assert {item.kind.value for item in history.changes} >= {"swap", "add", "remove", "target"}
    assert any(item.source.value == "undo" for item in history.changes)

    draft = await parsed(await api.get(f"/monthly/{month}/review"), MonthlyReviewOut)
    assert draft.draft and not draft.stored
    review_preview = await parsed(
        await api.post(
            f"/monthly/{month}/review",
            json={
                "decisions": [
                    {"project_id": a, "decision": "carry"},
                    {"project_id": b, "decision": "drop"},
                    {"project_id": d, "decision": "replace", "replacement_project_id": g},
                    {"project_id": e, "decision": "later"},
                ],
                "dry_run": True,
            },
        ),
        ReviewStorePreviewOut,
    )
    assert review_preview.will_create_version == 1
    stored = await parsed(
        await api.post(
            f"/monthly/{month}/review",
            json={
                "decisions": [
                    {"project_id": a, "decision": "carry"},
                    {"project_id": b, "decision": "drop"},
                    {"project_id": d, "decision": "replace", "replacement_project_id": g},
                    {"project_id": e, "decision": "later"},
                ]
            },
        ),
        ReviewStoreResultOut,
        (201,),
    )
    assert {decision.decision.value for decision in stored.snapshot.decisions} >= {
        "carry",
        "drop",
        "replace",
        "later",
    }
    theme_rows = {str(item.project_id): item for item in stored.snapshot.themes}
    assert {item.status.value for item in theme_rows.values()} >= {
        "in_focus",
        "swapped_out",
        "removed",
    }
    assert {item.marker.value for item in theme_rows.values()} >= {
        "met",
        "missed",
        "beaten",
        "no_target",
    }
    assert {item.status.value for item in stored.snapshot.key_results} >= {
        "updated",
        "not_updated",
    }
    assert theme_rows[str(c)].orphaned is not None
    assert theme_rows[str(d)].label_changed == "maintenance"

    await parsed(
        await api.get(f"/monthly/{month}/review", params={"version": 1}),
        MonthlyReviewOut,
    )
    await parsed(
        await api.post(
            f"/monthly/{month}/review/current",
            json={"version": 1, "dry_run": True},
        ),
        MakeCurrentPreviewOut,
    )
    await parsed(
        await api.post(f"/monthly/{month}/review/current", json={"version": 1}),
        MonthlyReviewOut,
    )
    await parsed(
        await api.get(f"/monthly/{next_month_text}/suggestions"),
        SuggestionsOut,
    )
    snapshots = await parsed(
        await api.get("/monthly/snapshots", params={"year": year}), SnapshotsOut
    )
    assert snapshots.year == year
    assert any(item.month == month for item in snapshots.snapshots)
