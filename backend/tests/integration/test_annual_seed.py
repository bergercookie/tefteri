"""Start a new year from year N (spec 006, US5, FR-016, FR-017, SC-006)."""

import time
import uuid
from collections.abc import Awaitable, Callable
from typing import Any

from httpx import AsyncClient
from sqlalchemy import func, select

from tefteri.db.models.goal import Goal
from tefteri.db.models.key_result import KeyResult, KeyResultTheme, KeyResultValue, PlanChange
from tests.conftest import V1
from tests.integration.annual_helpers import (
    YEAR,
    connect_themes,
    create_goal,
    create_goals,
    enter_value,
    freeze,
    kr,
    plan,
    set_labels,
)
from tests.integration.conftest import ProjectsEnv

NEW = YEAR + 1


async def _counts(env: ProjectsEnv) -> dict[str, int]:
    async with env.db() as db:
        return {
            model.__tablename__: (
                await db.execute(select(func.count()).select_from(model))
            ).scalar_one()
            for model in (Goal, KeyResult, KeyResultValue, KeyResultTheme, PlanChange)
        }


async def _seed_source(env: ProjectsEnv) -> dict[str, Any]:
    """Year N: one goal with an unmet and a met key result, one retired goal, and themes."""
    freeze(env.api)
    themes = await connect_themes(env, "Open source", "Garden", "Writing")
    goal = await create_goal(
        env.api,
        "Open source",
        kr("Stars", start=100, target=500, themes=[themes["Open source"], themes["Garden"]]),
        kr("Talks", start=0, target=2),
    )
    stars, talks = goal["key_results"]
    await enter_value(env.api, stars["id"], 220, f"{YEAR}-06-01")
    await enter_value(env.api, talks["id"], 2, f"{YEAR}-06-02")
    other = await create_goal(env.api, "Write more", kr("Posts", themes=[themes["Writing"]]))
    dropped = await create_goal(env.api, "Dropped goal", kr("Never"))
    retired = await env.api.post(f"{V1}/annual/goals/{dropped['id']}/retire", json={})
    assert retired.status_code == 200, retired.text
    # The theme of one link is no longer usable: it is now a milestone.
    await set_labels(env, {themes["Garden"]: "milestone"})
    return {"goal": goal, "stars": stars, "talks": talks, "other": other, "themes": themes}


async def test_suggestions_come_from_the_year_before_and_write_nothing(env: ProjectsEnv) -> None:
    source = await _seed_source(env)
    before = await _counts(env)

    response = await env.api.get(f"{V1}/annual/{NEW}/suggestions")

    assert response.status_code == 200, response.text
    body = response.json()
    assert (body["year"], body["from_year"], body["has_plan"]) == (NEW, YEAR, True)
    assert [g["title"] for g in body["goals"]] == ["Open source", "Write more"]
    first = body["goals"][0]
    assert first["goal_id"] == source["goal"]["id"]
    # The met key result is not offered, its goal is; the retired goal is not offered.
    assert [k["metric"] for k in first["key_results"]] == ["Stars"]
    stars = first["key_results"][0]
    assert stars["key_result_id"] == source["stars"]["id"]
    assert (stars["start_value"], stars["target"], stars["deadline"]) == (220, 500, f"{NEW}-12-31")
    assert stars["update_source"] == "manual"
    # The link to the theme that became a milestone is not offered.
    assert stars["themes"] == [
        {"project_id": source["themes"]["Open source"], "name": "Open source"}
    ]
    assert await _counts(env) == before


