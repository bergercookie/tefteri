"""Annual-plan reads, atomic creation, goal edits and user isolation."""

from collections.abc import Awaitable, Callable

from httpx import AsyncClient

from tests.conftest import V1

YEAR = 2026
MakeUser = Callable[[str], Awaitable[AsyncClient]]


async def test_an_empty_year_returns_an_empty_plan(api: AsyncClient) -> None:
    response = await api.get(f"{V1}/annual/{YEAR}")

    assert response.status_code == 200, response.text
    plan = response.json()
    assert plan["year"] == YEAR
    assert plan["goals"] == []
    assert plan["retired_goals"] == []


async def test_bulk_goal_create_trims_titles_and_records_edits(api: AsyncClient) -> None:
    created = await api.post(
        f"{V1}/annual/{YEAR}/goals/bulk",
        json={
            "goals": [
                {
                    "title": "  Learn more  ",
                    "key_results": [
                        {
                            "metric": "Read books",
                            "start_value": 0,
                            "target": 12,
                            "deadline": "2026-12-31",
                        }
                    ],
                }
            ]
        },
    )
    assert created.status_code == 201, created.text
    goal = created.json()["goals"][0]
    assert goal["title"] == "Learn more"
    assert [row["metric"] for row in goal["key_results"]] == ["Read books"]

    edited = await api.patch(f"{V1}/annual/goals/{goal['id']}", json={"title": "Learn deeply"})
    assert edited.status_code == 200, edited.text
    assert edited.json()["title"] == "Learn deeply"

    history = (await api.get(f"{V1}/annual/{YEAR}/history")).json()["changes"]
    change = next(row for row in history if row["kind"] == "goal_edited")
    assert (change["old_value"], change["new_value"]) == ("Learn more", "Learn deeply")
    assert change["batch_id"]


async def test_blank_goal_title_is_rejected_without_partial_bulk_creation(
    api: AsyncClient,
) -> None:
    response = await api.post(
        f"{V1}/annual/{YEAR}/goals/bulk",
        json={"goals": [{"title": "Would be valid"}, {"title": "  "}]},
    )

    assert response.status_code == 422, response.text
    assert (await api.get(f"{V1}/annual/{YEAR}")).json()["goals"] == []


async def test_bad_key_result_rolls_back_the_whole_bulk_create(api: AsyncClient) -> None:
    response = await api.post(
        f"{V1}/annual/{YEAR}/goals/bulk",
        json={
            "goals": [
                {"title": "First"},
                {
                    "title": "Invalid key result",
                    "key_results": [
                        {
                            "metric": "A measure",
                            "start_value": 0,
                            "target": 10,
                            "deadline": "2027-01-01",
                        }
                    ],
                },
            ]
        },
    )

    assert response.status_code == 422, response.text
    assert (await api.get(f"{V1}/annual/{YEAR}")).json()["goals"] == []
    assert (await api.get(f"{V1}/annual/{YEAR}/history")).json()["changes"] == []


async def test_goal_without_key_result_is_saved_with_a_nonblocking_flag(
    api: AsyncClient,
) -> None:
    created = await api.post(
        f"{V1}/annual/{YEAR}/goals/bulk",
        json={"goals": [{"title": "A broad goal"}]},
    )
    assert created.status_code == 201, created.text

    plan = (await api.get(f"{V1}/annual/{YEAR}")).json()
    goal = plan["goals"][0]
    assert any(
        flag["code"] == "no_key_result" and "add_key_result" in flag["actions"]
        for flag in goal["flags"]
    )
    assert goal["key_results"] == []


async def test_annual_goals_are_private_to_their_owner(
    api: AsyncClient, make_user: MakeUser
) -> None:
    made = await api.post(
        f"{V1}/annual/{YEAR}/goals/bulk",
        json={"goals": [{"title": "Private goal"}]},
    )
    goal_id = made.json()["goals"][0]["id"]
    other = await make_user("annual-reader")

    assert (await other.get(f"{V1}/annual/{YEAR}")).json()["goals"] == []
    assert (
        await other.patch(f"{V1}/annual/goals/{goal_id}", json={"title": "Changed"})
    ).status_code == 404
