#!/usr/bin/env python3
"""Seed the explicitly selected local Vikunja and SQLite database with demo data."""

from __future__ import annotations

import asyncio
import json
import os
import subprocess
import sys
from calendar import monthrange
from collections.abc import Iterable
from datetime import UTC, date, datetime, time, timedelta
from ipaddress import ip_address
from pathlib import Path
from typing import Any
from urllib.parse import urlparse
from uuid import UUID

import httpx
from sqlalchemy import select
from sqlalchemy.engine import make_url
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT / "backend"
CONFIRMATION = "I-UNDERSTAND-THIS-IS-A-THROW-AWAY-DEMO"
VIKUNJA_USERNAME = "tefteri-demo"
VIKUNJA_PASSWORD = "tefteri-demo-password"  # noqa: S105 - fake, throw-away demo password
TEFTERI_USERNAME = "tefteri-demo"
TEFTERI_PASSWORD = "tefteri-demo-password"  # noqa: S105 - fake, throw-away demo password
CONNECTION_NAME = "Tefteri demo (Vikunja)"
THEME_NAMES = (
    "Open source",
    "Product quality",
    "Community",
    "Writing",
    "Health",
    "Learning",
    "Planning",
    "Demo theme to orphan",
)


class SeedError(Exception):
    """A missing safety setting or an unsuccessful seed operation."""


def settings_from_environment() -> tuple[str, str, str]:
    """Require a clearly identified local server and throw-away SQLite file."""
    vikunja_url = os.environ.get("TEFTERI_DEMO_VIKUNJA_URL", "").rstrip("/")
    database_url = os.environ.get("TEFTERI_DEMO_DATABASE_URL", "")
    secret_key = os.environ.get("TEFTERI_DEMO_SECRET_KEY", "")
    confirmation = os.environ.get("TEFTERI_DEMO_CONFIRM", "")
    if not vikunja_url or not database_url or not secret_key or confirmation != CONFIRMATION:
        raise SeedError(
            "seeding is opt-in. Set TEFTERI_DEMO_VIKUNJA_URL, "
            "TEFTERI_DEMO_DATABASE_URL, TEFTERI_DEMO_SECRET_KEY (also used by the local "
            "Tefteri server), and "
            f"TEFTERI_DEMO_CONFIRM={CONFIRMATION!r}."
        )
    if len(secret_key) < 16:
        raise SeedError("TEFTERI_DEMO_SECRET_KEY must contain at least 16 characters.")

    parsed = urlparse(vikunja_url)
    if parsed.scheme != "http" or not parsed.hostname or parsed.username or parsed.password:
        raise SeedError("TEFTERI_DEMO_VIKUNJA_URL must be an unauthenticated local http:// URL.")
    try:
        local_host = parsed.hostname == "localhost" or ip_address(parsed.hostname).is_loopback
    except ValueError:
        local_host = False
    if not local_host or parsed.path not in ("", "/") or parsed.query or parsed.fragment:
        raise SeedError(
            "Vikunja must be explicitly identified by a local loopback URL "
            "(for example http://127.0.0.1:3456). Remote hosts are refused."
        )

    try:
        parsed_db = make_url(database_url)
    except Exception as exc:
        raise SeedError("TEFTERI_DEMO_DATABASE_URL is not a valid SQLAlchemy URL.") from exc
    if (
        parsed_db.drivername != "sqlite+aiosqlite"
        or not parsed_db.database
        or parsed_db.database == ":memory:"
        or not Path(parsed_db.database).is_absolute()
        or "demo" not in Path(parsed_db.database).name.casefold()
    ):
        raise SeedError(
            "TEFTERI_DEMO_DATABASE_URL must be an absolute sqlite+aiosqlite URL "
            "whose filename includes 'demo' (for example "
            "sqlite+aiosqlite:////home/me/tefteri-demo.db)."
        )
    target_path = Path(parsed_db.database).resolve()
    default_path = (BACKEND / "tefteri.db").resolve()
    if target_path == default_path:
        raise SeedError("The application's default database is not a demo database.")
    return vikunja_url, database_url, secret_key


def _request(client: httpx.Client, method: str, path: str, **kwargs: object) -> httpx.Response:
    response = client.request(method, path, **kwargs)
    if response.is_error:
        detail = response.text[:500]
        raise SeedError(f"Vikunja {method} {path} returned {response.status_code}: {detail}")
    return response


