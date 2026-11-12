"""Creating annual-plan themes through the connected task app (spec 006, FR-015)."""

import uuid
from datetime import UTC, datetime
from typing import Any

from httpx import AsyncClient

from tefteri.domain.entities import Container
from tests.conftest import V1, connect_all
from tests.integration.conftest import ProjectsEnv

YEAR = 2030


async def _connect(env: ProjectsEnv, *containers: Container) -> None:
    env.world.tasks["default"].containers.extend(containers)
    ids = await connect_all(env.api)
    env.connection_id = ids["vikunja"]
    await env.sync()


def _freeze_plan_clock(env: ProjectsEnv) -> None:
    env.app.state.annual_service._clock = lambda: datetime(2030, 7, 1, tzinfo=UTC)


async def _create_theme(api: AsyncClient, connection_id: str, name: str) -> Any:
    return await api.post(
        f"{V1}/annual/themes", json={"connection_id": connection_id, "name": name}
    )


async def test_theme_creation_writes_the_task_app_and_is_immediately_pickable(
    env: ProjectsEnv,
) -> None:
    _freeze_plan_clock(env)
    await _connect(env)
    past_plan = await env.api.get(f"{V1}/annual/2029")
    assert past_plan.status_code == 200 and past_plan.json()["editable"] is False

    created = await _create_theme(env.api, env.connection_id, "  Product direction  ")

    assert created.status_code == 201, created.text
    theme = created.json()
    assert theme["name"] == "Product direction"
    assert any(
        project.name == "Product direction" and project.parent_id is None
        for project in env.world.tasks["default"].containers
    )
    classification = await env.api.get(
        f"{V1}/projects/classification", params={"connection_id": env.connection_id}
    )
    assert classification.status_code == 200, classification.text
    project = next(
        project
        for project in classification.json()["connections"][0]["projects"]
        if project["id"] == theme["project_id"]
    )
    assert project["label"] == "theme"
    picker = await env.api.get(f"{V1}/annual/themes")
    assert picker.status_code == 200, picker.text
    assert any(row["project_id"] == theme["project_id"] for row in picker.json()["themes"])


async def test_task_app_refusal_returns_error_without_storing_a_theme(env: ProjectsEnv) -> None:
    await _connect(env)
    env.world.tasks["default"].unavailable = True

    refused = await _create_theme(env.api, env.connection_id, "Unavailable theme")

    assert refused.status_code == 502, refused.text
    assert refused.json()["code"] == "backend_unavailable"
    assert [container.name for container in env.world.tasks["default"].containers] == ["Inbox"]
    classification = await env.api.get(
        f"{V1}/projects/classification", params={"connection_id": env.connection_id}
    )
    assert [project["name"] for project in classification.json()["connections"][0]["projects"]] == [
        "Inbox"
    ]


async def test_theme_names_are_unique_case_insensitively_per_connection(
    env: ProjectsEnv,
) -> None:
    await _connect(env)
    first = await _create_theme(env.api, env.connection_id, "Research")
    assert first.status_code == 201, first.text

    duplicate = await _create_theme(env.api, env.connection_id, "rEsEaRcH")

    assert duplicate.status_code == 409, duplicate.text
    assert duplicate.json()["code"] == "theme_exists"
    assert duplicate.json()["existing"] == {
        "project_id": first.json()["project_id"],
        "name": "Research",
    }


async def test_unknown_and_foreign_task_connections_answer_not_found(
    env: ProjectsEnv, make_user: object
) -> None:
    await _connect(env)
    other = await make_user("annual-theme-reader")  # type: ignore[operator]

    unknown = await _create_theme(env.api, str(uuid.uuid4()), "Unknown connection")
    foreign = await _create_theme(other, env.connection_id, "Foreign connection")

    assert unknown.status_code == 404
    assert unknown.json()["code"] == "not_found"
    assert foreign.status_code == 404
    assert foreign.json()["code"] == "not_found"
