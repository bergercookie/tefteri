"""Monthly review snapshots are immutable records with a mutable current-version pointer."""

import re
from datetime import date
from typing import Any, cast

from sqlalchemy import select

from tefteri.db.models.milestone import Milestone
from tefteri.db.models.monthly import MonthlyReview, MonthlyReviewSnapshot
from tefteri.db.models.project_label import ProjectLabel as ProjectLabelRow
from tefteri.db.models.task import Task
from tefteri.services.errors import ConfirmRequired, NoSuchVersion
from tests.integration.conftest import ProjectsEnv
from tests.integration.monthly_review_helpers import MONTH, add_milestone, setup_review


async def test_snapshot_read_versions_current_pointer_and_current_snapshots(
    env: ProjectsEnv,
) -> None:
    rows = await setup_review(env, "Theme")
    done = await add_milestone(env, "Ship feature", done_on=MONTH, theme_name="Theme")
    async with env.db() as db:
        task = Task(
            user_id=await env.user_id(),
            connection_id=env.connection_uuid(),
            container_id=None,
            remote_id="snapshot-task",
            title="A task that is later removed",
        )
        db.add(task)
    service = env.app.state.monthly_review_service
    user_id = await env.user_id()
    async with env.db() as db:
        unreviewed = await service.review(db, user_id, MONTH)
    assert unreviewed.snapshot["month"] == MONTH.isoformat()
    async with env.db() as db:
        assert await db.scalar(select(MonthlyReview.id)) is None
    async with env.db() as db:
        first = await service.store(
            db,
            user_id,
            MONTH,
            tz="UTC",
            decisions=[{"project_id": rows["Theme"].id, "decision": "carry"}],
        )
    original = first.snapshot
    async with env.db() as db:
        project = await db.get(ProjectLabelRow, rows["Theme"].id)
        milestone = await db.get(Milestone, done.id)
        task = (
            await db.execute(select(Task).where(Task.remote_id == "snapshot-task"))
        ).scalar_one()
        assert project is not None and milestone is not None
        project.name = "Renamed theme"
        project.label = "maintenance"
        project.orphaned_reason = "missing"
        milestone.done_on = None
        await db.delete(task)
    async with env.db() as db:
        stored_while_live_data_changed = await service.review(db, user_id, MONTH)
    assert stored_while_live_data_changed.snapshot == original
    try:
        async with env.db() as db:
            await service.store(db, user_id, MONTH, tz="UTC")
    except ConfirmRequired:
        pass
    else:
        raise AssertionError("saving a second version must require confirmation")
    async with env.db() as db:
        second = await service.store(db, user_id, MONTH, tz="UTC", confirm_new_version=True)
    assert second.version == 2
    assert first.snapshot == original
    versions = await _versions(env, service, MONTH)
    assert [item.version for item in versions] == [1, 2]
    assert versions[0].taken_at is not None

    original_draft = service.draft

    async def no_recalculation(*args: Any, **kwargs: Any) -> Any:
        raise AssertionError("stored review read recalculated live data")

    service.draft = no_recalculation
    async with env.db() as db:
        stored = await service.review(db, user_id, MONTH)
    assert stored.snapshot == second.snapshot
    async with env.db() as db:
        current = await service.current_snapshots(db, user_id, MONTH.year)
    assert len(current) == 1 and current[0]["snapshot"] == second.snapshot

    async with env.db() as db:
        await service.make_current(db, user_id, MONTH, 1)
    async with env.db() as db:
        header = (
            await db.execute(
                select(MonthlyReview).where(
                    MonthlyReview.user_id == user_id, MonthlyReview.month == MONTH
                )
            )
        ).scalar_one()
        snapshots = list(
            (
                await db.execute(
                    select(MonthlyReviewSnapshot)
                    .where(MonthlyReviewSnapshot.review_id == header.id)
                    .order_by(MonthlyReviewSnapshot.version)
                )
            ).scalars()
        )
    assert header.current_version == 1
    assert [item.payload for item in snapshots] == [original, second.snapshot]
    async with env.db() as db:
        read_current = await service.review(db, user_id, MONTH)
    assert read_current.snapshot == original
    service.draft = original_draft
    async with env.db() as db:
        third = await service.store(db, user_id, MONTH, tz="UTC", confirm_new_version=True)
    assert third.version == 3
    try:
        async with env.db() as db:
            await service.make_current(db, user_id, MONTH, 99)
    except NoSuchVersion:
        pass
    else:
        raise AssertionError("unknown versions must be refused")


async def test_snapshot_source_has_no_snapshot_update_or_delete(env: ProjectsEnv) -> None:
    del env
    from pathlib import Path

    source = Path(__file__).parents[2] / "src"
    for path in source.rglob("*.py"):
        text = path.read_text()
        assert not re.search(
            r"(?:update|delete)\s*\([^)]*MonthlyReviewSnapshot|"
            r"(?:update|delete)\s*\(\s*MonthlyReviewSnapshot",
            text,
            re.IGNORECASE,
        ), path


async def _versions(env: ProjectsEnv, service: Any, month: date) -> list[Any]:
    async with env.db() as db:
        return cast(list[Any], await service.versions(db, await env.user_id(), month))
