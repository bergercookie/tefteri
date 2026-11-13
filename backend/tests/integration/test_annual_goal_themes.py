"""Adding one theme to all key results of an annual goal (bulk theme link)."""

from tests.conftest import V1
from tests.integration.annual_helpers import (
    connect_themes,
    create_goal,
    freeze,
    key_result_of,
    kr,
    plan,
)
from tests.integration.conftest import ProjectsEnv


def _themes(key_result: dict[str, object]) -> set[str]:
    links = key_result["links"]
    assert isinstance(links, list)
    return {
        str(link["name"])  # type: ignore[index]
        for link in links
        if link["active"]  # type: ignore[index]
    }


async def test_a_theme_is_added_to_every_active_key_result_in_one_undoable_batch(
    env: ProjectsEnv,
) -> None:
    freeze(env.api)
    themes = await connect_themes(env, "Open source", "Talks")
    created = await create_goal(
        env.api,
        "Get better at open source",
        kr("Stars", themes=[themes["Talks"]]),
        kr("Talks given"),
    )
    goal = created
    first, second = goal["key_results"]

    added = await env.api.put(
        f"{V1}/annual/goals/{goal['id']}/themes",
        json={"theme_ids": [themes["Open source"]]},
    )
    assert added.status_code == 200, added.text
    batch = added.json()["batch_id"]
    assert [entry["name"] for entry in added.json()["effect"]["added"]] == ["Open source"]

    after = await plan(env.api)
    first_after = key_result_of(after, first["id"])
    second_after = key_result_of(after, second["id"])
    assert _themes(first_after) == {"Open source", "Talks"}
    assert _themes(second_after) == {"Open source"}
    assert "no_usable_theme" not in [f["code"] for f in second_after["flags"]]

    history = (await env.api.get(f"{V1}/annual/2030/history")).json()["changes"]
    added_rows = [row for row in history if row["batch_id"] == batch]
    assert len(added_rows) == 2
    assert all(row["kind"] == "link_added" for row in added_rows)

    undone = await env.api.post(f"{V1}/annual/undo", json={"batch_id": batch})
    assert undone.status_code == 200, undone.text
    reverted = await plan(env.api)
    assert _themes(key_result_of(reverted, first["id"])) == {"Talks"}
    assert _themes(key_result_of(reverted, second["id"])) == set()


async def test_a_goal_theme_that_is_not_a_live_theme_is_refused(env: ProjectsEnv) -> None:
    freeze(env.api)
    themes = await connect_themes(env, "Open source")
    created = await create_goal(env.api, "Goal", kr("Stars", themes=[themes["Open source"]]))
    goal = created

    refused = await env.api.put(
        f"{V1}/annual/goals/{goal['id']}/themes",
        json={"theme_ids": ["00000000-0000-0000-0000-000000000000"]},
    )

    assert refused.status_code == 422, refused.text
    assert refused.json()["code"] == "not_a_theme"
