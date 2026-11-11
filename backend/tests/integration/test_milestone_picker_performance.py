"""Picker volume target: 500 projects load in under one second on SQLite (spec 004, plan)."""

import time

from tefteri.domain.entities import Container, TaskDraft
from tests.conftest import V1
from tests.integration.conftest import ProjectsEnv
from tests.integration.weekly_helpers import WEEK

LIMIT_SECONDS = 1.0


async def test_the_picker_of_500_projects_loads_in_under_a_second(env: ProjectsEnv) -> None:
    backend = env.world.tasks["default"]
    for t in range(25):
        backend.containers.append(Container(f"t{t}", f"Theme {t}"))
        for m in range(19):
            backend.containers.append(Container(f"m{t}-{m}", f"Milestone {t}-{m}", f"t{t}"))
    for t in range(25):
        for m in range(19):
            for n in range(2):
                await backend.create_task(TaskDraft(f"m{t}-{m}", f"Task {t}-{m}-{n}"))
    await env.connect()
    assert len(backend.containers) == 501
    started = time.perf_counter()
    found = await env.api.get(f"{V1}/weekly/{WEEK}/candidates")
    themes = await env.api.get(f"{V1}/weekly/{WEEK}/themes")
    took = time.perf_counter() - started
    assert found.status_code == 200 and themes.status_code == 200
    assert len(found.json()) == 475 + 1  # the nested leaves and Inbox
    assert took < LIMIT_SECONDS, f"the picker took {took:.2f} s"
