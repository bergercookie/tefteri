"""Annual key-result theme links and their history (spec 006, FR-013)."""

import uuid
from datetime import UTC, datetime
from typing import Any

from httpx import AsyncClient
from sqlalchemy import select

from tefteri.db.models.key_result import KeyResultTheme, PlanChange
from tefteri.domain.entities import Container
from tefteri.domain.enums import ProjectLabel
from tefteri.services.classification import Change
from tests.conftest import V1, connect_all
from tests.integration.conftest import ProjectsEnv

YEAR = 2030


async def _connect(env: ProjectsEnv, *containers: Container) -> None:
    env.app.state.annual_service._clock = lambda: datetime(2030, 7, 1, tzinfo=UTC)
    env.world.tasks["default"].containers.extend(containers)
    ids = await connect_all(env.api)
    env.connection_id = ids["vikunja"]
    await env.sync()


async def _label(env: ProjectsEnv, **labels: ProjectLabel | None) -> dict[str, Any]:
    rows = await env.rows()
    async with env.db() as db:
        await env.classification.save(
            db,
            await env.user_id(),
            [Change(rows[name].id, label) for name, label in labels.items()],
        )
    return rows


async def _goal_and_key_result(
    api: AsyncClient, title: str, *, themes: list[str] | None = None
) -> tuple[str, dict[str, Any]]:
    goal_response = await api.post(
        f"{V1}/annual/{YEAR}/goals/bulk", json={"goals": [{"title": title}]}
    )
    assert goal_response.status_code == 201, goal_response.text
    goal = goal_response.json()["goals"][0]
    key_result_response = await api.post(
        f"{V1}/annual/goals/{goal['id']}/key-results",
        json={
            "metric": f"{title} measure",
            "start_value": 0,
            "target": 10,
            "deadline": f"{YEAR}-12-31",
            "theme_ids": themes or [],
        },
    )
    assert key_result_response.status_code == 201, key_result_response.text
    return goal["id"], key_result_response.json()


async def _all_key_results(api: AsyncClient) -> list[dict[str, Any]]:
    plan = (await api.get(f"{V1}/annual/{YEAR}")).json()
    return [result for goal in plan["goals"] for result in goal["key_results"]]


async def test_theme_picker_lists_only_live_stored_themes(env: ProjectsEnv) -> None:
    await _connect(
        env,
        Container("p2", "Live theme"),
        Container("p3", "Milestone"),
        Container("p4", "Maintenance"),
        Container("p5", "Ignored"),
        Container("p6", "Unclassified"),
        Container("p7", "Missing theme"),
    )
    rows = await _label(
        env,
        **{
            "Live theme": ProjectLabel.THEME,
            "Milestone": ProjectLabel.MILESTONE,
            "Maintenance": ProjectLabel.MAINTENANCE,
            "Ignored": ProjectLabel.IGNORED,
            "Missing theme": ProjectLabel.THEME,
        },
    )
    backend = env.world.tasks["default"]
    backend.containers = [c for c in backend.containers if c.remote_id != "p7"]
    await env.sync()

    response = await env.api.get(f"{V1}/annual/themes")
    assert response.status_code == 200, response.text
    assert [(theme["name"], theme["project_id"]) for theme in response.json()["themes"]] == [
        ("Live theme", str(rows["Live theme"].id))
    ]
    assert response.json()["unsorted_count"] == 2
    assert response.json()["task_connections"] == [
        {"id": env.connection_id, "name": "vikunja", "can_create": True}
    ]


async def test_themes_can_be_shared_and_plan_has_the_reverse_usage(env: ProjectsEnv) -> None:
    await _connect(env, Container("p2", "Theme A"), Container("p3", "Theme B"))
    rows = await _label(env, **{"Theme A": ProjectLabel.THEME, "Theme B": ProjectLabel.THEME})

    _, first = await _goal_and_key_result(env.api, "First goal", themes=[str(rows["Theme A"].id)])
    _, second = await _goal_and_key_result(env.api, "Second goal", themes=[str(rows["Theme A"].id)])
    _, third = await _goal_and_key_result(
        env.api,
        "Third goal",
        themes=[str(rows["Theme A"].id), str(rows["Theme B"].id)],
    )

    plan = (await env.api.get(f"{V1}/annual/{YEAR}")).json()
    usage = {row["name"]: set(row["key_result_ids"]) for row in plan["theme_usage"]}
    assert usage == {
        "Theme A": {first["id"], second["id"], third["id"]},
        "Theme B": {third["id"]},
    }


