"""Planning and review service calls do not write to task-app adapters."""

from datetime import date
from typing import Any

from sqlalchemy import func, select

from tefteri.db.models.key_result import KeyResultValue
from tefteri.db.models.project_label import ProjectLabel as ProjectLabelRow
from tefteri.db.models.task import Task
from tests.integration.conftest import ProjectsEnv
from tests.integration.monthly_review_helpers import MONTH, TODAY, add_key_result, setup_review


async def test_monthly_services_make_no_task_app_write_calls(env: ProjectsEnv) -> None:
    rows = await setup_review(env, "Theme", "Replacement")
    async with env.db() as db:
        initial_labels = await db.scalar(select(func.count()).select_from(ProjectLabelRow))
        initial_tasks = await db.scalar(select(func.count()).select_from(Task))
    current = date(TODAY.year, TODAY.month, 1)
    focus = env.app.state.monthly_focus_service
    async with env.db() as db:
        await focus.save_plan(
            db,
            await env.user_id(),
            current,
            [(rows["Theme"].id, 3)],
            tz="UTC",
        )
    backend = env.world.tasks["default"]
    calls: list[str] = []
    for method_name in (
        "create_container",
        "rename_container",
        "archive_container",
        "create_task",
        "update_task",
        "move_task",
        "set_reminder",
    ):
        original = getattr(backend, method_name)

        async def record(*args: Any, _name: str = method_name, _original=original, **kwargs: Any):
            calls.append(_name)
            return await _original(*args, **kwargs)

        setattr(backend, method_name, record)

    async with env.db() as db:
        await focus.plan(db, await env.user_id(), current, tz="UTC")
        await focus.change(
            db,
            await env.user_id(),
            current,
            kind="target",
            out_project_id=rows["Theme"].id,
            target=4,
            dry_run=True,
            tz="UTC",
        )
        await env.app.state.monthly_review_service.draft(db, await env.user_id(), MONTH, tz="UTC")
    key_result = await add_key_result(
        env, rows, metric="Manual", themes=("Theme",), source="manual"
    )
    async with env.db() as db:
        await env.app.state.monthly_review_service.store(
            db,
            await env.user_id(),
            MONTH,
            tz="UTC",
            key_result_values={key_result.id: 20},
        )
    assert calls == []
    async with env.db() as db:
        user_id = await env.user_id()
        assert await db.scalar(select(func.count()).select_from(Task)) == initial_tasks
        assert (
            await db.scalar(
                select(func.count())
                .select_from(ProjectLabelRow)
                .where(ProjectLabelRow.user_id == user_id)
            )
            == initial_labels
        )
        assert (
            await db.scalar(
                select(func.count())
                .select_from(KeyResultValue)
                .where(KeyResultValue.key_result_id == key_result.id)
            )
            == 1
        )
