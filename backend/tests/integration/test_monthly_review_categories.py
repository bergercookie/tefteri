"""Category counts and trend come from the injected feature-005 reader."""

from datetime import date
from typing import Any

from tefteri.domain.monthly import CategoryCounts
from tefteri.domain.work_categories import CategoryCounts as WorkCategoryCounts
from tefteri.services.monthly_review import StatisticsCategoryCountsReader
from tests.integration.conftest import ProjectsEnv
from tests.integration.monthly_review_helpers import MONTH, previous_month, setup_review


class FakeCategoryCountsReader:
    """Return fixed work-category counts for selected months."""

    def __init__(self, counts: dict[date, CategoryCounts | None]) -> None:
        self.counts = counts
        self.calls: list[date] = []

    async def month_counts(self, db: Any, user_id: Any, month_start: date) -> CategoryCounts | None:
        self.calls.append(month_start)
        return self.counts.get(month_start)


async def test_review_keeps_reader_counts_and_computes_only_trend_shares(
    env: ProjectsEnv,
) -> None:
    await setup_review(env, "Theme")
    reader = FakeCategoryCountsReader(
        {
            MONTH: CategoryCounts(4, 6, 8, 3),
            previous_month(MONTH, 1): CategoryCounts(8, 8, 2, 1),
            previous_month(MONTH, 2): CategoryCounts(8, 8, 1, 0),
        }
    )
    service = env.app.state.monthly_review_service
    service._category_reader = reader
    async with env.db() as db:
        draft = await service.draft(db, await env.user_id(), MONTH, tz="UTC")
    assert draft.snapshot["categories"] == {
        "goal_aligned": 4,
        "maintenance": 6,
        "off_plan": 8,
        "hidden": 3,
    }
    assert draft.trend.state == "rising"
    assert set(reader.calls) == {
        MONTH,
        previous_month(MONTH, 1),
        previous_month(MONTH, 2),
    }
    assert not _has_forbidden_keys(draft.snapshot)
    assert draft.trend.share == 8 / 18


async def test_no_category_data_has_no_share_and_two_months_are_required(
    env: ProjectsEnv,
) -> None:
    await setup_review(env, "Theme")
    reader = FakeCategoryCountsReader(
        {
            MONTH: CategoryCounts(0, 0, 0, 0),
            previous_month(MONTH, 1): CategoryCounts(0, 10, 0, 0),
            previous_month(MONTH, 2): None,
        }
    )
    service = env.app.state.monthly_review_service
    service._category_reader = reader
    async with env.db() as db:
        draft = await service.draft(db, await env.user_id(), MONTH, tz="UTC")
    assert draft.trend.share is None
    assert draft.trend.state == "not_enough_history"
    assert draft.trend.previous[1]["share"] is None


async def test_one_missing_prior_month_prevents_a_trend(env: ProjectsEnv) -> None:
    await setup_review(env, "Theme")
    reader = FakeCategoryCountsReader(
        {
            MONTH: CategoryCounts(0, 0, 3, 0),
            previous_month(MONTH, 1): CategoryCounts(3, 0, 0, 0),
            previous_month(MONTH, 2): None,
        }
    )
    service = env.app.state.monthly_review_service
    service._category_reader = reader
    async with env.db() as db:
        draft = await service.draft(db, await env.user_id(), MONTH, tz="UTC")
    assert draft.trend.state == "not_enough_history"


async def test_high_steady_maintenance_share_is_not_flagged(env: ProjectsEnv) -> None:
    await setup_review(env, "Theme")
    steady = CategoryCounts(1, 100, 1, 4)
    reader = FakeCategoryCountsReader(
        {
            MONTH: steady,
            previous_month(MONTH, 1): steady,
            previous_month(MONTH, 2): steady,
        }
    )
    service = env.app.state.monthly_review_service
    service._category_reader = reader
    async with env.db() as db:
        draft = await service.draft(db, await env.user_id(), MONTH, tz="UTC")
    assert draft.trend.state == "not_rising"


async def test_statistics_reader_adapts_summary_counts_without_recalculation(
    env: ProjectsEnv,
) -> None:
    await setup_review(env, "Theme")
    user_id = await env.user_id()

    class FakeStatisticsService:
        calls: list[tuple[Any, ...]] = []

        async def summary(
            self,
            db: Any,
            uid: Any,
            tz: Any,
            period: Any,
            start: Any,
            today: Any,
        ) -> Any:
            self.calls.append((uid, tz, period, start, today))

            class Summary:
                available = True
                counts = WorkCategoryCounts(2, 4, 6, 3)

            return Summary()

    statistics = FakeStatisticsService()
    reader = StatisticsCategoryCountsReader(
        statistics,  # type: ignore[arg-type]
        clock=lambda: env.app.state.clock(),
    )
    async with env.db() as db:
        counts = await reader.month_counts(db, user_id, MONTH)
    assert counts == CategoryCounts(2, 4, 6, 3)
    assert len(statistics.calls) == 1
    assert statistics.calls[0][3] == MONTH


def _has_forbidden_keys(value: object) -> bool:
    if isinstance(value, dict):
        return any(
            any(
                term in str(key).lower()
                for term in ("share", "percent", "hours", "duration", "effort")
            )
            or _has_forbidden_keys(item)
            for key, item in value.items()
        )
    if isinstance(value, list):
        return any(_has_forbidden_keys(item) for item in value)
    return False
