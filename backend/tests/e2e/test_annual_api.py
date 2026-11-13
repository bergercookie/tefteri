"""The annual planning contract over HTTP (spec 006, M5)."""

from collections.abc import Awaitable, Callable
from datetime import timedelta
from typing import Any

import pytest
from httpx import AsyncClient

from tests.conftest import V1
from tests.fakes.world import FakeWorld
from tests.integration.annual_helpers import (
    NOW,
    YEAR,
    bare_client,
    connect_themes,
    create_goal,
    create_goals,
    enter_value,
    freeze,
    key_result_of,
    kr,
    plan,
)
from tests.integration.conftest import ProjectsEnv

MakeUser = Callable[..., Awaitable[AsyncClient]]

PLAN_KEYS = {"year", "state", "editable", "goals", "retired_goals", "theme_usage"}
GOAL_KEYS = {
    "id",
    "title",
    "status",
    "legacy_done",
    "criteria_suggestion",
    "progress",
    "flags",
    "notes",
    "updated_at",
    "key_results",
}
KEY_RESULT_KEYS = {
    "id",
    "goal_id",
    "metric",
    "start_value",
    "target",
    "deadline",
    "update_source",
    "status",
    "current_value",
    "current_at",
    "progress",
    "met",
    "retired_at",
    "flags",
    "links",
}
LINK_KEYS = {
    "id",
    "project_id",
    "name",
    "active",
    "usable",
    "state",
    "label",
    "started_at",
    "ended_at",
}
CHANGE_KEYS = {
    "id",
    "at",
    "kind",
    "year",
    "goal_id",
    "key_result_id",
    "link_id",
    "field",
    "old_value",
    "new_value",
    "reason",
    "batch_id",
    "source",
    "undone",
}
EFFECT_KEYS = {"key_results_retired", "links_ended", "flags_removed", "history_kept"}


@pytest.fixture
def env(api: AsyncClient, world: FakeWorld) -> ProjectsEnv:
    return ProjectsEnv(api, world)


async def test_the_read_routes_have_the_contract_shape(env: ProjectsEnv) -> None:
    freeze(env.api)
    themes = await connect_themes(env, "Open source", "Talks")
    goal = await create_goal(
        env.api,
        "Get better at open source",
        kr("Stars", start=100, target=500, themes=[themes["Open source"]]),
    )
    key_result = goal["key_results"][0]
    await enter_value(env.api, key_result["id"], 220, "2030-06-30")

    answer = await plan(env.api)
    assert set(answer) == PLAN_KEYS
    assert (answer["year"], answer["state"], answer["editable"]) == (YEAR, "current", True)
    assert list(answer) == ["year", "state", "editable", "goals", "retired_goals", "theme_usage"]
    assert set(answer["goals"][0]) == GOAL_KEYS
    assert set(answer["goals"][0]["key_results"][0]) == KEY_RESULT_KEYS
    assert set(answer["goals"][0]["key_results"][0]["links"][0]) == LINK_KEYS
    assert answer["goals"][0]["key_results"][0]["current_value"] == 220
    assert answer["goals"][0]["key_results"][0]["links"][0]["name"] == "Open source"

    history = (await env.api.get(f"{V1}/annual/{YEAR}/history")).json()
    assert set(history) == {"year", "changes"}
    assert history["year"] == YEAR
    assert history["changes"]
    assert set(history["changes"][0]) == CHANGE_KEYS

    themes_answer = (await env.api.get(f"{V1}/annual/themes")).json()
    assert set(themes_answer) == {"themes", "unsorted_count", "task_connections"}
    assert {theme["name"] for theme in themes_answer["themes"]} == {"Open source", "Talks"}
    assert set(themes_answer["themes"][0]) == {
        "project_id",
        "name",
        "connection_id",
        "key_result_ids",
        "connection_name",
    }
    assert set(themes_answer["task_connections"][0]) == {"id", "name", "can_create"}

    series = (await env.api.get(f"{V1}/annual/key-results/{key_result['id']}/values")).json()
    assert set(series[0]) == {"id", "value", "at", "on_date", "source", "seq"}
    assert (series[0]["value"], series[0]["on_date"], series[0]["source"]) == (
        220.0,
        "2030-06-30",
        "manual",
    )
    value_on = (
        await env.api.get(
            f"{V1}/annual/key-results/{key_result['id']}/value-on",
            params={"date": "2030-06-30"},
        )
    ).json()
    assert set(value_on) == {"key_result_id", "date", "value", "at", "source"}
    assert value_on["value"] == 220
    empty_on = (
        await env.api.get(
            f"{V1}/annual/key-results/{key_result['id']}/value-on",
            params={"date": "2030-01-01"},
        )
    ).json()
    assert empty_on["value"] is None and empty_on["at"] is None

    suggestions = (
        await env.api.get(f"{V1}/annual/{YEAR + 1}/suggestions", params={"from_year": YEAR})
    ).json()
    assert set(suggestions) == {"year", "from_year", "has_plan", "goals"}
    assert suggestions["has_plan"] is True
    assert set(suggestions["goals"][0]) == {"goal_id", "title", "key_results"}
    assert set(suggestions["goals"][0]["key_results"][0]) == {
        "key_result_id",
        "metric",
        "start_value",
        "target",
        "deadline",
        "update_source",
        "themes",
    }

    assert (await env.api.get(f"{V1}/annual/push-token")).json() == {"exists": False}


