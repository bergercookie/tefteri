"""Counts of a week, a month and a year come from the stored categories (spec 005, M3)."""

import random
from datetime import UTC, date, datetime
from typing import Any

import pytest

from tests.conftest import V1
from tests.integration.conftest import ProjectsEnv
from tests.integration.stats_helpers import NEXT, WEEK, Stats, at

CATEGORY_PROJECT = {"goal_aligned": "p3", "maintenance": "p5", "off_plan": "p9", "hidden": "p7"}


async def _commit_login_flow(s: Stats, week: date = WEEK) -> None:
    await s.add("p3", "Seed")
    await s.weekly.commit(week, "Login flow")


def _sum(parts: list[dict[str, Any]]) -> dict[str, int]:
    out = {"goal_aligned": 0, "maintenance": 0, "off_plan": 0}
    for p in parts:
        for k in out:
            out[k] += p["counts"][k]
    return out


async def test_each_month_is_the_sum_of_its_days_and_each_year_the_sum_of_its_months(
    env: ProjectsEnv,
) -> None:
    s = Stats(env)
    await s.standard()
    rng = random.Random(3)
    n = 0
    for day in range(1, 21):
        for category in rng.choices(list(CATEGORY_PROJECT), k=rng.randint(1, 4)):
            n += 1
            await s.done(CATEGORY_PROJECT[category], f"T{n}", datetime(2030, 3, day, 9, tzinfo=UTC))
    for other in (1, 7, 12):  # other months of the same year, and the year before
        await s.done("p9", f"M{other}", datetime(2030, other, 15, 9, tzinfo=UTC))
    await s.done("p9", "Last year", datetime(2029, 12, 31, 9, tzinfo=UTC))
    await s.sync()

    month = await s.stats("month", date(2030, 3, 10))
    assert month["part_kind"] == "day" and len(month["parts"]) == 31
    assert _sum(month["parts"]) == month["counts"]
    assert sum(p["hidden"] for p in month["parts"]) == month["hidden"]
    assert month["total"] + month["hidden"] == n
    assert (month["start"], month["end"]) == ("2030-03-01", "2030-04-01")

    year = await s.stats("year", date(2030, 6, 1))
    assert year["part_kind"] == "month" and len(year["parts"]) == 12
    assert _sum(year["parts"]) == year["counts"]
    march = next(p for p in year["parts"] if p["start"] == "2030-03-01")
    assert march["counts"] == month["counts"] and march["hidden"] == month["hidden"]
    assert year["total"] == month["total"] + 3  # Jan, July and December
    assert year["hidden"] == month["hidden"]
    assert (year["start"], year["end"]) == ("2030-01-01", "2031-01-01")


