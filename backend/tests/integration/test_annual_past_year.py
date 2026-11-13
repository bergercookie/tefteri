"""Annual-plan write guards and planning-year state in the user's time zone."""

from datetime import UTC, datetime
from typing import Any, cast

import pytest
from httpx import AsyncClient, Response

from tefteri.domain.entities import Container
from tests.conftest import V1
from tests.integration.conftest import ProjectsEnv

YEAR = 2030
BEFORE_YEAR_END = datetime(2029, 6, 1, 12, tzinfo=UTC)
AFTER_YEAR_END = datetime(2031, 1, 1, 12, tzinfo=UTC)


def _freeze(api: AsyncClient, now: datetime) -> None:
    app = api.app  # type: ignore[attr-defined]
    app.state.annual_service._clock = lambda: now
    app.state.key_result_service._clock = lambda: now


async def _theme(env: ProjectsEnv) -> str:
    await env.connect(Container("p2", "Open source"))
    project_id = (await env.rows())["Open source"].id
    response = await env.api.put(
        f"{V1}/projects/labels",
        json={"changes": [{"id": str(project_id), "label": "theme"}]},
    )
    assert response.status_code == 200, response.text
    return str(project_id)


def _key_result(
    metric: str = "Measure",
    *,
    theme_id: str | None = None,
    year: int = YEAR,
) -> dict[str, Any]:
    return {
        "metric": metric,
        "start_value": 0,
        "target": 10,
        "deadline": f"{year}-12-31",
        "theme_ids": [theme_id] if theme_id else [],
    }