async def test_the_write_routes_round_trip_and_record_history(env: ProjectsEnv) -> None:
    freeze(env.api)
    themes = await connect_themes(env, "Open source", "Talks")
    goal = await create_goal(env.api, "First", kr("Stars", themes=[themes["Open source"]]))
    key_result = goal["key_results"][0]

    edited = await env.api.patch(f"{V1}/annual/goals/{goal['id']}", json={"title": "Better first"})
    assert edited.status_code == 200, edited.text
    assert set(edited.json()) == GOAL_KEYS
    assert edited.json()["title"] == "Better first"

    added = await env.api.post(
        f"{V1}/annual/goals/{goal['id']}/key-results", json=kr("Talks", target=2)
    )
    assert added.status_code == 201, added.text
    assert set(added.json()) == KEY_RESULT_KEYS

    edited_kr = await env.api.patch(
        f"{V1}/annual/key-results/{key_result['id']}",
        json={"metric": "Stars on one repository", "target": 600},
    )
    assert edited_kr.status_code == 200, edited_kr.text
    assert set(edited_kr.json()) == KEY_RESULT_KEYS
    assert edited_kr.json()["metric"] == "Stars on one repository"
    assert edited_kr.json()["target"] == 600

    dry_links = await env.api.put(
        f"{V1}/annual/key-results/{key_result['id']}/themes",
        json={"theme_ids": [themes["Talks"]], "dry_run": True},
    )
    assert dry_links.status_code == 200, dry_links.text
    assert set(dry_links.json()) == {"effect"}
    assert set(dry_links.json()["effect"]) == {
        "added",
        "ended",
        "flags_removed",
        "flags_added",
    }
    assert [entry["name"] for entry in dry_links.json()["effect"]["added"]] == ["Talks"]
    assert [entry["name"] for entry in dry_links.json()["effect"]["ended"]] == ["Open source"]

    linked = await env.api.put(
        f"{V1}/annual/key-results/{key_result['id']}/themes",
        json={"theme_ids": [themes["Talks"]]},
    )
    assert linked.status_code == 200, linked.text
    assert set(linked.json()) == {"batch_id", "key_result"}
    active = [link["name"] for link in linked.json()["key_result"]["links"] if link["active"]]
    assert active == ["Talks"]
    assert {link["name"] for link in linked.json()["key_result"]["links"]} == {
        "Open source",
        "Talks",
    }
    link_batch = linked.json()["batch_id"]

    undone = await env.api.post(f"{V1}/annual/undo", json={"batch_id": link_batch})
    assert undone.status_code == 200, undone.text
    assert set(undone.json()) == {"restored"}
    assert undone.json()["restored"] >= 1
    again = await env.api.post(f"{V1}/annual/undo", json={"batch_id": link_batch})
    assert (again.status_code, again.json()["code"]) == (409, "already_undone")

    dry_retire = await env.api.post(
        f"{V1}/annual/key-results/{key_result['id']}/retire", json={"dry_run": True}
    )
    assert dry_retire.status_code == 200, dry_retire.text
    assert set(dry_retire.json()) == {"effect"}
    assert set(dry_retire.json()["effect"]) == EFFECT_KEYS
    assert dry_retire.json()["effect"]["key_results_retired"] == 1
    assert dry_retire.json()["effect"]["links_ended"] == 1

    retired = await env.api.post(
        f"{V1}/annual/key-results/{key_result['id']}/retire", json={"reason": "done"}
    )
    assert retired.status_code == 200, retired.text
    assert set(retired.json()) == {"batch_id", "effect"}
    retired_plan = await plan(env.api)
    retired_kr = key_result_of(retired_plan, key_result["id"])
    assert retired_kr["status"] == "retired"
    assert retired_kr["retired_at"] is not None

    restored = await env.api.post(f"{V1}/annual/key-results/{key_result['id']}/restore")
    assert restored.status_code == 200, restored.text
    assert set(restored.json()) == {"restored", "links_restored", "links_skipped"}
    assert restored.json()["restored"] == 1

    dry_goal = await env.api.post(f"{V1}/annual/goals/{goal['id']}/retire", json={"dry_run": True})
    assert dry_goal.status_code == 200, dry_goal.text
    assert set(dry_goal.json()) == {"effect"}
    assert set(dry_goal.json()["effect"]) == EFFECT_KEYS

    retired_goal = await env.api.post(f"{V1}/annual/goals/{goal['id']}/retire", json={})
    assert retired_goal.status_code == 200, retired_goal.text
    assert set(retired_goal.json()) == {"batch_id", "effect"}
    after = await plan(env.api)
    assert after["goals"] == []
    assert [g["id"] for g in after["retired_goals"]] == [goal["id"]]

    restored_goal = await env.api.post(f"{V1}/annual/goals/{goal['id']}/restore")
    assert restored_goal.status_code == 200, restored_goal.text
    assert set(restored_goal.json()) == {"restored", "links_restored", "links_skipped"}
    assert restored_goal.json()["restored"] >= 1
    assert (await plan(env.api))["goals"][0]["id"] == goal["id"]

    history = (await env.api.get(f"{V1}/annual/{YEAR}/history")).json()["changes"]
    assert {row["kind"] for row in history} >= {
        "goal_created",
        "goal_edited",
        "goal_retired",
        "goal_restored",
        "key_result_created",
        "key_result_edited",
        "key_result_retired",
        "key_result_restored",
        "link_added",
        "link_removed",
    }
    assert any(row["source"] == "undo" for row in history)
    assert any(row["undone"] for row in history)


