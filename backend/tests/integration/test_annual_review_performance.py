"""Performance of the annual review read model (spec 008, SC-007, R-14)."""

import time
from datetime import UTC, datetime

from tests.integration.conftest import make_snapshot, store_snapshot
from tests.integration.monthly_review_helpers import add_key_result, setup_review

TODAY_AT = datetime(2026, 11, 13, 12, tzinfo=UTC)


async def test_a_large_year_is_built_in_under_500_ms(env) -> None:
    env.app.state.clock = lambda: TODAY_AT
    env.app.state.key_result_service._clock = lambda: TODAY_AT
    names = tuple(f"Theme {n}" for n in range(20))
    rows = await setup_review(env, *names)
    key_results = []
    for n in range(10):
        key_results.append(
            await add_key_result(
                env,
                rows,
                metric=f"Metric {n}",
                themes=names,
                start_value=0,
                target=100,
                year=2025,
                values=((datetime(2025, 1, 1, tzinfo=UTC).date(), 10 + n),),
            )
        )
    user_id = await env.user_id()
    async with env.db() as db:
        for month in range(1, 13):
            await store_snapshot(
                db,
                user_id,
                f"2025-{month:02d}",
                make_snapshot(
                    f"2025-{month:02d}",
                    themes=[
                        {
                            "project_id": str(rows[name].id),
                            "name": name,
                            "target": 1,
                            "done": 1,
                            "status": "in_focus",
                            "milestones": [
                                {
                                    "milestone_id": f"{name}-{month}",
                                    "name": "Ship",
                                    "done_on": f"2025-{month:02d}-08",
                                }
                            ],
                        }
                        for name in names
                    ],
                    categories={
                        "goal_aligned": 20,
                        "maintenance": 10,
                        "off_plan": 5,
                        "hidden": 1,
                    },
                    key_results=[
                        {
                            "key_result_id": str(key_result.id),
                            "start_value": 0,
                            "base_value": 5 + n,
                            "latest_value": 10 + n + month,
                            "latest_at": f"2025-{month:02d}-08T12:00:00Z",
                            "target": 100,
                            "deadline": "2025-12-31",
                            "status": "active",
                            "retired": False,
                        }
                        for n, key_result in enumerate(key_results)
                    ],
                ),
            )
        started = time.perf_counter()
        review = await env.app.state.annual_review_service.review(db, user_id, 2025)
        elapsed = time.perf_counter() - started
    assert len(review["goals"]) == 10
    assert len(review["goals"][0]["key_results"][0]["themes"]) == 20
    assert elapsed < 0.5, f"the review took {elapsed:.3f}s"