def vikunja_token(client: httpx.Client) -> str:
    """Register or log in the dedicated fake Vikunja account; never touch another account."""
    response = client.post(
        "/register",
        json={
            "username": VIKUNJA_USERNAME,
            "email": "tefteri-demo@example.invalid",
            "password": VIKUNJA_PASSWORD,
        },
    )
    if response.status_code not in (200, 201, 400, 409, 412):
        raise SeedError(
            f"Vikunja demo registration returned {response.status_code}: {response.text[:500]}"
        )
    login = _request(
        client,
        "POST",
        "/login",
        json={"username": VIKUNJA_USERNAME, "password": VIKUNJA_PASSWORD},
    )
    token = login.json().get("token")
    if not isinstance(token, str) or not token:
        raise SeedError("Vikunja login did not return an API token.")
    return token


class VikunjaSeed:
    """Small idempotent writer for the dedicated demo account."""

    def __init__(self, client: httpx.Client, token: str) -> None:
        """Store the HTTP client and the bearer token of the demo account."""
        self.client = client
        self.headers = {"Authorization": f"Bearer {token}"}
        self.projects: dict[str, dict[str, object]] = {}
        self.tasks: dict[str, tuple[dict[str, object], date]] = {}

    def _all_projects(self) -> list[dict[str, object]]:
        return _request(self.client, "GET", "/projects", headers=self.headers).json()

    def ensure_project(
        self,
        title: str,
        parent: dict[str, object] | None = None,
    ) -> dict[str, object]:
        """Return the project with the title, and create it when it is missing."""
        parent_id = int(parent["id"]) if parent else 0
        existing = next(
            (
                project
                for project in self._all_projects()
                if project["title"] == title
                and int(project.get("parent_project_id") or 0) == parent_id
            ),
            None,
        )
        if existing is not None:
            return existing
        body: dict[str, object] = {"title": title}
        if parent:
            body["parent_project_id"] = parent_id
        return _request(self.client, "PUT", "/projects", headers=self.headers, json=body).json()

    def ensure_task(
        self, project: dict[str, object], title: str, done_on: date
    ) -> dict[str, object]:
        """Return the task with the title, complete it, and keep it for the demo history."""
        project_id = int(project["id"])
        found = next(
            (
                task
                for task in _request(
                    self.client,
                    "GET",
                    f"/projects/{project_id}/tasks",
                    headers=self.headers,
                    params={"page": 1, "per_page": 100},
                ).json()
                if task["title"] == title
            ),
            None,
        )
        if found is None:
            found = _request(
                self.client,
                "PUT",
                f"/projects/{project_id}/tasks",
                headers=self.headers,
                json={"title": title, "description": "Fake Tefteri demo data."},
            ).json()
        if not found.get("done"):
            task = _request(
                self.client, "GET", f"/tasks/{found['id']}", headers=self.headers
            ).json()
            task["done"] = True
            task["done_at"] = datetime.combine(done_on, time(12), UTC).isoformat()
            _request(
                self.client,
                "POST",
                f"/tasks/{found['id']}",
                headers=self.headers,
                json=task,
            )
            found = _request(
                self.client, "GET", f"/tasks/{found['id']}", headers=self.headers
            ).json()
        if not found.get("done"):
            raise SeedError(f"Vikunja did not preserve the completion of demo task {title!r}.")
        self.tasks[title] = (found, done_on)
        return found


def three_months(today: date) -> tuple[date, date, date]:
    """First days of the previous two months and this month."""
    first = today.replace(day=1)
    previous = (first - timedelta(days=1)).replace(day=1)
    earlier = (previous - timedelta(days=1)).replace(day=1)
    return earlier, previous, first


def month_day(month: date, today: date) -> date:
    """Return an early day in the month, not later than today for the current month."""
    day = min(8, monthrange(month.year, month.month)[1])
    if month == today.replace(day=1):
        day = min(day, today.day)
    return month.replace(day=day)


