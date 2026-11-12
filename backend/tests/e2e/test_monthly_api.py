"""The monthly planning and review contract over HTTP (spec 007, M4)."""

from datetime import date

import pytest
from httpx import AsyncClient

from tefteri.domain.entities import Container
from tefteri.domain.enums import ProjectLabel
from tests.conftest import V1
from tests.fakes.world import FakeWorld
from tests.integration.conftest import ProjectsEnv
from tests.integration.monthly_helpers import label, setup_month
from tests.integration.monthly_review_helpers import (
    MONTH as REVIEW_MONTH,
)
from tests.integration.monthly_review_helpers import (
    add_key_result,
    setup_review,
)


@pytest.fixture
def env(api: AsyncClient, world: FakeWorld) -> ProjectsEnv:
    return ProjectsEnv(api, world)


async def test_monthly_planning_routes_and_focus_validation(env: ProjectsEnv) -> None:
    rows = await setup_month(
        env,
        Container("t1", "Alpha"),
        Container("t2", "Beta"),
        Container("t3", "Gamma"),
        Container("m1", "Milestone"),
        Container("a1", "Maintenance"),
    )
    await label(env, "Milestone", ProjectLabel.MILESTONE)
    await label(env, "Maintenance", ProjectLabel.MAINTENANCE)

    month = "2030-03"
    plan_response = await env.api.get(f"{V1}/monthly/{month}")
    assert plan_response.status_code == 200, plan_response.text
    plan = plan_response.json()
    assert (plan["month"], plan["start"], plan["end"], plan["state"]) == (
        month,
        "2030-03-01",
        "2030-04-01",
        "current",
    )
    assert plan["focus_known"] is False and plan["entries"] == []
    assert plan["review"] == {"stored": False, "current_version": None, "versions": 0}

    themes_response = await env.api.get(f"{V1}/monthly/{month}/themes")
    assert themes_response.status_code == 200, themes_response.text
    themes = themes_response.json()
    assert [item["name"] for item in themes["themes"]] == ["Alpha", "Beta", "Gamma"]
    assert themes["unsorted_count"] >= 1
    assert themes["task_connections"][0]["id"] == env.connection_id
    assert all(
        set(item)
        == {
            "project_id",
            "connection_id",
            "connection_name",
            "name",
            "in_focus",
            "left_this_month",
            "last_month_done",
            "key_result_ids",
        }
        for item in themes["themes"]
    )
    filtered = await env.api.get(
        f"{V1}/monthly/{month}/themes",
        params={"q": "Beta", "connection_id": env.connection_id},
    )
    assert [item["name"] for item in filtered.json()["themes"]] == ["Beta"]

    suggestions_response = await env.api.get(f"{V1}/monthly/{month}/suggestions")
    assert suggestions_response.status_code == 200, suggestions_response.text
    assert suggestions_response.json() == {
        "from_month": None,
        "suggestions": [],
        "skipped": [],
    }

    first_two = [
        {"project_id": str(rows[name].id), "target": target}
        for name, target in (("Alpha", 2), ("Beta", 0))
    ]
    dry_run = await env.api.put(
        f"{V1}/monthly/{month}/focus", json={"entries": first_two, "dry_run": True}
    )
    assert dry_run.status_code == 200, dry_run.text
    assert set(dry_run.json()) == {"effect", "count_note"}
    assert dry_run.json()["count_note"] == "below"
    assert (await env.api.get(f"{V1}/monthly/{month}")).json()["focus_known"] is False

    saved = await env.api.put(f"{V1}/monthly/{month}/focus", json={"entries": first_two})
    assert saved.status_code == 200, saved.text
    focus = saved.json()["focus"]
    assert saved.json()["count_note"] == "below"
    assert focus["focus_known"] is True
    assert {item["name"]: item["target"] for item in focus["entries"]} == {
        "Alpha": 2,
        "Beta": 0,
    }

    invalid_target = await env.api.put(
        f"{V1}/monthly/{month}/focus",
        json={"entries": [{"project_id": str(rows["Alpha"].id), "target": True}]},
    )
    assert invalid_target.status_code == 422
    assert invalid_target.json()["code"] == "invalid_target"

    duplicate = await env.api.put(
        f"{V1}/monthly/2030-04/focus",
        json={
            "entries": [
                {"project_id": str(rows["Alpha"].id), "target": None},
                {"project_id": str(rows["Alpha"].id), "target": None},
            ]
        },
    )
    assert duplicate.status_code == 422 and duplicate.json()["code"] == "duplicate_theme"

    not_a_theme = await env.api.put(
        f"{V1}/monthly/2030-04/focus",
        json={"entries": [{"project_id": str(rows["Maintenance"].id), "target": None}]},
    )
    assert not_a_theme.status_code == 422 and not_a_theme.json()["code"] == "not_a_theme"

    past_month = await env.api.put(
        f"{V1}/monthly/2030-02/focus",
        json={"entries": [{"project_id": str(rows["Alpha"].id), "target": None}]},
    )
    assert past_month.status_code == 409 and past_month.json()["code"] == "past_month"

    membership_change = await env.api.put(
        f"{V1}/monthly/{month}/focus",
        json={
            "entries": [
                {"project_id": str(rows["Alpha"].id), "target": 2},
                {"project_id": str(rows["Gamma"].id), "target": 0},
            ]
        },
    )
    assert membership_change.status_code == 409
    assert membership_change.json()["code"] == "use_changes"


