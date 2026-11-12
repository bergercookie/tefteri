"""Fixtures for the monthly review service integration tests."""

import uuid
from datetime import UTC, date, datetime, time
from typing import Any

from sqlalchemy import select

from tefteri.db.models.goal import Goal
from tefteri.db.models.key_result import KeyResult, KeyResultTheme, KeyResultValue
from tefteri.db.models.milestone import Milestone
from tefteri.db.models.monthly import MonthlyFocus, MonthlyFocusEntry
from tefteri.db.models.project_label import ProjectLabel as ProjectLabelRow
from tefteri.domain.entities import Container
from tefteri.domain.enums import ProjectLabel
from tefteri.services.classification import Change
from tests.integration.conftest import ProjectsEnv
from tests.integration.weekly_helpers import Weekly

TODAY = date.today()
MONTH = date(TODAY.year - (TODAY.month == 1), 12 if TODAY.month == 1 else TODAY.month - 1, 1)
TODAY_AT = datetime.combine(TODAY, time(12), UTC)


async def setup_review(env: ProjectsEnv, *names: str) -> dict[str, Any]:
    """Create themes, fix the app clock, and save a past-month focus."""
    env.app.state.clock = lambda: TODAY_AT
    env.app.state.key_result_service._clock = lambda: TODAY_AT
    await env.connect(*(Container(f"theme-{i}", name) for i, name in enumerate(names)))
    await Weekly(env).label(**{name: "theme" for name in names})
    rows = await env.rows()
    user_id = await env.user_id()
    async with env.db() as db:
        db.add(MonthlyFocus(user_id=user_id, month=MONTH))
        await db.flush()
        focus = (
            await db.execute(
                select(MonthlyFocus).where(
                    MonthlyFocus.user_id == user_id, MonthlyFocus.month == MONTH
                )
            )
        ).scalar_one()
        db.add_all(
            [
                MonthlyFocusEntry(
                    focus_id=focus.id,
                    project_id=rows[name].id,
                    name=name,
                    target=None,
                    counts_from=MONTH,
                    position=index,
                )
                for index, name in enumerate(names)
            ]
        )
    return rows


async def add_milestone(
    env: ProjectsEnv,
    name: str,
    *,
    done_on: date,
    theme_name: str | None,
    state: str = "done",
) -> Milestone:
    """Create a milestone project and persist its done-time theme."""
    user_id = await env.user_id()
    async with env.db() as db:
        theme = None
        if theme_name is not None:
            theme = (
                (
                    await db.execute(
                        select(ProjectLabelRow).where(
                            ProjectLabelRow.user_id == user_id,
                            ProjectLabelRow.name == theme_name,
                            ProjectLabelRow.label == ProjectLabel.THEME.value,
                        )
                    )
                )
                .scalars()
                .first()
            )
        project = ProjectLabelRow(
            user_id=user_id,
            connection_id=env.connection_uuid(),
            remote_id=f"milestone-{uuid.uuid4()}",
            name=name,
            label=ProjectLabel.MILESTONE.value,
        )
        db.add(project)
        await db.flush()
        milestone = Milestone(
            user_id=user_id,
            project_id=project.id,
            state=state,
            done_on=done_on if state == "done" else None,
            done_by="user" if state == "done" else None,
            done_theme_id=theme.id if state == "done" and theme else None,
            done_theme_name=theme.name if state == "done" and theme else None,
        )
        db.add(milestone)
        await db.flush()
        return milestone


async def add_key_result(
    env: ProjectsEnv,
    rows: dict[str, Any],
    *,
    metric: str,
    themes: tuple[str, ...],
    start_value: float = 10,
    target: float = 50,
    source: str = "manual",
    year: int | None = None,
    status: str = "active",
    values: tuple[tuple[date, float], ...] = (),
) -> KeyResult:
    """Create a one-result annual goal, its historical theme links, and values."""
    user_id = await env.user_id()
    planning_year = year or MONTH.year
    async with env.db() as db:
        goal = Goal(
            user_id=user_id,
            period_type="year",
            period_start=date(planning_year, 1, 1),
            title=f"Goal for {metric}",
            status="active",
            position=0,
        )
        db.add(goal)
        await db.flush()
        key_result = KeyResult(
            user_id=user_id,
            goal_id=goal.id,
            year=planning_year,
            metric=metric,
            start_value=start_value,
            target=target,
            deadline=date(planning_year, 12, 31),
            update_source=source,
            status=status,
            slot=1 if status == "active" else None,
            position=0,
        )
        db.add(key_result)
        await db.flush()
        db.add_all(
            [
                KeyResultTheme(
                    user_id=user_id,
                    key_result_id=key_result.id,
                    project_id=rows[theme].id,
                    year=planning_year,
                    started_at=datetime.combine(date(planning_year, 1, 1), time.min, UTC),
                )
                for theme in themes
            ]
        )
        db.add_all(
            [
                KeyResultValue(
                    user_id=user_id,
                    key_result_id=key_result.id,
                    value=value,
                    at=datetime.combine(on_date, time(12), UTC),
                    on_date=on_date,
                    source="manual",
                    seq=index,
                )
                for index, (on_date, value) in enumerate(values, 1)
            ]
        )
        await db.flush()
        return key_result


def previous_month(month: date, offset: int) -> date:
    """Return the first day of a month ``offset`` calendar months before ``month``."""
    year, m = month.year, month.month - offset
    while m <= 0:
        year -= 1
        m += 12
    return date(year, m, 1)


async def classify_theme(env: ProjectsEnv, name: str, label: ProjectLabel) -> None:
    """Set one stored project label using the classification service."""
    row = (await env.rows())[name]
    async with env.db() as db:
        await env.classification.save(db, await env.user_id(), [Change(row.id, label)])


async def get_theme_id(env: ProjectsEnv, name: str) -> uuid.UUID:
    """Return one theme's stored project-label id."""
    return (await env.rows())[name].id