async def test_removing_a_link_ends_and_keeps_its_row(env: ProjectsEnv) -> None:
    await _connect(env, Container("p2", "Theme"))
    rows = await _label(env, Theme=ProjectLabel.THEME)
    _, key_result = await _goal_and_key_result(
        env.api, "Unlink goal", themes=[str(rows["Theme"].id)]
    )

    removed = await env.api.put(
        f"{V1}/annual/key-results/{key_result['id']}/themes", json={"theme_ids": []}
    )
    assert removed.status_code == 200, removed.text
    historic = next(
        result for result in await _all_key_results(env.api) if result["id"] == key_result["id"]
    )
    assert len(historic["links"]) == 1
    assert historic["links"][0]["active"] is False
    assert historic["links"][0]["ended_at"] is not None
    async with env.db() as db:
        links = list((await db.execute(select(KeyResultTheme))).scalars())
    assert len(links) == 1
    assert links[0].end_reason == "removed"
    assert links[0].ended_at is not None


async def test_setting_an_already_linked_theme_does_not_add_a_second_active_link(
    env: ProjectsEnv,
) -> None:
    await _connect(env, Container("p2", "Theme"))
    rows = await _label(env, Theme=ProjectLabel.THEME)
    _, key_result = await _goal_and_key_result(
        env.api, "Single link goal", themes=[str(rows["Theme"].id)]
    )

    repeated = await env.api.put(
        f"{V1}/annual/key-results/{key_result['id']}/themes",
        json={"theme_ids": [str(rows["Theme"].id)]},
    )

    assert repeated.status_code == 200, repeated.text
    async with env.db() as db:
        links = list((await db.execute(select(KeyResultTheme))).scalars())
    assert len(links) == 1
    assert links[0].ended_at is None


async def test_dry_run_reports_link_changes_without_writing(env: ProjectsEnv) -> None:
    await _connect(env, Container("p2", "Theme A"), Container("p3", "Theme B"))
    rows = await _label(env, **{"Theme A": ProjectLabel.THEME, "Theme B": ProjectLabel.THEME})
    _, key_result = await _goal_and_key_result(
        env.api, "Dry run goal", themes=[str(rows["Theme A"].id)]
    )

    response = await env.api.put(
        f"{V1}/annual/key-results/{key_result['id']}/themes",
        json={"theme_ids": [str(rows["Theme B"].id)], "dry_run": True},
    )

    assert response.status_code == 200, response.text
    assert response.json()["effect"]["added"] == [
        {"project_id": str(rows["Theme B"].id), "name": "Theme B", "state": None}
    ]
    assert response.json()["effect"]["ended"] == [
        {"project_id": str(rows["Theme A"].id), "name": "Theme A", "state": None}
    ]
    active = next(
        result for result in await _all_key_results(env.api) if result["id"] == key_result["id"]
    )
    assert [(link["project_id"], link["active"]) for link in active["links"]] == [
        (str(rows["Theme A"].id), True)
    ]
    async with env.db() as db:
        links = list((await db.execute(select(KeyResultTheme))).scalars())
    assert len(links) == 1 and links[0].ended_at is None


async def test_relink_ends_and_starts_one_pair_in_the_same_batch(env: ProjectsEnv) -> None:
    await _connect(env, Container("p2", "Theme A"), Container("p3", "Theme B"))
    rows = await _label(env, **{"Theme A": ProjectLabel.THEME, "Theme B": ProjectLabel.THEME})
    _, key_result = await _goal_and_key_result(
        env.api, "Relink goal", themes=[str(rows["Theme A"].id)]
    )

    response = await env.api.put(
        f"{V1}/annual/key-results/{key_result['id']}/themes",
        json={"theme_ids": [str(rows["Theme B"].id)]},
    )

    assert response.status_code == 200, response.text
    async with env.db() as db:
        links = list(
            (
                await db.execute(
                    select(KeyResultTheme).where(
                        KeyResultTheme.key_result_id == uuid.UUID(key_result["id"])
                    )
                )
            ).scalars()
        )
    assert len(links) == 2
    ended = next(link for link in links if link.ended_at is not None)
    started = next(link for link in links if link.ended_at is None)
    assert (ended.project_id, ended.end_reason) == (rows["Theme A"].id, "relinked")
    assert started.project_id == rows["Theme B"].id
    assert ended.ended_at is not None
    async with env.db() as db:
        history = list(
            (
                await db.execute(
                    select(PlanChange).where(
                        PlanChange.key_result_id == uuid.UUID(key_result["id"])
                    )
                )
            ).scalars()
        )
    batch_id = next(row.batch_id for row in history if row.link_id == started.id)
    assert batch_id is not None
    in_relink_batch = [row for row in history if row.batch_id == batch_id]
    assert len(in_relink_batch) == 2
    assert {row.link_id for row in in_relink_batch} == {ended.id, started.id}