async def test_the_write_routes_refuse_bad_input(env: ProjectsEnv) -> None:
    freeze(env.api)
    goal = await create_goal(
        env.api,
        "Goal",
        kr("One"),
        kr("Two"),
        kr("Three"),
    )

    limit = await env.api.post(f"{V1}/annual/goals/{goal['id']}/key-results", json=kr("Four"))
    assert (limit.status_code, limit.json()["code"]) == (409, "key_result_limit")
    assert limit.json()["detail"] == "A goal can have three key results. Retire one first."

    blank = await env.api.post(f"{V1}/annual/{YEAR}/goals/bulk", json={"goals": [{"title": " "}]})
    assert (blank.status_code, blank.json()["code"]) == (422, "invalid")
    assert (await plan(env.api))["goals"] == [goal]

    unknown = await env.api.patch(
        f"{V1}/annual/goals/00000000-0000-0000-0000-000000000001",
        json={"title": "Missing"},
    )
    assert (unknown.status_code, unknown.json()["code"]) == (404, "not_found")

    past = await env.api.post(
        f"{V1}/annual/{YEAR - 1}/goals/bulk", json={"goals": [{"title": "Old"}]}
    )
    assert (past.status_code, past.json()["code"]) == (409, "past_year")

    bad_source = await env.api.get(f"{V1}/annual/{YEAR}/suggestions", params={"from_year": YEAR})
    assert (bad_source.status_code, bad_source.json()["code"]) == (422, "invalid")

    same_target = await env.api.post(
        f"{V1}/annual/goals/{goal['id']}/key-results", json=kr("Same", start=5, target=5)
    )
    assert same_target.status_code == 422
    assert same_target.json()["code"] == "invalid"