async def ensure_identity(
    database_url: str, vikunja_url: str, token: str, secret_key: str
) -> tuple[UUID, UUID, set[str]]:
    """Create or safely reuse the named demo user and its single Vikunja connection."""
    from sqlalchemy import func

    from tefteri.auth.passwords import hash_password
    from tefteri.db.models.connection import Connection
    from tefteri.db.models.project_label import ProjectLabel
    from tefteri.db.models.user import User
    from tefteri.domain.enums import ConnectionKind
    from tefteri.security.crypto import TokenCipher

    engine = create_async_engine(database_url)
    factory = async_sessionmaker(engine, expire_on_commit=False)
    try:
        async with factory() as db:
            user = (
                await db.execute(select(User).where(func.lower(User.username) == TEFTERI_USERNAME))
            ).scalar_one_or_none()
            created_user = user is None
            if user is None:
                user = User(
                    username=TEFTERI_USERNAME,
                    password_hash=hash_password(TEFTERI_PASSWORD),
                    is_admin=False,
                    timezone="UTC",
                )
                db.add(user)
                await db.flush()
            connection = (
                await db.execute(
                    select(Connection).where(
                        Connection.user_id == user.id,
                        Connection.display_name == CONNECTION_NAME,
                    )
                )
            ).scalar_one_or_none()
            if connection is None:
                if not created_user:
                    raise SeedError(
                        f"User {TEFTERI_USERNAME!r} exists without the seed connection; "
                        "refusing to adopt it."
                    )
                other = (
                    await db.execute(select(Connection.id).where(Connection.user_id == user.id))
                ).first()
                if other:
                    raise SeedError(
                        f"User {TEFTERI_USERNAME!r} already has connections but no "
                        f"{CONNECTION_NAME!r} connection; refusing to modify it."
                    )
                connection = Connection(
                    user_id=user.id,
                    kind=ConnectionKind.TASKS.value,
                    provider="vikunja",
                    display_name=CONNECTION_NAME,
                    settings={"base_url": vikunja_url},
                    encrypted_credentials=TokenCipher(secret_key).encrypt(
                        json.dumps({"token": token})
                    ),
                    status="ok",
                )
                db.add(connection)
                await db.flush()
            else:
                if (
                    connection.provider != "vikunja"
                    or connection.settings.get("base_url") != vikunja_url
                ):
                    raise SeedError(
                        "The existing demo connection points elsewhere; refusing to replace it."
                    )
                # The login token is rotated by Vikunja. This connection is owned by the demo
                # account identified above, so refreshing its credentials is an idempotent upsert.
                connection.encrypted_credentials = TokenCipher(secret_key).encrypt(
                    json.dumps({"token": token})
                )
                user.password_hash = hash_password(TEFTERI_PASSWORD)
            orphaned = set(
                (
                    await db.execute(
                        select(ProjectLabel.name).where(
                            ProjectLabel.connection_id == connection.id,
                            ProjectLabel.orphaned_reason.is_not(None),
                        )
                    )
                ).scalars()
            )
            await db.commit()
            return user.id, connection.id, orphaned
    finally:
        await engine.dispose()


def build_vikunja_seed(
    remote: VikunjaSeed,
    orphaned_names: set[str],
    current_projects: Iterable[dict[str, object]],
    today: date,
) -> tuple[dict[str, dict[str, object]], dict[str, tuple[dict[str, object], date]]]:
    """Make the project tree and fake tasks, preserving a theme deliberately orphaned later."""
    remote.projects = {
        str(project["id"]): project for project in current_projects if int(project["id"]) > 0
    }
    roots: dict[str, dict[str, object]] = {}
    for name in ("Open source", "Work", "Admin"):
        roots[name] = remote.ensure_project(name)
    themes: dict[str, dict[str, object]] = {THEME_NAMES[0]: roots["Open source"]}
    for name in THEME_NAMES[1:]:
        if name in orphaned_names and not any(
            project["title"] == name for project in remote._all_projects()
        ):
            continue
        themes[name] = remote.ensure_project(name, roots["Work"])
    months = three_months(today)
    for name, theme in themes.items():
        for month in months:
            done_on = month_day(month, today)
            project_name = f"Demo milestone: {name} / {month:%Y-%m}"
            if name in orphaned_names and not any(
                project["title"] == project_name for project in remote._all_projects()
            ):
                continue
            project = remote.ensure_project(project_name, theme)
            remote.projects[str(project["id"])] = project
            task_title = f"Demo finish: {name} / {month:%Y-%m}"
            remote.ensure_task(project, task_title, done_on)
    for month in months:
        project_name = f"Demo milestone without theme / {month:%Y-%m}"
        project = remote.ensure_project(project_name, roots["Admin"])
        remote.projects[str(project["id"])] = project
        remote.ensure_task(
            project,
            f"Demo finish without theme / {month:%Y-%m}",
            month_day(month, today),
        )

    category_counts = ((1, 2, 2), (2, 2, 1), (3, 1, 1))
    for month, (off_plan, maintenance, goal_aligned) in zip(months, category_counts, strict=True):
        done_on = month_day(month, today)
        # An unlabelled Work project gives an off-plan example; Admin is labeled maintenance
        # in Tefteri below. Goal-aligned examples sit in a milestone project.
        selected_milestone = next(
            (p for p in remote.projects.values() if str(p["title"]).startswith("Demo milestone: ")),
            roots["Admin"],
        )
        for category, count, project in (
            ("off-plan", off_plan, roots["Work"]),
            ("maintenance", maintenance, roots["Admin"]),
            ("goal-aligned", goal_aligned, selected_milestone),
        ):
            for index in range(count):
                title = f"Demo {category} task {index + 1} / {month:%Y-%m}"
                remote.ensure_task(project, title, done_on)
    return {name: project for name, project in themes.items()}, remote.tasks


