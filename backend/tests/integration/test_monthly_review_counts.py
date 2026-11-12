"""Monthly review counts use the milestone's done date and theme at done."""

from datetime import timedelta

from sqlalchemy import select

from tefteri.db.models.milestone import Milestone
from tefteri.db.models.monthly import MonthlyFocusEntry
from tefteri.db.models.project_label import ProjectLabel as ProjectLabelRow
from tefteri.domain.enums import FocusEntryStatus
from tests.integration.conftest import ProjectsEnv
from tests.integration.monthly_review_helpers import MONTH, add_milestone, setup_review


async def test_review_counts_done_milestones_by_theme_and_done_date(env: ProjectsEnv) -> None:
    rows = await setup_review(env, "Missed", "Beaten", "Met", "Zero", "No target")
    user_id = await env.user_id()
    async with env.db() as db:
        db.add(
            ProjectLabelRow(
                user_id=user_id,
                connection_id=env.connection_uuid(),
                remote_id="outside-theme",
                name="Not focused",
                label="theme",
            )
        )
    async with env.db() as db:
        focus_entries = (
            (
                await db.execute(
                    select(MonthlyFocusEntry).where(
                        MonthlyFocusEntry.project_id == rows["Missed"].id
                    )
                )
            )
            .scalars()
            .all()
        )
        focus_entries[0].target = 3
        zero_entry = (
            await db.execute(
                select(MonthlyFocusEntry).where(MonthlyFocusEntry.project_id == rows["Zero"].id)
            )
        ).scalar_one()
        zero_entry.target = 0
        beaten_entry = (
            await db.execute(
                select(MonthlyFocusEntry).where(MonthlyFocusEntry.project_id == rows["Beaten"].id)
            )
        ).scalar_one()
        beaten_entry.target = 3
        met_entry = (
            await db.execute(
                select(MonthlyFocusEntry).where(MonthlyFocusEntry.project_id == rows["Met"].id)
            )
        ).scalar_one()
        met_entry.target = 3
    for theme, count in (("Missed", 2), ("Beaten", 3), ("Met", 3)):
        for index in range(count):
            await add_milestone(
                env,
                f"{theme} milestone {index}",
                done_on=MONTH + timedelta(days=index),
                theme_name=theme,
            )
    await add_milestone(env, "Closed", done_on=MONTH, theme_name="Met", state="closed")
    await add_milestone(env, "Parked", done_on=MONTH, theme_name="Met", state="parked")
    moved = await add_milestone(
        env, "Moved milestone", done_on=MONTH + timedelta(days=2), theme_name=None
    )
    async with env.db() as db:
        done = await db.get(Milestone, moved.id)
        assert done is not None
        done.done_theme_id = rows["Beaten"].id
        done.done_theme_name = "Beaten"
    next_month = MONTH.replace(day=28) + timedelta(days=4)
    next_month = next_month.replace(day=1)
    last_day = next_month - timedelta(days=1)
    await add_milestone(env, "Last day", done_on=last_day, theme_name="No target")
    await add_milestone(env, "Outside", done_on=MONTH, theme_name=None)
    await add_milestone(env, "Outside focus", done_on=MONTH, theme_name="Not focused")
    async with env.db() as db:
        milestones = list(
            (
                await db.execute(
                    select(Milestone).where(
                        Milestone.user_id == await env.user_id(),
                        Milestone.done_on >= MONTH,
                    )
                )
            ).scalars()
        )
    assert len(milestones) == 12
    assert sum(item.done_theme_id == rows["Missed"].id for item in milestones) == 2

    async with env.db() as db:
        draft = await env.app.state.monthly_review_service.draft(
            db, await env.user_id(), MONTH, tz="UTC"
        )
    themes = {item["name"]: item for item in draft.snapshot["themes"]}
    assert (themes["Missed"]["done"], themes["Missed"]["marker"]) == (2, "missed")
    assert (themes["Beaten"]["done"], themes["Beaten"]["marker"]) == (4, "beaten")
    assert (themes["Met"]["done"], themes["Met"]["marker"]) == (3, "met")
    assert (themes["Zero"]["done"], themes["Zero"]["marker"]) == (0, "met")
    assert (themes["No target"]["done"], themes["No target"]["marker"]) == (1, "no_target")
    outside_theme_id = (await env.rows())["Not focused"].id
    assert any(
        item["name"] == "Outside focus"
        and item["theme_name"] == "Not focused"
        and item["theme_project_id"] == str(outside_theme_id)
        for item in draft.snapshot["outside_focus"]
    )
    assert any(
        item["name"] == "Outside" and item["theme_name"] is None
        for item in draft.snapshot["outside_focus"]
    )


async def test_swapped_out_theme_and_orphan_keep_historical_counting(env: ProjectsEnv) -> None:
    rows = await setup_review(env, "Old", "New")
    await add_milestone(env, "Before swap", done_on=MONTH, theme_name="New")
    await add_milestone(env, "After swap", done_on=MONTH + timedelta(days=10), theme_name="New")
    await add_milestone(env, "Old result", done_on=MONTH + timedelta(days=12), theme_name="Old")
    async with env.db() as db:
        entry = (
            await db.execute(
                select(MonthlyFocusEntry).where(MonthlyFocusEntry.project_id == rows["New"].id)
            )
        ).scalar_one()
        entry.counts_from = MONTH + timedelta(days=5)
        old = (
            await db.execute(
                select(MonthlyFocusEntry).where(MonthlyFocusEntry.project_id == rows["Old"].id)
            )
        ).scalar_one()
        old.target = 3
        old.left_on = MONTH + timedelta(days=15)
        old.left_reason = "swapped_out"
        project = await db.get(ProjectLabelRow, rows["Old"].id)
        assert project is not None
        project.orphaned_reason = "missing"
    async with env.db() as db:
        draft = await env.app.state.monthly_review_service.draft(
            db, await env.user_id(), MONTH, tz="UTC"
        )
    themes = {item["name"]: item for item in draft.snapshot["themes"]}
    assert themes["New"]["done"] == 1
    assert [item["name"] for item in themes["New"]["earlier_not_counted"]] == ["Before swap"]
    assert themes["Old"]["status"] == FocusEntryStatus.SWAPPED_OUT.value
    assert themes["Old"]["done"] == 1
    assert themes["Old"]["marker"] == "missed"
    assert themes["Old"]["orphaned"] == {"reason": "missing"}
