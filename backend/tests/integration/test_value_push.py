"""The inbound value push (spec 006, US7, FR-010, SC-007, contract section 4)."""

from collections.abc import AsyncIterator, Awaitable, Callable
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import func, select

from tefteri.db.models.key_result import KeyResultValue
from tefteri.domain.entities import Container
from tests.conftest import V1
from tests.integration.annual_helpers import (
    NOW,
    YEAR,
    bare_client,
    create_goal,
    freeze,
    key_result_of,
    kr,
    plan,
)
from tests.integration.conftest import ProjectsEnv

AT = "2030-07-01T09:30:00Z"


@pytest.fixture
async def source(env: ProjectsEnv) -> AsyncIterator[AsyncClient]:
    """An outside source: a client with no session and no client header."""
    client = bare_client(env.api)
    yield client
    await client.aclose()


async def _setup(env: ProjectsEnv) -> dict[str, Any]:
    freeze(env.api)
    await env.connect(Container("p2", "Unused"))
    goal = await create_goal(
        env.api,
        "Open source",
        kr("Stars", start=100, target=500, source="automatic"),
        kr("Talks", start=0, target=2),
    )
    token = (await env.api.post(f"{V1}/annual/push-token")).json()
    return {"auto": goal["key_results"][0], "manual": goal["key_results"][1], **token}


def _push(
    client: AsyncClient, key_result_id: str, token: str | None, body: Any = None
) -> Awaitable[Any]:
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    return client.post(
        f"{V1}/key-results/{key_result_id}/push",
        json={"value": 1342, "at": AT} if body is None else body,
        headers=headers,
    )


async def _stored(env: ProjectsEnv) -> int:
    async with env.db() as db:
        return (await db.execute(select(func.count()).select_from(KeyResultValue))).scalar_one()


async def test_a_valid_push_is_stored_and_is_the_current_value_at_once(
    env: ProjectsEnv, source: AsyncClient
) -> None:
    s = await _setup(env)

    response = await _push(source, s["auto"]["id"], s["token"])

    assert response.status_code == 201, response.text
    body = response.json()
    assert body["stored"] is True
    assert (body["key_result_id"], body["value"], body["current_value"]) == (
        s["auto"]["id"],
        1342,
        1342,
    )
    assert datetime.fromisoformat(body["at"]) == datetime(2030, 7, 1, 9, 30, tzinfo=UTC)
    item = key_result_of(await plan(env.api), s["auto"]["id"])
    assert item["current_value"] == 1342
    series = (await env.api.get(f"{V1}/annual/key-results/{s['auto']['id']}/values")).json()
    assert [(p["value"], p["source"]) for p in series] == [(1342, "automatic")]


async def test_an_identical_retry_answers_200_and_stores_nothing_new(
    env: ProjectsEnv, source: AsyncClient
) -> None:
    s = await _setup(env)
    assert (await _push(source, s["auto"]["id"], s["token"])).status_code == 201

    again = await _push(source, s["auto"]["id"], s["token"])
    same_instant = await _push(
        source, s["auto"]["id"], s["token"], {"value": 1342, "at": "2030-07-01T11:30:00+02:00"}
    )

    assert again.status_code == 200 and again.json()["stored"] is False
    assert same_instant.status_code == 200 and same_instant.json()["stored"] is False
    assert await _stored(env) == 1


async def test_tokens_that_are_missing_wrong_rotated_or_deleted_are_refused(
    env: ProjectsEnv, source: AsyncClient
) -> None:
    s = await _setup(env)
    kr_id = s["auto"]["id"]

    for token in (None, "tfv_wrong", s["token"][:-1]):
        response = await _push(source, kr_id, token)
        assert response.status_code == 401
        assert response.json()["code"] == "invalid_push_token"
    not_bearer = await source.post(
        f"{V1}/key-results/{kr_id}/push",
        json={"value": 1, "at": AT},
        headers={"Authorization": s["token"]},
    )
    assert not_bearer.status_code == 401

    rotated = (await env.api.post(f"{V1}/annual/push-token")).json()
    assert (await _push(source, kr_id, s["token"])).status_code == 401
    assert (await _push(source, kr_id, rotated["token"])).status_code == 201

    assert (await env.api.delete(f"{V1}/annual/push-token")).status_code == 204
    assert (await _push(source, kr_id, rotated["token"])).status_code == 401
    assert (await env.api.get(f"{V1}/annual/push-token")).json() == {"exists": False}
    assert await _stored(env) == 1


async def test_a_session_is_not_a_push_token_and_a_push_token_is_not_a_session(
    env: ProjectsEnv, source: AsyncClient
) -> None:
    s = await _setup(env)
    session = env.api.headers["Authorization"].removeprefix("Bearer ")

    assert (await _push(source, s["auto"]["id"], session)).status_code == 401
    # The session client itself has a session, but no push token in its header.
    assert (await _push(env.api, s["auto"]["id"], session)).status_code == 401
    as_session = await source.get(
        f"{V1}/annual/{YEAR}", headers={"Authorization": f"Bearer {s['token']}"}
    )
    assert as_session.status_code == 401
    assert await _stored(env) == 0


