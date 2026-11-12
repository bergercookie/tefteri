"""The value series of a key result and the value on a date (spec 006, US7, FR-007 to FR-009)."""

from datetime import UTC, datetime

from tefteri.domain.entities import Container
from tests.conftest import V1
from tests.integration.annual_helpers import (
    NOW,
    YEAR,
    create_goal,
    enter_value,
    freeze,
    key_result_of,
    kr,
    plan,
)
from tests.integration.conftest import ProjectsEnv


async def _key_result(env: ProjectsEnv, **fields: object) -> dict[str, object]:
    freeze(env.api)
    await env.connect(Container("p2", "Unused"))
    goal = await create_goal(env.api, "Run", kr("Distance", start=10, target=100, **fields))  # type: ignore[arg-type]
    return goal["key_results"][0]


async def _current(env: ProjectsEnv, key_result_id: str) -> object:
    return key_result_of(await plan(env.api), key_result_id)["current_value"]


async def test_the_latest_date_is_the_current_value(env: ProjectsEnv) -> None:
    item = await _key_result(env)

    stored = await enter_value(env.api, item["id"], 40, f"{YEAR}-06-01")
    assert (stored["value"], stored["on_date"], stored["source"]) == (40, f"{YEAR}-06-01", "manual")
    assert stored["key_result"]["current_value"] == 40
    assert await _current(env, item["id"]) == 40

    await enter_value(env.api, item["id"], 20, f"{YEAR}-05-01")
    assert await _current(env, item["id"]) == 40

    without_date = await enter_value(env.api, item["id"], 55)
    assert without_date["on_date"] == NOW.date().isoformat()
    assert await _current(env, item["id"]) == 55


async def test_two_values_on_one_date_are_kept_and_the_later_entry_wins(env: ProjectsEnv) -> None:
    item = await _key_result(env)

    await enter_value(env.api, item["id"], 30, f"{YEAR}-06-01")
    await enter_value(env.api, item["id"], 35, f"{YEAR}-06-01")

    series = (await env.api.get(f"{V1}/annual/key-results/{item['id']}/values")).json()
    assert [(p["value"], p["seq"]) for p in series] == [(35, 2), (30, 1)]
    assert await _current(env, item["id"]) == 35


async def test_a_manual_entry_on_an_automatic_key_result_is_stored_as_manual(
    env: ProjectsEnv,
) -> None:
    item = await _key_result(env, source="automatic")

    stored = await enter_value(env.api, item["id"], 12, f"{YEAR}-06-01")

    assert stored["source"] == "manual"
    assert key_result_of(await plan(env.api), item["id"])["update_source"] == "automatic"


async def test_bad_values_future_dates_and_retired_key_results_are_refused(
    env: ProjectsEnv,
) -> None:
    item = await _key_result(env)
    url = f"{V1}/annual/key-results/{item['id']}/values"

    for body in ({"value": "abc"}, {"value": None}, {}):
        assert (await env.api.post(url, json=body)).status_code == 422
    nan = await env.api.post(
        url, content=b'{"value": NaN}', headers={"Content-Type": "application/json"}
    )
    assert nan.status_code == 422
    future = await env.api.post(url, json={"value": 5, "date": f"{YEAR}-07-02"})
    assert future.status_code == 422 and future.json()["code"] == "future_date"

    await env.api.post(f"{V1}/annual/key-results/{item['id']}/retire", json={})
    retired = await env.api.post(url, json={"value": 5})
    assert retired.status_code == 409 and retired.json()["code"] == "retired"
    assert (await env.api.get(url.replace("/values", "/values"))).json() == []


async def test_values_can_be_entered_in_a_past_year(env: ProjectsEnv) -> None:
    item = await _key_result(env)
    freeze(env.api, datetime(YEAR + 1, 2, 1, 12, tzinfo=UTC))

    stored = await enter_value(env.api, item["id"], 77, f"{YEAR}-12-30")

    assert stored["key_result"]["current_value"] == 77
    assert (await plan(env.api))["editable"] is False


async def test_value_on_a_date_is_the_last_value_on_or_before_it(env: ProjectsEnv) -> None:
    item = await _key_result(env)
    url = f"{V1}/annual/key-results/{item['id']}/value-on"
    await enter_value(env.api, item["id"], 30, f"{YEAR}-02-01")
    await enter_value(env.api, item["id"], 50, f"{YEAR}-04-01")

    before = (await env.api.get(url, params={"date": f"{YEAR}-01-31"})).json()
    assert before == {
        "key_result_id": item["id"],
        "date": f"{YEAR}-01-31",
        "value": None,
        "at": None,
        "source": None,
    }
    on = (await env.api.get(url, params={"date": f"{YEAR}-02-01"})).json()
    assert (on["value"], on["source"]) == (30, "manual")
    assert on["at"].startswith(f"{YEAR}-02-01")
    between = (await env.api.get(url, params={"date": f"{YEAR}-03-15"})).json()
    assert between["value"] == 30
    after = (await env.api.get(url, params={"date": f"{YEAR}-05-01"})).json()
    assert after["value"] == 50