async def test_monthly_change_routes_dry_run_history_and_undo(env: ProjectsEnv) -> None:
    rows = await setup_month(env, *(Container(f"t{i}", f"Theme {i}") for i in range(4)))
    month = "2030-03"
    initial = await env.api.put(
        f"{V1}/monthly/{month}/focus",
        json={
            "entries": [
                {"project_id": str(rows["Theme 0"].id), "target": 1},
                {"project_id": str(rows["Theme 1"].id), "target": None},
            ]
        },
    )
    assert initial.status_code == 200, initial.text

    previews = (
        {
            "kind": "swap",
            "out_project_id": str(rows["Theme 0"].id),
            "in_project_id": str(rows["Theme 3"].id),
            "target": 2,
        },
        {"kind": "add", "in_project_id": str(rows["Theme 2"].id), "target": 0},
        {"kind": "remove", "out_project_id": str(rows["Theme 0"].id)},
        {"kind": "target", "out_project_id": str(rows["Theme 0"].id), "target": 4},
    )
    for payload in previews:
        response = await env.api.post(
            f"{V1}/monthly/{month}/changes", json={**payload, "dry_run": True}
        )
        assert response.status_code == 200, response.text
        assert set(response.json()) == {"effect"}

    changed = await env.api.post(
        f"{V1}/monthly/{month}/changes",
        json={
            "kind": "swap",
            "out_project_id": str(rows["Theme 0"].id),
            "in_project_id": str(rows["Theme 3"].id),
            "target": 2,
        },
    )
    assert changed.status_code == 200, changed.text
    swap_batch = changed.json()["batch_id"]

    added = await env.api.post(
        f"{V1}/monthly/{month}/changes",
        json={"kind": "add", "in_project_id": str(rows["Theme 2"].id), "target": 0},
    )
    assert added.status_code == 200, added.text
    assert added.json()["effect"]["counts_from"] == "2030-03-15"

    target_change = await env.api.post(
        f"{V1}/monthly/{month}/changes",
        json={"kind": "target", "out_project_id": str(rows["Theme 3"].id), "target": 4},
    )
    assert target_change.status_code == 200, target_change.text
    removed = await env.api.post(
        f"{V1}/monthly/{month}/changes",
        json={"kind": "remove", "out_project_id": str(rows["Theme 1"].id)},
    )
    assert removed.status_code == 200, removed.text
    remove_batch = removed.json()["batch_id"]

    already_in_focus = await env.api.post(
        f"{V1}/monthly/{month}/changes",
        json={"kind": "add", "in_project_id": str(rows["Theme 3"].id)},
    )
    assert already_in_focus.status_code == 409
    assert already_in_focus.json()["code"] == "already_in_focus"
    left_this_month = await env.api.post(
        f"{V1}/monthly/{month}/changes",
        json={"kind": "add", "in_project_id": str(rows["Theme 1"].id)},
    )
    assert left_this_month.status_code == 409
    assert left_this_month.json()["code"] == "left_this_month"
    not_current_month = await env.api.post(
        f"{V1}/monthly/2030-04/changes",
        json={"kind": "add", "in_project_id": str(rows["Theme 1"].id)},
    )
    assert not_current_month.status_code == 409
    assert not_current_month.json()["code"] == "not_current_month"

    first_target = await env.api.post(
        f"{V1}/monthly/{month}/changes",
        json={"kind": "target", "out_project_id": str(rows["Theme 3"].id), "target": 5},
    )
    second_target = await env.api.post(
        f"{V1}/monthly/{month}/changes",
        json={"kind": "target", "out_project_id": str(rows["Theme 3"].id), "target": 6},
    )
    assert first_target.status_code == second_target.status_code == 200
    not_undoable = await env.api.post(
        f"{V1}/monthly/{month}/changes/undo",
        json={"batch_id": first_target.json()["batch_id"]},
    )
    assert not_undoable.status_code == 409
    assert not_undoable.json()["code"] == "not_undoable"

    undone = await env.api.post(
        f"{V1}/monthly/{month}/changes/undo", json={"batch_id": remove_batch}
    )
    assert undone.status_code == 200, undone.text
    assert undone.json()["undone"] == "remove"
    already_undone = await env.api.post(
        f"{V1}/monthly/{month}/changes/undo", json={"batch_id": remove_batch}
    )
    assert already_undone.status_code == 409
    assert already_undone.json()["code"] == "already_undone"

    history = await env.api.get(f"{V1}/monthly/{month}/history")
    assert history.status_code == 200, history.text
    body = history.json()
    assert body["month"] == month
    assert {change["kind"] for change in body["changes"]} == {
        "swap",
        "add",
        "target",
        "remove",
    }
    assert any(change["batch_id"] == swap_batch for change in body["changes"])
    assert any(change["source"] == "undo" for change in body["changes"])
    assert all(
        set(change)
        == {
            "batch_id",
            "kind",
            "on",
            "out_name",
            "in_name",
            "target_before",
            "target_after",
            "source",
            "undone",
            "can_undo",
        }
        for change in body["changes"]
    )