async def seed_database(
    database_url: str,
    vikunja_url: str,
    user_id: UUID,
    connection_id: UUID,
    projects: dict[str, dict[str, object]],
    tasks: dict[str, tuple[dict[str, object], date]],
    today: date,
) -> None:
    """Upsert only demo-owned rows; never delete or reset existing data."""
    from tefteri.db.models.connection import Connection, SourceContainer
    from tefteri.db.models.key_result import KeyResult, KeyResultTheme, KeyResultValue
    from tefteri.db.models.milestone import Milestone
    from tefteri.db.models.project_label import ProjectLabel, ProjectLabelHistory
    from tefteri.db.models.task import Task
    from tefteri.db.models.task_category import TaskCategory
    from tefteri.db.models.user import User

    engine = create_async_engine(database_url)
    factory = async_sessionmaker(engine, expire_on_commit=False)
    try:
        async with factory() as db:
            user = await db.get(User, user_id)
            connection = await db.get(Connection, connection_id)
            if user is None or connection is None:
                raise SeedError("The demo user or Vikunja connection disappeared.")
            if connection.settings.get("base_url") != vikunja_url:
                raise SeedError("The demo connection changed during seeding.")

            containers: dict[str, SourceContainer] = {}
            labels: dict[str, ProjectLabel] = {}
            for remote_id, project in projects.items():
                remote_id = str(project["id"])
                parent_id = (
                    str(project["parent_project_id"]) if project.get("parent_project_id") else None
                )
                container = (
                    await db.execute(
                        select(SourceContainer).where(
                            SourceContainer.connection_id == connection_id,
                            SourceContainer.remote_id == remote_id,
                        )
                    )
                ).scalar_one_or_none()
                if container is None:
                    container = SourceContainer(
                        user_id=user_id,
                        connection_id=connection_id,
                        remote_id=remote_id,
                        name=str(project["title"]),
                        parent_remote_id=parent_id,
                    )
                    db.add(container)
                    await db.flush()
                else:
                    container.name = str(project["title"])
                    container.parent_remote_id = parent_id
                containers[remote_id] = container
                row = (
                    await db.execute(
                        select(ProjectLabel).where(
                            ProjectLabel.connection_id == connection_id,
                            ProjectLabel.remote_id == remote_id,
                        )
                    )
                ).scalar_one_or_none()
                if row is None:
                    row = ProjectLabel(
                        user_id=user_id,
                        connection_id=connection_id,
                        remote_id=remote_id,
                        name=str(project["title"]),
                        parent_remote_id=parent_id,
                    )
                    db.add(row)
                    await db.flush()
                else:
                    row.name = str(project["title"])
                    row.parent_remote_id = parent_id
                    row.orphaned_reason = None
                    row.orphaned_at = None
                labels[remote_id] = row

            desired_labels: dict[str, str] = {
                str(project["id"]): "theme"
                for project in projects.values()
                if project["title"] in THEME_NAMES
            }
            desired_labels.update(
                {
                    str(project["id"]): "milestone"
                    for project in projects.values()
                    if str(project["title"]).startswith("Demo milestone")
                }
            )
            desired_labels[
                str(next(p["id"] for p in projects.values() if p["title"] == "Admin"))
            ] = "maintenance"
            for remote_id, label_value in desired_labels.items():
                row = labels[remote_id]
                if row.label != label_value:
                    row.label = label_value
                    row.label_changed_at = datetime.now(UTC)
                    history = (
                        await db.execute(
                            select(ProjectLabelHistory.id).where(
                                ProjectLabelHistory.project_id == row.id,
                                ProjectLabelHistory.label == label_value,
                            )
                        )
                    ).first()
                    if history is None:
                        db.add(
                            ProjectLabelHistory(
                                project_id=row.id,
                                label=label_value,
                                from_at=datetime(2000, 1, 1, tzinfo=UTC),
                                batch_id=None,
                                source="user",
                            )
                        )

            task_rows: dict[str, Task] = {}
            for title, (remote, done_on) in tasks.items():
                remote_project_id = str(remote["project_id"])
                container = containers.get(remote_project_id)
                if container is None:
                    continue
                task = (
                    await db.execute(
                        select(Task).where(
                            Task.connection_id == connection_id,
                            Task.remote_id == str(remote["id"]),
                        )
                    )
                ).scalar_one_or_none()
                if task is None:
                    task = Task(
                        user_id=user_id,
                        connection_id=connection_id,
                        container_id=container.id,
                        remote_id=str(remote["id"]),
                        title=str(remote["title"]),
                        description=str(remote.get("description") or ""),
                        status="done",
                        completed_at=datetime.combine(done_on, time(12), UTC),
                        all_day=False,
                        labels=[],
                        remote_version=str(remote.get("updated") or ""),
                    )
                    db.add(task)
                    await db.flush()
                else:
                    task.container_id = container.id
                    task.title = str(remote["title"])
                    task.status = "done"
                    task.completed_at = datetime.combine(done_on, time(12), UTC)
                    task.remote_version = str(remote.get("updated") or task.remote_version)
                task_rows[title] = task

            milestone_projects = [
                p for p in projects.values() if str(p["title"]).startswith("Demo milestone")
            ]
            for project in milestone_projects:
                project_id = str(project["id"])
                row = labels[project_id]
                title = str(project["title"])
                matching_task = next(
                    (
                        (task, task_date)
                        for task_title, (task, task_date) in tasks.items()
                        if task_title.startswith("Demo finish")
                        and str(task["project_id"]) == project_id
                    ),
                    None,
                )
                if matching_task is None:
                    continue
                _, done_on = matching_task
                theme_id = (
                    labels[str(project["parent_project_id"])].id
                    if project.get("parent_project_id")
                    and str(
                        projects.get(str(project["parent_project_id"]), {}).get("title", "")
                    ).startswith(
                        (
                            "Open source",
                            "Product quality",
                            "Community",
                            "Writing",
                            "Health",
                            "Learning",
                            "Planning",
                            "Demo theme",
                        )
                    )
                    else None
                )
                milestone = (
                    await db.execute(select(Milestone).where(Milestone.project_id == row.id))
                ).scalar_one_or_none()
                values = {
                    "done_state": "The project has a finished deliverable.",
                    "state": "done",
                    "state_changed_at": datetime.combine(done_on, time(12), UTC),
                    "rollover_count": 0,
                    "done_on": done_on,
                    "done_by": "auto",
                    "done_theme_id": theme_id,
                    "done_theme_name": labels[str(project["parent_project_id"])].name
                    if theme_id
                    else None,
                }
                if milestone is None:
                    db.add(Milestone(user_id=user_id, project_id=row.id, **values))
                else:
                    for key, value in values.items():
                        setattr(milestone, key, value)

            for title, (remote, done_on) in tasks.items():
                if not title.startswith("Demo "):
                    continue
                task_row = task_rows.get(title)
                if task_row is None:
                    continue
                category = (
                    "off_plan"
                    if "off-plan task" in title
                    else "maintenance"
                    if "maintenance task" in title
                    else "goal_aligned"
                    if "goal-aligned task" in title
                    else None
                )
                if category is None:
                    continue
                reason = {
                    "off_plan": "unclassified",
                    "maintenance": "maintenance_label",
                    "goal_aligned": "committed_milestone",
                }[category]
                record = (
                    await db.execute(
                        select(TaskCategory).where(TaskCategory.task_id == task_row.id)
                    )
                ).scalar_one_or_none()
                task_project = labels.get(str(remote["project_id"]))
                values = {
                    "user_id": user_id,
                    "task_id": task_row.id,
                    "completed_at": task_row.completed_at,
                    "completed_on": done_on,
                    "category": category,
                    "reason": reason,
                    "unsorted": category == "off_plan",
                    "project_id": task_project.id if task_project else None,
                    "project_name": task_project.name if task_project else None,
                    "project_label": task_project.label if task_project else None,
                    "plan_id": None,
                    "decided_via": "sync",
                    "decided_at": datetime.now(UTC),
                }
                if record is None:
                    db.add(TaskCategory(**values))

            current_year = today.year
            annual_goal = await _goal(
                db, user_id, "year", date(current_year, 1, 1), "Demo annual progress"
            )
            old_year = current_year - 1
            await _goal(
                db,
                user_id,
                "year",
                date(old_year, 1, 1),
                "Old annual goal with criteria",
                criteria="Ship a small, useful open-source release.",
            )
            previous_month = (today.replace(day=1) - timedelta(days=1)).replace(day=1)
            await _goal(
                db,
                user_id,
                "month",
                previous_month,
                "Old monthly goal",
                criteria="Keep a short log.",
            )
            old_week_start = today - timedelta(days=today.weekday() + 7)
            await _goal(
                db,
                user_id,
                "week",
                old_week_start,
                "Old weekly goal",
                criteria="Finish one small task.",
            )

            theme_projects = {
                str(project["title"]): labels[str(project["id"])]
                for project in projects.values()
                if project["title"] in THEME_NAMES
            }
            key_result_specs = (
                (
                    "Published repository stars",
                    12.0,
                    500.0,
                    "manual",
                    theme_projects.get("Open source"),
                ),
                (
                    "Community contributors",
                    4.0,
                    100.0,
                    "automatic",
                    theme_projects.get("Product quality"),
                ),
            )
            months = three_months(today)
            for slot, (metric, start, target, source, theme) in enumerate(key_result_specs, 1):
                result = (
                    await db.execute(
                        select(KeyResult).where(
                            KeyResult.goal_id == annual_goal.id,
                            KeyResult.metric == metric,
                        )
                    )
                ).scalar_one_or_none()
                if result is None:
                    result = KeyResult(
                        user_id=user_id,
                        goal_id=annual_goal.id,
                        year=current_year,
                        metric=metric,
                        start_value=start,
                        target=target,
                        deadline=date(current_year, 12, 31),
                        update_source=source,
                        status="active",
                        slot=slot,
                        position=slot - 1,
                    )
                    db.add(result)
                    await db.flush()
                if theme is not None:
                    link = (
                        await db.execute(
                            select(KeyResultTheme).where(
                                KeyResultTheme.key_result_id == result.id,
                                KeyResultTheme.project_id == theme.id,
                                KeyResultTheme.ended_at.is_(None),
                            )
                        )
                    ).scalar_one_or_none()
                    if link is None:
                        db.add(
                            KeyResultTheme(
                                user_id=user_id,
                                key_result_id=result.id,
                                project_id=theme.id,
                                year=current_year,
                                started_at=datetime(current_year, 1, 1, tzinfo=UTC),
                            )
                        )
                values = (20.0, 31.0, 45.0) if source == "manual" else (10.0, 25.0, 40.0)
                existing_dates = set(
                    (
                        await db.execute(
                            select(KeyResultValue.on_date).where(
                                KeyResultValue.key_result_id == result.id
                            )
                        )
                    ).scalars()
                )
                next_seq = (
                    await db.execute(
                        select(KeyResultValue.seq)
                        .where(KeyResultValue.key_result_id == result.id)
                        .order_by(KeyResultValue.seq.desc())
                        .limit(1)
                    )
                ).scalar_one_or_none() or 0
                for month, value in zip(months, values, strict=True):
                    on_date = month_day(month, today)
                    if on_date in existing_dates:
                        continue
                    next_seq += 1
                    stamp = datetime.combine(on_date, time(15), UTC)
                    db.add(
                        KeyResultValue(
                            user_id=user_id,
                            key_result_id=result.id,
                            value=value,
                            at=stamp,
                            on_date=on_date,
                            source=source,
                            seq=next_seq,
                        )
                    )

            await db.commit()
    finally:
        await engine.dispose()