async def test_a_week_across_two_months_is_the_sum_of_its_days(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    week = date(2030, 2, 25)  # Monday 25 Feb to Sunday 3 March
    for day in (26, 28):
        await s.done("p9", f"Feb {day}", datetime(2030, 2, day, 9, tzinfo=UTC))
    for day in (1, 3):
        await s.done("p5", f"Mar {day}", datetime(2030, 3, day, 9, tzinfo=UTC))
    await s.done("p9", "Mar 4", datetime(2030, 3, 4, 9, tzinfo=UTC))  # the next week
    await s.sync()
    w = await s.stats("week", week)
    assert w["counts"] == {"goal_aligned": 0, "maintenance": 2, "off_plan": 2}
    assert _sum(w["parts"]) == w["counts"] and len(w["parts"]) == 7
    feb = await s.stats("month", date(2030, 2, 1))
    mar = await s.stats("month", date(2030, 3, 1))
    assert feb["counts"] == {"goal_aligned": 0, "maintenance": 0, "off_plan": 2}
    assert mar["counts"] == {"goal_aligned": 0, "maintenance": 2, "off_plan": 1}


async def test_a_task_counts_once_per_period(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    await s.done("p9", "Once", at(6))
    await s.sync()
    for period in ("week", "month", "year"):
        assert (await s.stats(period, date(2030, 3, 6)))["total"] == 1
    parts = (await s.stats("week", WEEK))["parts"]
    assert sum(p["counts"]["off_plan"] for p in parts) == 1


async def test_counts_always_have_three_keys_and_total_plus_hidden_is_every_task(
    env: ProjectsEnv,
) -> None:
    s = Stats(env)
    await s.standard()
    await s.done("p7", "Only hidden", at(6))
    await s.done("p5", "Only maintenance", at(6))
    await s.sync()
    w = await s.stats("week", WEEK)
    assert w["counts"] == {"goal_aligned": 0, "maintenance": 1, "off_plan": 0}
    assert set(w["percentages"]) == {"goal_aligned", "maintenance", "off_plan"}
    assert w["total"] + w["hidden"] == 2


async def test_a_week_of_only_maintenance_is_zero_n_zero_and_zero_100_zero(
    env: ProjectsEnv,
) -> None:
    s = Stats(env)
    await s.standard()
    for i in range(4):
        await s.done("p5", f"Chore {i}", at(4 + i))
    await s.sync()
    w = await s.stats("week", WEEK)
    assert w["counts"] == {"goal_aligned": 0, "maintenance": 4, "off_plan": 0}
    assert w["percentages"] == {"goal_aligned": 0, "maintenance": 100, "off_plan": 0}


async def test_one_task_in_a_hundred_shows_count_one_and_percentage_one(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    await _commit_login_flow(s)
    await s.done("p3", "The one", at(5))
    for i in range(99):
        await s.done("p5", f"Chore {i}", at(5))
    await s.sync()
    w = await s.stats("week", WEEK)
    assert w["counts"]["goal_aligned"] == 1 and w["percentages"]["goal_aligned"] == 1
    assert w["percentages"]["maintenance"] == 99


@pytest.mark.parametrize("seed", range(10))
async def test_the_percentages_add_up_to_100_for_seeded_mixes(env: ProjectsEnv, seed: int) -> None:
    s = Stats(env)
    await s.standard()
    await _commit_login_flow(s)
    rng = random.Random(seed)
    n = 0
    for category in ("goal_aligned", "maintenance", "off_plan"):
        for _ in range(rng.randint(0, 12)):
            n += 1
            await s.done(CATEGORY_PROJECT[category], f"T{n}", at(rng.randint(4, 10)))
    if n == 0:
        await s.done("p9", "Single", at(4))
    await s.sync()
    w = await s.stats("week", WEEK)
    assert sum(w["percentages"].values()) == 100


async def test_the_hidden_count_is_not_in_the_total_or_the_percentages(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    await s.done("p9", "Counted", at(5))
    for i in range(5):
        await s.done("p7", f"Hidden {i}", at(5))
    await s.sync()
    w = await s.stats("week", WEEK)
    assert (w["total"], w["hidden"]) == (1, 5)
    assert w["percentages"] == {"goal_aligned": 0, "maintenance": 0, "off_plan": 100}


async def test_a_period_with_no_task_has_zero_counts_and_is_empty(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    w = await s.stats("week", WEEK)
    assert w["counts"] == {"goal_aligned": 0, "maintenance": 0, "off_plan": 0}
    assert w["percentages"] == {"goal_aligned": 0, "maintenance": 0, "off_plan": 0}
    assert w["empty"] == {"reason": "no_tasks", "action": "plan_week"}


# -- the cases that moved here from the weekly tests (done_outside_plan is gone) ------------------


async def test_tasks_done_outside_the_plan_are_off_plan_with_their_day(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    await s.add("p3", "p3 task 1")
    await s.add("p3", "p3 task 2")
    await s.weekly.commit(WEEK, "Login flow")
    assert await s.titles() == []  # nothing is done yet

    s.finish("p3 task 1", at(5))  # a task of the plan: goal-aligned
    await s.done("p9", "p9 task 1", at(6, 9))  # another project: off-plan
    await s.done("p3", "Added later", at(4, 8))  # a task of the project after the commit
    await s.sync()
    # Not in the week: done another week, done with no time, still open.
    s.finish("p3 task 2", at(12, 9))
    await s.done("p9", "No time", None)
    await s.sync()

    items = await s.all_tasks(period="week", day=str(WEEK))
    got = {(t["title"], t["completed_day"], t["project"]["name"], t["category"]) for t in items}
    assert got == {
        ("p3 task 1", "2030-03-05", "Login flow", "goal_aligned"),
        ("Added later", "2030-03-04", "Login flow", "goal_aligned"),
        ("p9 task 1", "2030-03-06", "Misc", "off_plan"),
    }
    assert [t["title"] for t in await s.all_tasks(period="week", day=str(NEXT))] == ["p3 task 2"]


async def test_the_week_follows_the_time_zone_of_the_user(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    me = (await env.api.get(f"{V1}/auth/me")).json()
    await env.api.patch(f"{V1}/users/{me['id']}", json={"timezone": "Europe/Athens"})
    # Sunday 22:30 UTC before the week is Monday 00:30 in Athens: it belongs to the week.
    await s.done("p9", "Starts the week", datetime(2030, 3, 3, 22, 30, tzinfo=UTC))
    # Sunday 22:30 UTC at the end of the week is Monday 00:30 in Athens: the next week.
    await s.done("p9", "Starts the next", datetime(2030, 3, 10, 22, 30, tzinfo=UTC))
    await s.sync()
    assert await s.titles("off_plan") == ["Starts the week"]
    assert await s.titles("off_plan", NEXT) == ["Starts the next"]
    first = (await s.all_tasks(period="week", day=str(WEEK)))[0]
    assert first["completed_day"] == "2030-03-04"


async def test_a_draft_plan_commits_nothing_and_a_routine_is_maintenance_without_one(
    env: ProjectsEnv,
) -> None:
    s = Stats(env)
    await s.standard()
    await s.weekly.add(WEEK, "Login flow")  # a draft
    await s.done("p3", "In a milestone", at(6))
    await s.done("p5", "In a routine", at(6))
    await s.sync()
    by_title = {t["title"]: t for t in await s.all_tasks(period="week", day=str(WEEK))}
    assert by_title["In a milestone"]["category"] == "off_plan"
    assert by_title["In a routine"]["category"] == "maintenance"
    # A week with no plan at all has the same rule.
    await s.done("p3", "No plan", at(20))
    await s.sync()
    (only,) = await s.all_tasks(period="week", day=str(date(2030, 3, 18)))
    assert only["category"] == "off_plan"


# -- empty states, sync and availability ----------------------------------------------------------


async def test_empty_is_null_with_a_counted_or_a_hidden_task(env: ProjectsEnv) -> None:
    s = Stats(env)
    await s.standard()
    await s.done("p9", "Counted", at(5))
    await s.done("p7", "Hidden", at(12))
    await s.sync()
    assert (await s.stats("week", WEEK))["empty"] is None
    assert (await s.stats("week", NEXT))["empty"] is None  # only a hidden task


async def test_no_labels_has_its_own_reason_and_action(env: ProjectsEnv) -> None:
    s = Stats(env)
    await env.connect()  # nothing is labelled
    w = await s.stats("week", WEEK)
    assert w["empty"] == {"reason": "no_labels", "action": "label_projects"}
    await s.weekly.label(Inbox="theme")
    assert (await s.stats("week", WEEK))["empty"] == {"reason": "no_tasks", "action": "plan_week"}


async def test_the_sync_block_is_the_newest_run_and_the_numbers_stay_after_a_failure(
    env: ProjectsEnv,
) -> None:
    s = Stats(env)
    await s.standard()
    await s.done("p9", "Counted", at(5))
    await s.sync()
    ok = await s.stats("week", WEEK)
    assert ok["sync"]["outcome"] == "ok" and ok["sync"]["last_synced_at"].endswith("Z")
    s.backend.unavailable = True
    await s.sync()  # the sync fails; the numbers stay the last stored ones
    failed = await s.stats("week", WEEK)
    assert failed["sync"]["outcome"] == "unreachable"
    assert failed["counts"] == ok["counts"] and failed["total"] == 1
    s.backend.unavailable = False
    s.backend.auth_expired = True
    await s.sync()
    assert (await s.stats("week", WEEK))["sync"]["outcome"] == "auth_expired"


async def test_never_synced_has_no_time_and_no_outcome(env: ProjectsEnv) -> None:
    w = await Stats(env).stats("week", WEEK)
    assert w["sync"] == {"last_synced_at": None, "outcome": None}


async def test_an_unavailable_commitment_gives_zero_numbers_and_the_reason(
    env: ProjectsEnv,
) -> None:
    s = Stats(env)
    await s.standard()
    await s.done("p9", "Counted", at(5))
    await s.sync()

    class Unavailable:
        async def committed_projects(self, db: object, user_id: object, week_start: date) -> None:
            return None

    env.app.state.statistics_service._commitments = Unavailable()  # noqa: SLF001
    for period in ("week", "month", "year"):
        w = await s.stats(period, WEEK)
        assert (
            w["available"] is False and w["unavailable_reason"] == "weekly_commitment_unavailable"
        )
        assert w["counts"] == {"goal_aligned": 0, "maintenance": 0, "off_plan": 0}
        assert w["total"] == 0 and w["hidden"] == 0 and w["empty"] is None
        assert w["progress"] is None and _sum(w["parts"]) == w["counts"]
    ok = (await s.stats("week", WEEK))["parts"]
    assert len(ok) == 7
