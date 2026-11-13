"""Shared steps for the annual planning tests of spec 006 (M4 and M5)."""

from datetime import UTC, datetime
from typing import Any, cast

from httpx import ASGITransport, AsyncClient

from tefteri.domain.entities import Container
from tests.conftest import V1
from tests.integration.conftest import ProjectsEnv

YEAR = 2030
NOW = datetime(2030, 7, 1, 12, tzinfo=UTC)
"""The frozen time of most tests: the middle of ``YEAR``."""


def freeze(api: AsyncClient, now: datetime = NOW) -> None:
    """Make every annual service see ``now`` as the current time."""
    app: Any = api.app  # type: ignore[attr-defined]
    app.state.annual_service._clock = lambda: now
    app.state.key_result_service._clock = lambda: now
    app.state.push_token_service._clock = lambda: now


async def connect_themes(
    env: ProjectsEnv, *names: str, labels: dict[str, str] | None = None
) -> dict[str, str]:
    """Connect a task app with one project per name and label them (default: theme).

    Returns the project ids by name.
    """
    await env.connect(*(Container(f"p{n}", name) for n, name in enumerate(names, start=2)))
    rows = await env.rows()
    wanted = {name: "theme" for name in names} | (labels or {})
    await set_labels(env, {rows[name].id: label for name, label in wanted.items()})
    return {name: str(rows[name].id) for name in names}


async def set_labels(env: ProjectsEnv, labels: dict[Any, str | None]) -> None:
    """Store project labels through the route of feature 003."""
    response = await env.api.put(
        f"{V1}/projects/labels",
        json={"changes": [{"id": str(pid), "label": label} for pid, label in labels.items()]},
    )
    assert response.status_code == 200, response.text


def kr(
    metric: str = "Measure",
    *,
    start: float = 0,
    target: float = 10,
    deadline: str | None = None,
    source: str = "manual",
    themes: list[str] | None = None,
    year: int = YEAR,
) -> dict[str, Any]:
    """The body of one key result."""
    return {
        "metric": metric,
        "start_value": start,
        "target": target,
        "deadline": deadline or f"{year}-12-31",
        "update_source": source,
        "theme_ids": themes or [],
    }


async def create_goals(
    api: AsyncClient, goals: list[dict[str, Any]], *, year: int = YEAR, **extra: Any
) -> dict[str, Any]:
    """Create goals through the bulk route and return the answer."""
    response = await api.post(f"{V1}/annual/{year}/goals/bulk", json={"goals": goals, **extra})
    assert response.status_code == 201, response.text
    return cast(dict[str, Any], response.json())


async def create_goal(
    api: AsyncClient, title: str = "Goal", *key_results: dict[str, Any], year: int = YEAR
) -> dict[str, Any]:
    """Create one goal with key results and return it as the plan shows it."""
    created = await create_goals(
        api, [{"title": title, "key_results": list(key_results)}], year=year
    )
    return cast(dict[str, Any], created["goals"][0])


async def enter_value(
    api: AsyncClient, key_result_id: str, value: float, day: str | None = None
) -> dict[str, Any]:
    """Store a manual value and return the answer."""
    body: dict[str, Any] = {"value": value}
    if day is not None:
        body["date"] = day
    response = await api.post(f"{V1}/annual/key-results/{key_result_id}/values", json=body)
    assert response.status_code == 201, response.text
    return cast(dict[str, Any], response.json())


async def plan(api: AsyncClient, year: int = YEAR) -> dict[str, Any]:
    """The plan of a year."""
    response = await api.get(f"{V1}/annual/{year}")
    assert response.status_code == 200, response.text
    return cast(dict[str, Any], response.json())


def key_result_of(plan_json: dict[str, Any], key_result_id: str) -> dict[str, Any]:
    """Find one key result in a plan answer."""
    for goal in plan_json["goals"] + plan_json["retired_goals"]:
        for item in goal["key_results"]:
            if item["id"] == key_result_id:
                return cast(dict[str, Any], item)
    raise AssertionError(f"no key result {key_result_id}")


def bare_client(api: AsyncClient) -> AsyncClient:
    """A client for the same app with no session: no cookie, no bearer, no client header."""
    return AsyncClient(
        transport=ASGITransport(app=api.app),  # type: ignore[attr-defined]
        base_url="http://test",
    )
