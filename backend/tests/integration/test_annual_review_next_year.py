"""Integration tests of the next-year counts (spec 008, US7)."""

from datetime import UTC, date, datetime

from tests.integration.conftest import make_snapshot, store_snapshot
from tests.integration.monthly_review_helpers import add_key_result, setup_review

TODAY_AT = datetime(2026, 11, 13, 12, tzinfo=UTC)


async def test_next_year_counts_match_planning(env) -> None:
    env.app.state.clock = lambda: TODAY_AT
    env.app.state.key_result_service._clock = lambda: TODAY_AT
    rows = await setup_review(env, "Open source")
    await add_key_result(
        env,
        rows,
        metric="Stars",
        themes=("Open source",),
        start_value=0,
        target=100,
        year=2025,
        values=((date(2025, 11, 1), 40),),
    )
    user_id = await env.user_id()
    async with env.db() as db:
        await store_snapshot(db, user_id, "2025-11", make_snapshot("2025-11"))
        review = await env.app.state.annual_review_service.review(db, user_id, 2025)
        found = await env.app.state.annual_service.suggestions(db, user_id, 2026, from_year=2025)

    offered = [key_result for goal in found for key_result in goal.key_results]
    assert review["next_year"]["unmet_key_results"] == len(offered) == 1
    assert review["next_year"]["links"] == sum(len(k.theme_keys) for k in offered)
    assert review["next_year"]["has_plan"] is True
    assert review["next_year"]["year"] == 2026
    assert review["next_year"]["from_year"] == 2025