async def _goal(
    db: AsyncSession,
    user_id: UUID,
    period_type: str,
    period_start: date,
    title: str,
    *,
    criteria: str = "",
) -> Any:
    from tefteri.db.models.goal import Goal

    result = await db.execute(
        select(Goal).where(
            Goal.user_id == user_id,
            Goal.period_type == period_type,
            Goal.period_start == period_start,
            Goal.title == title,
        )
    )
    goal = result.scalar_one_or_none()
    if goal is None:
        goal = Goal(
            user_id=user_id,
            period_type=period_type,
            period_start=period_start,
            title=title,
            description="Seeded fake data for the local demo walkthrough.",
            criteria=criteria,
            status="active",
        )
        db.add(goal)
        await db.flush()
    elif criteria and not goal.criteria:
        goal.criteria = criteria
    return goal


def migrate(database_url: str) -> None:
    """Run ordinary forward migrations against the explicit demo target only."""
    environment = os.environ.copy()
    environment["TEFTERI_DATABASE_URL"] = database_url
    result = subprocess.run(  # noqa: S603 - fixed arguments, only the explicit demo URL
        [
            sys.executable,
            "-m",
            "alembic",
            "-c",
            str(BACKEND / "alembic.ini"),
            "upgrade",
            "head",
        ],
        cwd=BACKEND,
        env=environment,
        capture_output=True,
        check=False,
        text=True,
    )
    if result.returncode:
        detail = (result.stderr or result.stdout).strip()
        raise SeedError(f"database migrations failed: {detail}")


