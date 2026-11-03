"""Planner list speed: 2,000 tasks, filtered or searched, stay under 200 ms p95.

The time is CPU time of the process, so a busy machine does not fail the test.
"""

import gc
import statistics
import time
from datetime import UTC, datetime, timedelta

from httpx import AsyncClient

from tefteri.domain.entities import RemoteTask
from tests.conftest import V1, connect_all
from tests.fakes.world import FakeWorld

LIMIT_SECONDS = 0.2
RUNS = 20


async def _p95(api: AsyncClient, path: str, params: dict[str, str]) -> float:
    # Warm up and collect garbage first. Earlier tests leave a large heap that the collector
    # would rescan, and a pause inside one sample says nothing about the endpoint itself.
    assert (await api.get(path, params=params)).status_code == 200
    gc.collect()
    gc.freeze()
    try:
        samples = []
        for _ in range(RUNS):
            began = time.process_time()
            r = await api.get(path, params=params)
            samples.append(time.process_time() - began)
            assert r.status_code == 200
    finally:
        gc.unfreeze()
    return statistics.quantiles(samples, n=20)[-1]


async def test_filtered_and_searched_lists_stay_fast(api: AsyncClient, world: FakeWorld) -> None:
    start = datetime.now(UTC).replace(microsecond=0) - timedelta(days=30)
    tasks = world.tasks["default"]
    for i in range(2000):
        due = start + timedelta(hours=i) if i % 5 else None
        tasks.tasks[f"t{i}"] = RemoteTask(f"t{i}", "p1", f"Task number {i}", "v1", due_at=due)
    await connect_all(api)
    assert (await api.post(f"{V1}/sync")).status_code == 200

    cases = [
        (f"{V1}/tasks", {"due": "week"}),
        (f"{V1}/tasks", {"due": "overdue"}),
        (f"{V1}/tasks", {"due": "all"}),
        (f"{V1}/tasks", {"q": "number 19"}),
        (f"{V1}/tasks/counts", {}),
    ]
    for path, params in cases:
        p95 = await _p95(api, path, params)
        assert p95 < LIMIT_SECONDS, f"{path} {params}: p95 {p95 * 1000:.0f} ms"