async def test_unknown_and_foreign_key_results_both_answer_404(
    env: ProjectsEnv,
    source: AsyncClient,
    make_user: Callable[[str], Awaitable[AsyncClient]],
) -> None:
    s = await _setup(env)
    other = await make_user("bob")
    theirs = await create_goal(other, "Theirs", kr("Other", source="automatic"))

    foreign = await _push(source, theirs["key_results"][0]["id"], s["token"])
    unknown = await _push(source, "00000000-0000-0000-0000-000000000001", s["token"])

    assert (foreign.status_code, foreign.json()["code"]) == (404, "not_found")
    assert (unknown.status_code, unknown.json()) == (404, foreign.json())
    assert await _stored(env) == 0


async def test_retired_and_manual_key_results_refuse_a_push(
    env: ProjectsEnv, source: AsyncClient
) -> None:
    s = await _setup(env)

    manual = await _push(source, s["manual"]["id"], s["token"])
    await env.api.post(f"{V1}/annual/key-results/{s['auto']['id']}/retire", json={})
    retired = await _push(source, s["auto"]["id"], s["token"])

    assert (manual.status_code, manual.json()["code"]) == (409, "not_automatic")
    assert (retired.status_code, retired.json()["code"]) == (409, "retired")
    assert await _stored(env) == 0


@pytest.mark.parametrize(
    "body",
    [
        {"value": "1342", "at": AT},
        {"value": True, "at": AT},
        {"value": None, "at": AT},
        {"at": AT},
        {"value": 1342},
        {"value": 1342, "at": "2030-07-01T09:30:00"},
        {"value": 1342, "at": "yesterday"},
        {"value": 1342, "at": (NOW + timedelta(minutes=6)).isoformat()},
    ],
)
async def test_bad_values_and_time_stamps_answer_422_and_store_nothing(
    env: ProjectsEnv, source: AsyncClient, body: dict[str, Any]
) -> None:
    s = await _setup(env)

    response = await _push(source, s["auto"]["id"], s["token"], body)

    assert response.status_code == 422, response.text
    assert response.json()["code"] == "invalid"
    assert await _stored(env) == 0


@pytest.mark.parametrize("literal", [b"NaN", b"Infinity", b"-Infinity"])
async def test_nan_and_infinity_are_refused(
    env: ProjectsEnv, source: AsyncClient, literal: bytes
) -> None:
    s = await _setup(env)

    response = await source.post(
        f"{V1}/key-results/{s['auto']['id']}/push",
        content=b'{"value": ' + literal + b', "at": "' + AT.encode() + b'"}',
        headers={"Authorization": f"Bearer {s['token']}", "Content-Type": "application/json"},
    )

    assert response.status_code == 422
    assert await _stored(env) == 0


async def test_a_small_clock_skew_is_accepted(env: ProjectsEnv, source: AsyncClient) -> None:
    s = await _setup(env)

    response = await _push(
        source,
        s["auto"]["id"],
        s["token"],
        {"value": 5, "at": (NOW + timedelta(minutes=4)).isoformat()},
    )

    assert response.status_code == 201


async def test_the_61st_push_in_a_minute_is_rate_limited(
    env: ProjectsEnv, source: AsyncClient
) -> None:
    s = await _setup(env)
    for n in range(60):
        at = (NOW - timedelta(seconds=n)).isoformat()
        response = await _push(source, s["auto"]["id"], s["token"], {"value": n, "at": at})
        assert response.status_code == 201, response.text

    limited = await _push(source, s["auto"]["id"], s["token"], {"value": 999, "at": AT})

    assert limited.status_code == 429
    assert limited.json()["code"] == "rate_limited"
    assert int(limited.headers["Retry-After"]) > 0
    assert await _stored(env) == 60

    freeze(env.api, NOW + timedelta(minutes=1, seconds=1))
    assert (
        await _push(source, s["auto"]["id"], s["token"], {"value": 999, "at": AT})
    ).status_code == 201


async def test_a_push_to_a_key_result_of_a_past_year_is_stored(
    env: ProjectsEnv, source: AsyncClient
) -> None:
    s = await _setup(env)
    freeze(env.api, datetime(YEAR + 1, 1, 5, tzinfo=UTC))

    response = await _push(source, s["auto"]["id"], s["token"])

    assert response.status_code == 201
    assert (await plan(env.api))["state"] == "past"


async def test_last_used_is_set_only_by_an_accepted_push(
    env: ProjectsEnv, source: AsyncClient
) -> None:
    s = await _setup(env)
    status = (await env.api.get(f"{V1}/annual/push-token")).json()
    assert status["exists"] is True and status["hint"] == s["hint"] == s["token"][-4:]
    assert status["last_used_at"] is None
    assert "token" not in status

    await _push(source, s["manual"]["id"], s["token"])
    assert (await env.api.get(f"{V1}/annual/push-token")).json()["last_used_at"] is None

    await _push(source, s["auto"]["id"], s["token"])
    used = (await env.api.get(f"{V1}/annual/push-token")).json()["last_used_at"]
    assert used is not None and used.startswith("2030-07-01")
