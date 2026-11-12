"""Annual key-result and goal flags remain advisory (spec 006, FR-014)."""

from datetime import UTC, datetime
from typing import Any

from httpx import AsyncClient

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
    api: AsyncClient, title: str, *, themes: list[str] | None = None, deadline: str | None = None
) -> tuple[dict[str, Any], dict[str, Any]]:
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
            "deadline": deadline or f"{YEAR}-12-31",
            "theme_ids": themes or [],
        },
    )
    assert key_result_response.status_code == 201, key_result_response.text
    return goal, key_result_response.json()


async def _key_result(api: AsyncClient, key_result_id: str) -> dict[str, Any]:
    plan = (await api.get(f"{V1}/annual/{YEAR}")).json()
    return next(
        key_result
        for goal in plan["goals"]
        for key_result in goal["key_results"]
        if key_result["id"] == key_result_id
    )


async def test_no_links_are_flagged_and_do_not_block_key_result_saves(env: ProjectsEnv) -> None:
    await _connect(env, Container("p2", "Theme"))
    rows = await _label(env, Theme=ProjectLabel.THEME)
    goal, key_result = await _goal_and_key_result(env.api, "No links", deadline=f"{YEAR}-12-31")
    assert key_result["flags"] == [
        {
            "code": "no_usable_theme",
            "actions": ["link_theme", "create_theme"],
            "reasons": [{"project_id": None, "name": None, "state": "no_links", "label": None}],
        }
    ]

    linked = await env.api.put(
        f"{V1}/annual/key-results/{key_result['id']}/themes",
        json={"theme_ids": [str(rows["Theme"].id)]},
    )
    assert linked.status_code == 200, linked.text
    assert "no_usable_theme" not in {
        flag["code"] for flag in (await _key_result(env.api, key_result["id"]))["flags"]
    }

    # An unlinked key result can still be saved, and its value series can be updated.
    another_goal, another_key_result = await _goal_and_key_result(env.api, "Save without a link")
    value = await env.api.post(
        f"{V1}/annual/key-results/{another_key_result['id']}/values", json={"value": 4}
    )
    assert value.status_code == 201, value.text
    assert value.json()["key_result"]["current_value"] == 4
    assert another_goal["id"] != goal["id"]


async def test_relabelled_themes_return_named_flags_for_each_unusable_state(
    env: ProjectsEnv,
) -> None:
    await _connect(env, Container("p2", "Theme"))
    rows = await _label(env, Theme=ProjectLabel.THEME)
    _, key_result = await _goal_and_key_result(
        env.api, "Relabel flags", themes=[str(rows["Theme"].id)]
    )
    assert key_result["flags"] == []

    for label, reason_state in (
        (ProjectLabel.IGNORED, "ignored"),
        (ProjectLabel.MILESTONE, "relabelled"),
        (ProjectLabel.MAINTENANCE, "relabelled"),
    ):
        await _label(env, Theme=label)
        flags = (await _key_result(env.api, key_result["id"]))["flags"]
        assert flags[0]["code"] == "no_usable_theme"
        assert flags[0]["reasons"][0]["name"] == "Theme"
        assert flags[0]["reasons"][0]["state"] == reason_state
        await _label(env, Theme=ProjectLabel.THEME)
        assert (await _key_result(env.api, key_result["id"]))["flags"] == []


async def test_an_ignored_ancestor_makes_a_linked_theme_unusable(env: ProjectsEnv) -> None:
    await _connect(env, Container("p2", "Ignored parent"), Container("p3", "Child theme", "p2"))
    rows = await _label(env, **{"Child theme": ProjectLabel.THEME})
    _, key_result = await _goal_and_key_result(
        env.api, "Ignored ancestor", themes=[str(rows["Child theme"].id)]
    )
    await _label(env, **{"Ignored parent": ProjectLabel.IGNORED})

    flags = (await _key_result(env.api, key_result["id"]))["flags"]

    assert flags[0]["code"] == "no_usable_theme"
    assert flags[0]["reasons"][0]["name"] == "Child theme"
    assert flags[0]["reasons"][0]["state"] == "ignored"


async def test_archived_and_missing_linked_themes_are_named_as_orphaned(env: ProjectsEnv) -> None:
    await _connect(
        env,
        Container("p2", "Archived theme"),
        Container("p3", "Missing theme"),
    )
    rows = await _label(
        env,
        **{
            "Archived theme": ProjectLabel.THEME,
            "Missing theme": ProjectLabel.THEME,
        },
    )
    _, archived_result = await _goal_and_key_result(
        env.api, "Archive flag", themes=[str(rows["Archived theme"].id)]
    )
    _, missing_result = await _goal_and_key_result(
        env.api, "Missing flag", themes=[str(rows["Missing theme"].id)]
    )

    archived = await env.api.post(f"{V1}/projects/{rows['Archived theme'].id}/archive")
    assert archived.status_code == 200, archived.text
    backend = env.world.tasks["default"]
    backend.containers = [
        container for container in backend.containers if container.remote_id != "p3"
    ]
    await env.sync()

    for key_result, name in (
        (archived_result, "Archived theme"),
        (missing_result, "Missing theme"),
    ):
        flags = (await _key_result(env.api, key_result["id"]))["flags"]
        assert flags[0]["code"] == "no_usable_theme"
        assert flags[0]["reasons"][0]["name"] == name
        assert flags[0]["reasons"][0]["state"] == "orphaned"


async def test_overdue_flag_depends_on_deadline_and_whether_target_is_met(
    env: ProjectsEnv,
) -> None:
    await _connect(env)
    _, below_target = await _goal_and_key_result(env.api, "Overdue", deadline="2030-06-30")
    _, met = await _goal_and_key_result(env.api, "Met", deadline="2030-06-30")
    value = await env.api.post(f"{V1}/annual/key-results/{met['id']}/values", json={"value": 10})
    assert value.status_code == 201, value.text

    overdue_flags = (await _key_result(env.api, below_target["id"]))["flags"]
    met_flags = (await _key_result(env.api, met["id"]))["flags"]
    assert [flag["code"] for flag in overdue_flags] == ["no_usable_theme", "overdue"]
    assert [flag["code"] for flag in met_flags] == ["no_usable_theme"]


async def test_a_goal_without_key_results_has_the_inline_add_action(env: ProjectsEnv) -> None:
    created = await env.api.post(
        f"{V1}/annual/{YEAR}/goals/bulk", json={"goals": [{"title": "No key result"}]}
    )
    assert created.status_code == 201, created.text

    plan = (await env.api.get(f"{V1}/annual/{YEAR}")).json()

    assert plan["goals"][0]["flags"] == [
        {"code": "no_key_result", "actions": ["add_key_result"], "reasons": []}
    ]