async def test_themes_and_the_push_token_have_the_contract_shape(env: ProjectsEnv) -> None:
    freeze(env.api)
    await connect_themes(env, "Existing")
    connection = str(env.connection_uuid())

    created = await env.api.post(
        f"{V1}/annual/themes", json={"connection_id": connection, "name": "Created"}
    )
    assert created.status_code == 201, created.text
    assert set(created.json()) == {
        "project_id",
        "name",
        "connection_id",
        "key_result_ids",
        "connection_name",
    }
    assert created.json()["name"] == "Created"
    duplicate = await env.api.post(
        f"{V1}/annual/themes", json={"connection_id": connection, "name": " created "}
    )
    assert (duplicate.status_code, duplicate.json()["code"]) == (409, "theme_exists")
    assert duplicate.json()["existing"]["name"] == "Created"

    token = await env.api.post(f"{V1}/annual/push-token")
    assert token.status_code == 200, token.text
    assert set(token.json()) == {"token", "hint"}
    assert token.json()["token"].startswith("tfv_")
    assert len(token.json()["hint"]) == 4

    status = (await env.api.get(f"{V1}/annual/push-token")).json()
    assert set(status) == {"exists", "hint", "created_at", "last_used_at"}
    assert status["exists"] is True and status["hint"] == token.json()["hint"]
    assert status["last_used_at"] is None

    rotated = (await env.api.post(f"{V1}/annual/push-token")).json()
    assert rotated["token"] != token.json()["token"]

    assert (await env.api.delete(f"{V1}/annual/push-token")).status_code == 204
    assert (await env.api.get(f"{V1}/annual/push-token")).json() == {"exists": False}


async def test_another_user_gets_404_for_every_id(env: ProjectsEnv, make_user: MakeUser) -> None:
    freeze(env.api)
    themes = await connect_themes(env, "Open source")
    created = await create_goals(
        env.api,
        [
            {
                "title": "Secret",
                "key_results": [
                    kr("Secret", themes=[themes["Open source"]]),
                    kr("Automatic secret", source="automatic"),
                ],
            }
        ],
    )
    goal = created["goals"][0]
    key_result = goal["key_results"][0]
    automatic_id = goal["key_results"][1]["id"]
    await enter_value(env.api, key_result["id"], 3)
    sam = await make_user("sam")

    calls = [
        sam.patch(f"{V1}/annual/goals/{goal['id']}", json={"title": "hacked"}),
        sam.post(f"{V1}/annual/goals/{goal['id']}/key-results", json=kr("Hacked")),
        sam.post(f"{V1}/annual/goals/{goal['id']}/retire", json={}),
        sam.post(f"{V1}/annual/goals/{goal['id']}/restore"),
        sam.patch(f"{V1}/annual/key-results/{key_result['id']}", json={"metric": "hacked"}),
        sam.post(f"{V1}/annual/key-results/{key_result['id']}/retire", json={}),
        sam.post(f"{V1}/annual/key-results/{key_result['id']}/restore"),
        sam.put(f"{V1}/annual/key-results/{key_result['id']}/themes", json={"theme_ids": []}),
        sam.post(f"{V1}/annual/key-results/{key_result['id']}/values", json={"value": 9}),
        sam.get(f"{V1}/annual/key-results/{key_result['id']}/values"),
        sam.get(
            f"{V1}/annual/key-results/{key_result['id']}/value-on", params={"date": "2030-07-01"}
        ),
        sam.post(f"{V1}/annual/undo", json={"batch_id": created["batch_id"]}),
    ]
    for call in calls:
        response = await call
        assert (response.status_code, response.json()["code"]) == (404, "not_found")

    sam_plan = (await sam.get(f"{V1}/annual/{YEAR}")).json()
    assert (sam_plan["goals"], sam_plan["retired_goals"]) == ([], [])
    sam_theme = (await sam.get(f"{V1}/annual/themes")).json()
    assert sam_theme["themes"] == []
    assert (await sam.get(f"{V1}/annual/{YEAR}/history")).json()["changes"] == []
    assert (await sam.get(f"{V1}/annual/push-token")).json() == {"exists": False}

    sam_token = (await sam.post(f"{V1}/annual/push-token")).json()["token"]
    async with bare_client(env.api) as source:
        pushed = await source.post(
            f"{V1}/key-results/{automatic_id}/push",
            json={"value": 1, "at": NOW.isoformat()},
            headers={"Authorization": f"Bearer {sam_token}"},
        )
    assert (pushed.status_code, pushed.json()["code"]) == (404, "not_found")