async def test_changing_year_n_rebuilds_and_a_year_without_plan_says_so(env: ProjectsEnv) -> None:
    await _seed_source(env)

    empty = await env.api.get(f"{V1}/annual/{NEW}/suggestions", params={"from_year": YEAR - 3})
    assert empty.status_code == 200
    assert empty.json() == {"year": NEW, "from_year": YEAR - 3, "has_plan": False, "goals": []}

    explicit = await env.api.get(f"{V1}/annual/{NEW + 2}/suggestions", params={"from_year": YEAR})
    assert [g["title"] for g in explicit.json()["goals"]] == ["Open source", "Write more"]
    assert explicit.json()["goals"][0]["key_results"][0]["deadline"] == f"{NEW + 2}-12-31"

    later = await env.api.get(f"{V1}/annual/{NEW}/suggestions", params={"from_year": NEW})
    assert later.status_code == 422


async def test_accepting_creates_one_seeded_batch_and_leaves_year_n_unchanged(
    env: ProjectsEnv,
) -> None:
    source = await _seed_source(env)
    year_n = await plan(env.api, YEAR)
    suggestion = (await env.api.get(f"{V1}/annual/{NEW}/suggestions")).json()["goals"][0]
    accepted = suggestion["key_results"][0]

    created = await create_goals(
        env.api,
        [
            {
                "title": suggestion["title"],
                "seeded_from_goal_id": suggestion["goal_id"],
                "key_results": [
                    {
                        **kr(
                            accepted["metric"],
                            start=250,  # edited before the save
                            target=accepted["target"],
                            deadline=accepted["deadline"],
                            themes=[t["project_id"] for t in accepted["themes"]],
                        ),
                        "seeded_from_key_result_id": accepted["key_result_id"],
                    }
                ],
            }
        ],
        year=NEW,
        seeded_from=YEAR,
    )

    goal = created["goals"][0]
    assert goal["key_results"][0]["start_value"] == 250
    assert goal["key_results"][0]["current_value"] == 250
    assert [link["project_id"] for link in goal["key_results"][0]["links"]] == [
        source["themes"]["Open source"]
    ]
    async with env.db() as db:
        row = await db.get(KeyResult, uuid.UUID(goal["key_results"][0]["id"]))
        assert row is not None and str(row.seeded_from_id) == source["stars"]["id"]
    changes = (await env.api.get(f"{V1}/annual/{NEW}/history")).json()["changes"]
    assert {c["source"] for c in changes} == {"seed"}
    assert {c["batch_id"] for c in changes} == {created["batch_id"]}
    assert await plan(env.api, YEAR) == year_n


async def test_seeding_cannot_point_at_another_users_key_result(
    env: ProjectsEnv, make_user: Callable[[str], Awaitable[AsyncClient]]
) -> None:
    source = await _seed_source(env)
    other = await make_user("bob")

    response = await other.post(
        f"{V1}/annual/{NEW}/goals/bulk",
        json={
            "seeded_from": YEAR,
            "goals": [
                {
                    "title": "Copied",
                    "key_results": [
                        {
                            **kr("Stars", year=NEW),
                            "seeded_from_key_result_id": source["stars"]["id"],
                        }
                    ],
                }
            ],
        },
    )

    assert response.status_code == 404
    assert (await plan(other, NEW))["goals"] == []


async def test_dismissing_all_leaves_a_blank_plan(env: ProjectsEnv) -> None:
    await _seed_source(env)
    await env.api.get(f"{V1}/annual/{NEW}/suggestions")

    blank = await plan(env.api, NEW)

    assert (blank["goals"], blank["retired_goals"], blank["state"]) == ([], [], "future")


async def test_suggestions_for_ten_goals_and_thirty_key_results_load_in_time(
    env: ProjectsEnv,
) -> None:
    freeze(env.api)
    await env.connect()
    await create_goals(
        env.api,
        [
            {"title": f"Goal {g}", "key_results": [kr(f"Measure {g}.{k}") for k in range(3)]}
            for g in range(10)
        ],
    )

    started = time.perf_counter()
    response = await env.api.get(f"{V1}/annual/{NEW}/suggestions")
    elapsed = time.perf_counter() - started

    assert response.status_code == 200
    assert sum(len(g["key_results"]) for g in response.json()["goals"]) == 30
    assert elapsed < 2.0
