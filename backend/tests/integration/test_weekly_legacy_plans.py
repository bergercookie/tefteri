"""Plans saved before milestones open under the new names and are never rewritten (SC-008)."""

import uuid
from datetime import UTC, date, datetime
from typing import Any

from sqlalchemy import select

from tefteri.db.models.project_label import ProjectLabel as ProjectLabelRow
from tefteri.db.models.weekly import WeeklyPlan, WeeklyPlanProject
from tefteri.domain.entities import Container
from tests.conftest import V1
from tests.integration.conftest import ProjectsEnv
from tests.integration.weekly_helpers import Weekly

OLD = date(2026, 11, 2)
AFTER_OLD = date(2026, 11, 9)


async def _seed(env: ProjectsEnv) -> None:
    """A reviewed plan as the code before spec 004 stored it: carry, backlog, no choice."""
    await env.connect(
        Container("p2", "Website"), Container("p3", "Garden"), tasks={"p2": 2, "p3": 2}
    )
    weekly = Weekly(env)
    user = await env.user_id()
    async with env.db() as db:
        plan = WeeklyPlan(
            user_id=user,
            week_start=OLD,
            status="committed",
            committed_at=datetime(2026, 11, 2, 8, tzinfo=UTC),
            reviewed_at=datetime(2026, 11, 9, 8, tzinfo=UTC),
            reflection="Old week.",
            retro_skipped=False,
        )
        db.add(plan)
        await db.flush()
        for n, (name, action, outcome, done) in enumerate(
            [
                ("Website", "carry", "not_done", 1),
                ("Garden", "backlog", "not_done", 0),
                ("Gone", None, "done", 2),
            ]
        ):
            container_id = None if name == "Gone" else uuid.UUID(await weekly.cid(name))
            db.add(
                WeeklyPlanProject(
                    plan_id=plan.id,
                    container_id=container_id,
                    name=name,
                    position=n,
                    created_here=False,
                    committed_task_ids=[],
                    outcome=outcome,
                    leftover_action=action,
                    reviewed_committed=2,
                    reviewed_done=done,
                )
            )


async def _snapshot(env: ProjectsEnv) -> list[dict[str, Any]]:
    async with env.db() as db:
        rows = (
            await db.execute(select(WeeklyPlanProject).order_by(WeeklyPlanProject.name))
        ).scalars()
        return [
            {c.name: getattr(r, c.name) for c in WeeklyPlanProject.__table__.columns} for r in rows
        ]


async def test_an_old_week_loads_with_its_choices_under_the_new_names(env: ProjectsEnv) -> None:
    await _seed(env)
    weekly = Weekly(env)
    back = (await weekly.state(AFTER_OLD))["look_back"]
    assert back["reviewed"] is True and back["reflection"] == "Old week."
    entries = {p["name"]: p for p in back["projects"]}
    assert (entries["Website"]["decision"], entries["Website"]["legacy"]) == ("recommit", True)
    assert (entries["Garden"]["decision"], entries["Garden"]["legacy"]) == ("park", True)
    assert (entries["Gone"]["decision"], entries["Gone"]["legacy"]) == (None, True)
    assert (entries["Website"]["committed"], entries["Website"]["done"]) == (2, 1)
    assert entries["Website"]["outcome"] == "not_done" and entries["Gone"]["outcome"] == "done"
    assert entries["Website"]["milestone_id"] is None and entries["Website"]["close"] is None
    assert "leftover_action" not in entries["Website"]


async def test_the_history_shows_the_old_choices_and_counts(env: ProjectsEnv) -> None:
    await _seed(env)
    history = (await env.api.get(f"{V1}/weekly/history")).json()
    (entry,) = history["entries"]
    assert (entry["committed_projects"], entry["done_projects"]) == (3, 1)
    assert (entry["committed_tasks"], entry["done_tasks"]) == (6, 3)
    shown = {p["name"]: (p["decision"], p["legacy"], p["done"]) for p in entry["projects"]}
    assert shown == {
        "Website": ("recommit", True, False),
        "Garden": ("park", True, False),
        "Gone": (None, True, True),
    }
    assert history["totals"]["weeks"] == 1


async def test_reading_an_old_week_changes_no_row_and_relabels_nothing(env: ProjectsEnv) -> None:
    await _seed(env)
    weekly = Weekly(env)
    before = await _snapshot(env)
    async with env.db() as db:
        labels = {r.name: r.label for r in (await db.execute(select(ProjectLabelRow))).scalars()}
    await weekly.state(AFTER_OLD)
    await weekly.state(OLD)
    await weekly.candidates(AFTER_OLD)
    await env.api.get(f"{V1}/weekly/history")
    await env.api.post(f"{V1}/weekly/{AFTER_OLD}/refresh")
    assert await _snapshot(env) == before
    async with env.db() as db:
        after = {r.name: r.label for r in (await db.execute(select(ProjectLabelRow))).scalars()}
    assert after == labels and after["Website"] is None  # never labelled milestone
    new_columns = ("milestone_id", "theme_project_id", "theme_name", "decision", "decided_at")
    assert all(row[c] is None for row in before for c in new_columns)


async def test_an_old_carry_still_suggests_its_project_for_the_next_week(env: ProjectsEnv) -> None:
    await _seed(env)
    weekly = Weekly(env)
    async with env.db() as db:
        row = (
            await db.execute(select(WeeklyPlanProject).where(WeeklyPlanProject.name == "Website"))
        ).scalar_one()
        tasks = [t for t in env.world.tasks["default"].tasks.values() if t.container_id == "p2"]
        assert row.leftover_action == "carry" and tasks
    found = await weekly.candidates(AFTER_OLD)
    assert found["Website"]["kind"] == "unsorted"  # still listed: it has no label yet