async def _push(
    client: AsyncClient,
    key_result_id: str,
    token: str | None,
    body: dict[str, Any] | None = None,
) -> Any:
    headers = {"Authorization": f"Bearer {token}"} if token is not None else {}
    return await client.post(
        f"{V1}/key-results/{key_result_id}/push",
        json=body if body is not None else {"value": 1342, "at": NOW.isoformat()},
        headers=headers,
    )


async def test_the_push_status_table_row_by_row(env: ProjectsEnv) -> None:
    freeze(env.api)
    automatic = await create_goal(env.api, "Automatic", kr("Stars", target=500, source="automatic"))
    automatic_id = automatic["key_results"][0]["id"]
    manual = await create_goal(env.api, "Manual", kr("Talks"))
    manual_id = manual["key_results"][0]["id"]
    token = (await env.api.post(f"{V1}/annual/push-token")).json()["token"]
    session = env.api.headers["Authorization"].removeprefix("Bearer ")

    async with bare_client(env.api) as source:
        first = await _push(source, automatic_id, token)
        assert first.status_code == 201, first.text
        assert set(first.json()) == {"stored", "key_result_id", "value", "at", "current_value"}
        assert first.json()["stored"] is True
        assert first.json()["current_value"] == 1342
        assert "set-cookie" not in first.headers

        retry = await _push(source, automatic_id, token)
        assert retry.status_code == 200
        assert retry.json()["stored"] is False
        assert retry.json()["current_value"] == 1342

        assert (await _push(source, automatic_id, None)).status_code == 401
        assert (await _push(source, automatic_id, "tfv_wrong")).status_code == 401
        assert (await _push(source, automatic_id, session)).status_code == 401
        assert (await _push(source, manual_id, token)).json()["code"] == "not_automatic"
        assert (
            await _push(source, automatic_id, token, {"value": "1342", "at": NOW.isoformat()})
        ).json()["code"] == "invalid"
        assert (
            await _push(
                source,
                automatic_id,
                token,
                {"value": 1, "at": (NOW + timedelta(minutes=6)).isoformat()},
            )
        ).json()["code"] == "invalid"

        unknown = await _push(source, "00000000-0000-0000-0000-000000000001", token)
        assert (unknown.status_code, unknown.json()["code"]) == (404, "not_found")

        # The contract's curl example uses a fake token; it is refused and stores nothing.
        example = await source.post(
            f"{V1}/key-results/{automatic_id}/push",
            json={"value": 1342, "at": "2027-03-04T09:30:00Z"},
            headers={
                "Authorization": "Bearer tfv_FAKE_TOKEN_FOR_DOCS",
                "Content-Type": "application/json",
            },
        )
        assert (example.status_code, example.json()["code"]) == (401, "invalid_push_token")

    current = key_result_of(await plan(env.api), automatic_id)
    assert current["current_value"] == 1342
    series = (await env.api.get(f"{V1}/annual/key-results/{automatic_id}/values")).json()
    assert [(point["value"], point["source"]) for point in series] == [(1342.0, "automatic")]
    status = (await env.api.get(f"{V1}/annual/push-token")).json()
    assert status["last_used_at"] is not None
