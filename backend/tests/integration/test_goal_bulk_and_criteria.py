"""Goals created in bulk, and the description and completeness criteria of a goal."""

from httpx import AsyncClient

from tests.conftest import V1

YEAR = {"period_type": "year", "period_start": "2026-01-01"}


async def test_goals_are_created_in_bulk_and_blank_lines_are_skipped(api: AsyncClient) -> None:
    r = await api.post(
        f"{V1}/goals/bulk", json={**YEAR, "titles": ["Run 25 km", "  ", "Read 12 books", ""]}
    )
    assert r.status_code == 201, r.text
    assert [g["title"] for g in r.json()] == ["Run 25 km", "Read 12 books"]
    listed = (await api.get(f"{V1}/goals", params=YEAR)).json()
    assert {g["title"] for g in listed} == {"Run 25 km", "Read 12 books"}


async def test_bulk_creation_needs_a_title_and_is_all_or_nothing(api: AsyncClient) -> None:
    empty = await api.post(f"{V1}/goals/bulk", json={**YEAR, "titles": [" ", ""]})
    assert empty.status_code == 422, empty.text
    # A year goal cannot start in the middle of a year: nothing is created.
    bad = await api.post(
        f"{V1}/goals/bulk",
        json={"period_type": "year", "period_start": "2026-03-01", "titles": ["a", "b"]},
    )
    assert bad.status_code == 422, bad.text
    assert (await api.get(f"{V1}/goals")).json() == []


async def test_child_goals_are_created_in_bulk_under_a_goal(api: AsyncClient) -> None:
    parent = (await api.post(f"{V1}/goals", json={**YEAR, "title": "Get fit"})).json()
    r = await api.post(
        f"{V1}/goals/bulk",
        json={
            "period_type": "month",
            "period_start": "2026-03-01",
            "parent_id": parent["id"],
            "titles": ["Run weekly", "Swim"],
        },
    )
    assert r.status_code == 201, r.text
    assert all(g["parent_id"] == parent["id"] for g in r.json())
    outside = await api.post(
        f"{V1}/goals/bulk",
        json={
            "period_type": "month",
            "period_start": "2027-03-01",
            "parent_id": parent["id"],
            "titles": ["Too late"],
        },
    )
    assert outside.status_code == 422, outside.text


async def test_a_goal_keeps_its_description_and_completeness_criteria(api: AsyncClient) -> None:
    made = await api.post(
        f"{V1}/goals",
        json={
            **YEAR,
            "title": "Get fit",
            "description": "Feel good in my body.",
            "criteria": "Run 10 km in under an hour.",
        },
    )
    assert made.status_code == 201, made.text
    goal = made.json()
    assert goal["description"] == "Feel good in my body."
    assert goal["criteria"] == "Run 10 km in under an hour."
    patched = await api.patch(f"{V1}/goals/{goal['id']}", json={"criteria": "Run a marathon."})
    assert patched.json()["criteria"] == "Run a marathon."
    assert patched.json()["description"] == "Feel good in my body."
    plain = (await api.post(f"{V1}/goals", json={**YEAR, "title": "Other"})).json()
    assert plain["criteria"] == ""