async def test_monthly_review_routes_versions_current_and_snapshots(env: ProjectsEnv) -> None:
    rows = await setup_review(env, "Carry", "Later")
    key_result = await add_key_result(
        env,
        rows,
        metric="Monthly value",
        themes=("Carry",),
        values=((REVIEW_MONTH, 12),),
    )
    month = REVIEW_MONTH.strftime("%Y-%m")

    draft = await env.api.get(f"{V1}/monthly/{month}/review")
    assert draft.status_code == 200, draft.text
    draft_body = draft.json()
    assert draft_body["month"] == month
    assert draft_body["stored"] is False and draft_body["draft"] is True
    assert draft_body["version"] is None and draft_body["taken_at"] is None
    assert {item["decision"] for item in draft_body["snapshot"]["decisions"]} == {"later"}

    preview = await env.api.post(
        f"{V1}/monthly/{month}/review",
        json={
            "key_result_values": [{"key_result_id": str(key_result.id), "value": 20}],
            "decisions": [{"project_id": str(rows["Carry"].id), "decision": "carry"}],
            "dry_run": True,
        },
    )
    assert preview.status_code == 200, preview.text
    assert preview.json()["will_create_version"] == 1
    key_result_preview = next(
        item
        for item in preview.json()["snapshot"]["key_results"]
        if item["key_result_id"] == str(key_result.id)
    )
    assert key_result_preview["latest_value"] == 20
    assert preview.json()["effects"]

    stored = await env.api.post(
        f"{V1}/monthly/{month}/review",
        json={
            "key_result_values": [{"key_result_id": str(key_result.id), "value": 20}],
            "decisions": [{"project_id": str(rows["Carry"].id), "decision": "carry"}],
        },
    )
    assert stored.status_code == 201, stored.text
    assert stored.json()["version"] == 1
    assert len(stored.json()["values_written"]) == 1

    current_review = await env.api.get(f"{V1}/monthly/{month}/review")
    assert current_review.status_code == 200, current_review.text
    assert current_review.json()["stored"] is True
    assert current_review.json()["draft"] is False
    assert current_review.json()["current_version"] == 1
    explicit_version = await env.api.get(f"{V1}/monthly/{month}/review", params={"version": 1})
    assert explicit_version.status_code == 200
    assert explicit_version.json()["version"] == 1

    confirm_required = await env.api.post(
        f"{V1}/monthly/{month}/review",
        json={"decisions": [{"project_id": str(rows["Carry"].id), "decision": "drop"}]},
    )
    assert confirm_required.status_code == 422
    assert confirm_required.json()["code"] == "confirm_required"

    second = await env.api.post(
        f"{V1}/monthly/{month}/review",
        json={
            "decisions": [{"project_id": str(rows["Carry"].id), "decision": "drop"}],
            "confirm_new_version": True,
        },
    )
    assert second.status_code == 201, second.text
    assert second.json()["version"] == 2
    version_one_current = await env.api.post(
        f"{V1}/monthly/{month}/review/current", json={"version": 1, "dry_run": True}
    )
    assert version_one_current.status_code == 200
    assert "Version 1 becomes the current version." in version_one_current.json()["message"]
    selected = await env.api.post(f"{V1}/monthly/{month}/review/current", json={"version": 1})
    assert selected.status_code == 200, selected.text
    assert selected.json()["current_version"] == 1
    assert [item["current"] for item in selected.json()["versions"]] == [True, False]

    snapshots = await env.api.get(f"{V1}/monthly/snapshots", params={"year": REVIEW_MONTH.year})
    assert snapshots.status_code == 200, snapshots.text
    assert snapshots.json()["year"] == REVIEW_MONTH.year
    assert len(snapshots.json()["snapshots"]) == 1
    assert snapshots.json()["snapshots"][0]["month"] == month
    assert snapshots.json()["snapshots"][0]["version"] == 1

    month_index = REVIEW_MONTH.year * 12 + REVIEW_MONTH.month - 1 + 2
    future_year, future_month_index = divmod(month_index, 12)
    future_month = date(future_year, future_month_index + 1, 1)
    future = await env.api.get(f"{V1}/monthly/{future_month:%Y-%m}/review")
    assert future.status_code == 409
    assert future.json()["code"] == "future_month"

    retired = await add_key_result(
        env,
        rows,
        metric="Retired value",
        themes=("Carry",),
        status="retired",
    )
    retired_value = await env.api.post(
        f"{V1}/monthly/{month}/review",
        json={
            "key_result_values": [{"key_result_id": str(retired.id), "value": 10}],
            "confirm_new_version": True,
        },
    )
    assert retired_value.status_code == 409
    assert retired_value.json()["code"] == "retired"

    no_such_version = await env.api.post(
        f"{V1}/monthly/{month}/review/current", json={"version": 99, "dry_run": True}
    )
    assert no_such_version.status_code == 404
    assert no_such_version.json()["code"] == "no_such_version"