async def run() -> None:
    """Seed the explicit throw-away Vikunja and demo database, then print the sign-in details."""
    vikunja_url, database_url, secret_key = settings_from_environment()
    today = date.today()
    parsed_db = make_url(database_url)
    db_path = Path(parsed_db.database)
    db_path.parent.mkdir(parents=True, exist_ok=True)

    with httpx.Client(
        base_url=f"{vikunja_url}/api/v1",
        timeout=20,
        follow_redirects=False,
    ) as client:
        info = _request(client, "GET", "/info")
        if not isinstance(info.json(), dict):
            raise SeedError("The local Vikunja /info endpoint returned an unexpected response.")
        token = vikunja_token(client)

    migrate(database_url)
    user_id, connection_id, orphaned_names = await ensure_identity(
        database_url, vikunja_url, token, secret_key
    )
    with httpx.Client(
        base_url=f"{vikunja_url}/api/v1",
        timeout=20,
        follow_redirects=False,
    ) as client:
        remote = VikunjaSeed(client, token)
        initial_projects = remote._all_projects()
        _, tasks = build_vikunja_seed(remote, orphaned_names, initial_projects, today)
        project_tree = remote._all_projects()
        allowed_projects = {
            str(project["id"]): project
            for project in project_tree
            if int(project["id"]) > 0
            and (
                str(project["title"]).startswith("Demo milestone")
                or project["title"] in ("Open source", "Work", "Admin", *THEME_NAMES)
            )
        }
        # Keep the mirror limited to projects created for this user and walkthrough.
        for title, (task, _) in list(tasks.items()):
            if str(task.get("project_id")) not in allowed_projects:
                tasks.pop(title)
        await seed_database(
            database_url,
            vikunja_url,
            user_id,
            connection_id,
            allowed_projects,
            tasks,
            today,
        )
    print("Seeded fake demo data in the explicitly selected local Vikunja and SQLite database.")
    print(f"Tefteri sign-in: {TEFTERI_USERNAME} / {TEFTERI_PASSWORD}")
    print(f"Vikunja sign-in: {VIKUNJA_USERNAME} / {VIKUNJA_PASSWORD}")
    print(
        "Run the local Tefteri server with TEFTERI_DATABASE_URL and TEFTERI_SECRET_KEY "
        "set to the same values as TEFTERI_DEMO_DATABASE_URL and TEFTERI_DEMO_SECRET_KEY."
    )
    print("After the first sync, delete 'Demo theme to orphan' in Vikunja to see the orphan state.")


def main() -> int:
    """Run the seed and turn every failure into one clear diagnostic."""
    try:
        asyncio.run(run())
    except Exception as exc:  # noqa: BLE001 - command-line failures need one clear diagnostic
        print(f"seed_demo: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
