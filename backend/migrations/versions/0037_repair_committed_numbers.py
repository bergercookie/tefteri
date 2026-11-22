"""repair the numbers of reviewed weeks after a milestone was closed

Closing a milestone moves its open tasks to the theme. The review counted a week's committed
tasks by the project they were in, so a review that came after the close stored too few
committed tasks, and the trends and the look-back showed them. A task that was committed at the
start of the week and done in the theme was recorded off-plan.

This repair counts the committed tasks of every reviewed week again, by the ids that the plan
kept, and never lowers a stored number. It makes a committed task goal-aligned when it was
recorded off-plan only because it was no longer in its milestone. The kept numbers of the weeks
that changed are removed, and the trends make them again.

Revision ID: 0037
Revises: 0036
"""

import uuid
from datetime import date, timedelta

import sqlalchemy as sa
from alembic import op

revision = "0037"
down_revision = "0036"
branch_labels = None
depends_on = None

_plans = sa.table(
    "weekly_plans",
    sa.column("id", sa.Uuid()),
    sa.column("user_id", sa.Uuid()),
    sa.column("week_start", sa.Date()),
    sa.column("status", sa.String()),
    sa.column("reviewed_at", sa.DateTime(timezone=True)),
)
_rows = sa.table(
    "weekly_plan_projects",
    sa.column("id", sa.Uuid()),
    sa.column("plan_id", sa.Uuid()),
    sa.column("committed_task_ids", sa.JSON()),
    sa.column("reviewed_committed", sa.Integer()),
    sa.column("reviewed_done", sa.Integer()),
)
_tasks = sa.table(
    "tasks",
    sa.column("id", sa.Uuid()),
    sa.column("status", sa.String()),
    sa.column("sync_state", sa.String()),
)
_categories = sa.table(
    "task_categories",
    sa.column("id", sa.Uuid()),
    sa.column("user_id", sa.Uuid()),
    sa.column("task_id", sa.Uuid()),
    sa.column("completed_on", sa.Date()),
    sa.column("category", sa.String()),
    sa.column("reason", sa.String()),
    sa.column("unsorted", sa.Boolean()),
    sa.column("plan_id", sa.Uuid()),
)
_metrics = sa.table(
    "weekly_metrics",
    sa.column("user_id", sa.Uuid()),
    sa.column("week_start", sa.Date()),
)

_NOT_PLANNED = ("theme", "unclassified", "milestone_not_committed")


def _uuid(raw: object) -> uuid.UUID | None:
    try:
        return uuid.UUID(str(raw))
    except ValueError:
        return None


def upgrade() -> None:
    """Count the committed tasks again and fix the categories of the committed ones."""
    bind = op.get_bind()
    changed: set[tuple[uuid.UUID, date]] = set()
    committed_by_week: dict[tuple[uuid.UUID, date], dict[uuid.UUID, uuid.UUID]] = {}
    plans = bind.execute(
        sa.select(_plans.c.id, _plans.c.user_id, _plans.c.week_start, _plans.c.reviewed_at).where(
            _plans.c.status == "committed"
        )
    ).all()
    for plan_id, user_id, week_start, reviewed_at in plans:
        rows = bind.execute(
            sa.select(
                _rows.c.id,
                _rows.c.committed_task_ids,
                _rows.c.reviewed_committed,
                _rows.c.reviewed_done,
            ).where(_rows.c.plan_id == plan_id)
        ).all()
        by_task = committed_by_week.setdefault((user_id, week_start), {})
        for row_id, raw_ids, stored_committed, stored_done in rows:
            ids = [i for i in (_uuid(x) for x in (raw_ids or [])) if i is not None]
            by_task.update({i: plan_id for i in ids})
            if reviewed_at is None or not ids:
                continue
            found = {
                tid: status
                for tid, status, state in bind.execute(
                    sa.select(_tasks.c.id, _tasks.c.status, _tasks.c.sync_state).where(
                        _tasks.c.id.in_(ids)
                    )
                )
                if state != "deleted_remotely" or status == "done"
            }
            committed = max(stored_committed or 0, len(found))
            done = min(
                committed,
                max(stored_done or 0, sum(1 for s in found.values() if s == "done")),
            )
            if (committed, done) != (stored_committed, stored_done):
                bind.execute(
                    sa.update(_rows)
                    .where(_rows.c.id == row_id)
                    .values(reviewed_committed=committed, reviewed_done=done)
                )
                changed.add((user_id, week_start))
    for (user_id, week_start), by_task in committed_by_week.items():
        if not by_task:
            continue
        end = week_start + timedelta(days=7)
        stale = bind.execute(
            sa.select(_categories.c.id, _categories.c.task_id).where(
                _categories.c.user_id == user_id,
                _categories.c.completed_on >= week_start,
                _categories.c.completed_on < end,
                _categories.c.category == "off_plan",
                _categories.c.reason.in_(_NOT_PLANNED),
            )
        ).all()
        for category_id, task_id in stale:
            plan_id = by_task.get(_uuid(task_id) or task_id)
            if plan_id is None:
                continue
            bind.execute(
                sa.update(_categories)
                .where(_categories.c.id == category_id)
                .values(
                    category="goal_aligned",
                    reason="committed_milestone",
                    unsorted=False,
                    plan_id=plan_id,
                )
            )
            changed.add((user_id, week_start))
    for user_id, week_start in changed:
        bind.execute(
            sa.delete(_metrics).where(
                _metrics.c.user_id == user_id, _metrics.c.week_start == week_start
            )
        )


def downgrade() -> None:
    """A repair of data has nothing to undo."""