async def _create_goal(
    api: AsyncClient,
    *,
    year: int = YEAR,
    key_results: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    response = await api.post(
        f"{V1}/annual/{year}/goals/bulk",
        json={"goals": [{"title": "Annual goal", "key_results": key_results or []}]},
    )
    assert response.status_code == 201, response.text
    return cast(dict[str, Any], response.json()["goals"][0])


@pytest.mark.parametrize(
    "operation",
    [
        "add_goal",
        "edit_goal",
        "retire_goal",
        "restore_goal",
        "add_key_result",
        "edit_key_result",
        "retire_key_result",
        "restore_key_result",
        "change_links",
        "seed",
        "undo",
    ],
)
async def test_past_year_structure_changes_are_refused(operation: str, env: ProjectsEnv) -> None:
    _freeze(env.api, BEFORE_YEAR_END)
    theme_id = await _theme(env) if operation == "change_links" else None
    goal = await _create_goal(
        env.api,
        key_results=[
            _key_result(),
        ],
    )
    key_result_id = goal["key_results"][0]["id"]
    if theme_id is not None:
        linked = await env.api.put(
            f"{V1}/annual/key-results/{key_result_id}/themes",
            json={"theme_ids": [theme_id]},
        )
        assert linked.status_code == 200, linked.text
    batch_id: str | None = None

    if operation in {"restore_goal", "undo"}:
        retired = await env.api.post(
            f"{V1}/annual/goals/{goal['id']}/retire",
            json={"reason": "Set up restore coverage"},
        )
        assert retired.status_code == 200, retired.text
        batch_id = retired.json()["batch_id"]
    elif operation == "restore_key_result":
        retired = await env.api.post(f"{V1}/annual/key-results/{key_result_id}/retire", json={})
        assert retired.status_code == 200, retired.text

    if operation == "undo":
        assert batch_id is not None
        response: Response | None = None
    else:
        response = None

    if operation == "seed":
        source = await _create_goal(env.api, year=2029)
        assert source["title"] == "Annual goal"

    _freeze(env.api, AFTER_YEAR_END)
    plan = await env.api.get(f"{V1}/annual/{YEAR}")
    history = await env.api.get(f"{V1}/annual/{YEAR}/history")
    assert plan.status_code == 200 and plan.json()["state"] == "past"
    assert history.status_code == 200
    if operation == "add_goal":
        response = await env.api.post(
            f"{V1}/annual/{YEAR}/goals/bulk",
            json={"goals": [{"title": "Too late"}]},
        )
    elif operation == "edit_goal":
        response = await env.api.patch(
            f"{V1}/annual/goals/{goal['id']}", json={"title": "Too late"}
        )
    elif operation == "retire_goal":
        response = await env.api.post(f"{V1}/annual/goals/{goal['id']}/retire", json={})
    elif operation == "restore_goal":
        response = await env.api.post(f"{V1}/annual/goals/{goal['id']}/restore")
    elif operation == "add_key_result":
        response = await env.api.post(
            f"{V1}/annual/goals/{goal['id']}/key-results",
            json=_key_result("Too late"),
        )
    elif operation == "edit_key_result":
        response = await env.api.patch(
            f"{V1}/annual/key-results/{key_result_id}",
            json={"metric": "Too late"},
        )
    elif operation == "retire_key_result":
        response = await env.api.post(f"{V1}/annual/key-results/{key_result_id}/retire", json={})
    elif operation == "restore_key_result":
        response = await env.api.post(f"{V1}/annual/key-results/{key_result_id}/restore")
    elif operation == "change_links":
        response = await env.api.put(
            f"{V1}/annual/key-results/{key_result_id}/themes",
            json={"theme_ids": []},
        )
    elif operation == "seed":
        response = await env.api.post(
            f"{V1}/annual/{YEAR}/goals/bulk",
            json={"seeded_from": 2029, "goals": [{"title": "Seeded too late"}]},
        )
    else:
        assert operation == "undo" and batch_id is not None
        response = await env.api.post(f"{V1}/annual/undo", json={"batch_id": batch_id})

    assert response is not None
    assert response.status_code == 409, f"{operation}: {response.text}"
    assert response.json()["code"] == "past_year"


async def test_future_year_allows_create_edit_link_retire_restore_and_seed(
    env: ProjectsEnv,
) -> None:
    _freeze(env.api, datetime(2030, 6, 1, 12, tzinfo=UTC))
    theme_id = await _theme(env)
    goal = await _create_goal(
        env.api,
        year=2031,
        key_results=[_key_result(year=2031)],
    )
    key_result_id = goal["key_results"][0]["id"]
    linked = await env.api.put(
        f"{V1}/annual/key-results/{key_result_id}/themes",
        json={"theme_ids": [theme_id]},
    )
    assert linked.status_code == 200, linked.text

    title = await env.api.patch(
        f"{V1}/annual/goals/{goal['id']}", json={"title": "Future goal edited"}
    )
    metric = await env.api.patch(
        f"{V1}/annual/key-results/{key_result_id}",
        json={"metric": "Future measure"},
    )
    links_removed = await env.api.put(
        f"{V1}/annual/key-results/{key_result_id}/themes",
        json={"theme_ids": []},
    )
    links_added = await env.api.put(
        f"{V1}/annual/key-results/{key_result_id}/themes",
        json={"theme_ids": [theme_id]},
    )
    retired_kr = await env.api.post(f"{V1}/annual/key-results/{key_result_id}/retire", json={})
    restored_kr = await env.api.post(f"{V1}/annual/key-results/{key_result_id}/restore")
    retired_goal = await env.api.post(f"{V1}/annual/goals/{goal['id']}/retire", json={})
    restored_goal = await env.api.post(f"{V1}/annual/goals/{goal['id']}/restore")
    seeded = await env.api.post(
        f"{V1}/annual/2032/goals/bulk",
        json={
            "seeded_from": 2031,
            "goals": [{"title": "Seeded future goal"}],
        },
    )

    assert title.status_code == 200, title.text
    assert metric.status_code == 200, metric.text
    assert links_removed.status_code == 200, links_removed.text
    assert links_added.status_code == 200, links_added.text
    assert retired_kr.status_code == 200, retired_kr.text
    assert restored_kr.status_code == 200, restored_kr.text
    assert retired_goal.status_code == 200, retired_goal.text
    assert restored_goal.status_code == 200, restored_goal.text
    assert seeded.status_code == 201, seeded.text
    assert seeded.json()["goals"][0]["title"] == "Seeded future goal"


async def test_year_state_and_write_guard_follow_user_timezone_with_injected_clock(
    api: AsyncClient,
) -> None:
    _freeze(api, datetime(2030, 1, 1, 1, tzinfo=UTC))
    user = (await api.get(f"{V1}/auth/me")).json()
    updated = await api.patch(f"{V1}/users/{user['id']}", json={"timezone": "America/Los_Angeles"})
    assert updated.status_code == 200, updated.text

    current = await api.get(f"{V1}/annual/2029")
    future = await api.get(f"{V1}/annual/2030")
    assert current.status_code == 200 and current.json()["state"] == "current"
    assert future.status_code == 200 and future.json()["state"] == "future"
    created = await api.post(
        f"{V1}/annual/2029/goals/bulk",
        json={"goals": [{"title": "Still current in Los Angeles"}]},
    )
    assert created.status_code == 201, created.text

    updated = await api.patch(f"{V1}/users/{user['id']}", json={"timezone": "Europe/Athens"})
    assert updated.status_code == 200, updated.text
    past = await api.get(f"{V1}/annual/2029")
    assert past.status_code == 200 and past.json()["state"] == "past"
    refused = await api.post(
        f"{V1}/annual/2029/goals/bulk",
        json={"goals": [{"title": "Already over in Athens"}]},
    )
    assert refused.status_code == 409
    assert refused.json()["code"] == "past_year"
