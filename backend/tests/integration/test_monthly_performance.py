"""Monthly draft review remains fast for a large completed-milestone month."""

import time
from typing import Any

from tefteri.db.models.milestone import Milestone
from tefteri.db.models.project_label import ProjectLabel as ProjectLabelRow
from tefteri.domain.enums import ProjectLabel
from tests.integration.conftest import ProjectsEnv
from tests.integration.monthly_review_helpers import MONTH, add_key_result, setup_review


async def test_review_of_500_done_milestones_completes_under_three_seconds(
    env: ProjectsEnv, monkeypatch: Any
) -> None:
    rows = await setup_review(env, "Theme 0", "Theme 1", "Theme 2", "Theme 3", "Theme 4")
    user_id = await env.user_id()
    async with env.db() as db:
        projects = [
            ProjectLabelRow(
                user_id=user_id,
                connection_id=env.connection_uuid(),
                remote_id=f"perf-{index}",
                name=f"Milestone {index}",
                label=ProjectLabel.MILESTONE.value,
            )
            for index in range(500)
        ]
        db.add_all(projects)
        await db.flush()
        db.add_all(
            [
                Milestone(
                    user_id=project.user_id,
                    project_id=project.id,
                    state="done",
                    done_on=MONTH,
                    done_by="user",
                    done_theme_id=rows[f"Theme {index % 5}"].id,
                    done_theme_name=f"Theme {index % 5}",
                )
                for index, project in enumerate(projects)
            ]
        )
    await add_key_result(
        env, rows, metric="Automatic metric", themes=("Theme 0",), source="automatic"
    )
    source_calls = []

    def forbidden_source_call(*args: Any, **kwargs: Any) -> Any:
        source_calls.append((args, kwargs))
        raise AssertionError("review attempted to call an automatic key-result source")

    monkeypatch.setattr(env.app.state.connection_service, "backend_for", forbidden_source_call)
    started = time.perf_counter()
    async with env.db() as db:
        draft = await env.app.state.monthly_review_service.draft(
            db, await env.user_id(), MONTH, tz="UTC"
        )
    elapsed = time.perf_counter() - started
    assert sum(theme["done"] for theme in draft.snapshot["themes"]) == 500
    assert elapsed < 3
    assert source_calls == []
