"""Helpers for the integration tests of weekly milestones (spec 004)."""

from datetime import date, timedelta
from typing import Any

from httpx import Response
from sqlalchemy import select

from tefteri.db.models.connection import SourceContainer
from tests.conftest import V1
from tests.integration.conftest import ProjectsEnv

WEEK = date(2030, 3, 4)  # a Monday, later than any "today" the tests run on
NEXT = WEEK + timedelta(days=7)
AFTER = WEEK + timedelta(days=14)


class Weekly:
    """Small helpers on top of the API, so that a test reads as the story it tells."""

    def __init__(self, env: ProjectsEnv) -> None:
        self.env = env
        self.api = env.api
        self.world = env.world

    async def label(self, **labels: str) -> None:
        """Label projects by name through the project API (spec 003)."""
        tree = (await self.api.get(f"{V1}/projects/classification")).json()
        by_name = {p["name"]: p["id"] for c in tree["connections"] for p in c["projects"]}
        r = await self.api.put(
            f"{V1}/projects/labels",
            json={"changes": [{"id": by_name[n], "label": label} for n, label in labels.items()]},
        )
        assert r.status_code == 200, r.text

    async def cid(self, name: str) -> str:
        """The container id (what the weekly API calls a project) of a project by name."""
        async with self.env.db() as db:
            found = (
                await db.execute(select(SourceContainer.id).where(SourceContainer.name == name))
            ).scalar_one()
        return str(found)

    async def add(self, week: date, name: str) -> dict[str, Any]:
        r = await self.api.post(
            f"{V1}/weekly/{week}/projects", json={"container_id": await self.cid(name)}
        )
        assert r.status_code == 201, r.text
        state: dict[str, Any] = r.json()
        return state

    async def try_add(self, week: date, name: str) -> Response:
        return await self.api.post(
            f"{V1}/weekly/{week}/projects", json={"container_id": await self.cid(name)}
        )

    async def state(self, week: date) -> dict[str, Any]:
        r = await self.api.get(f"{V1}/weekly/{week}")
        assert r.status_code == 200, r.text
        body: dict[str, Any] = r.json()
        return body

    async def entries(self, week: date) -> dict[str, dict[str, Any]]:
        """The entries of the plan of ``week`` by name."""
        plan = (await self.state(week))["plan"]
        return {p["name"]: p for p in (plan["projects"] if plan else [])}

    async def candidates(self, week: date) -> dict[str, dict[str, Any]]:
        r = await self.api.get(f"{V1}/weekly/{week}/candidates")
        assert r.status_code == 200, r.text
        return {c["name"]: c for c in r.json()}

    async def task(self, title: str) -> dict[str, Any]:
        tasks = (await self.api.get(f"{V1}/tasks", params={"due": "all"})).json()
        return next(t for t in tasks if t["title"] == title)

    async def complete(self, *titles: str) -> None:
        for title in titles:
            r = await self.api.post(f"{V1}/tasks/{(await self.task(title))['id']}/complete")
            assert r.status_code == 200, r.text

    async def commit(self, week: date, *names: str) -> dict[str, Any]:
        """Add the milestones, give every open task a day of the week and commit."""
        for name in names:
            await self.add(week, name)
        r = await self.api.post(f"{V1}/weekly/{week}/spread")
        assert r.status_code == 200, r.text
        done = await self.api.post(f"{V1}/weekly/{week}/commit")
        assert done.status_code == 200, done.text
        body: dict[str, Any] = done.json()
        return body

    async def review(
        self, reviewed_week: date, *answers: dict[str, Any], reflection: str = ""
    ) -> Response:
        """Review the week before ``reviewed_week + 7``. Answers use the names of entries."""
        back = (await self.state(reviewed_week + timedelta(days=7)))["look_back"]
        ids = {p["name"]: p["id"] for p in back["projects"]}
        body = [{**a, "plan_project_id": ids[a["name"]]} for a in answers]
        for item in body:
            del item["name"]
        return await self.api.post(
            f"{V1}/weekly/reviews/{back['plan_id']}",
            json={"projects": body, "reflection": reflection},
        )

    async def look_back(self, reviewed_week: date) -> dict[str, Any]:
        back: dict[str, Any] = (await self.state(reviewed_week + timedelta(days=7)))["look_back"]
        return back

    async def look_back_entries(self, reviewed_week: date) -> dict[str, dict[str, Any]]:
        return {p["name"]: p for p in (await self.look_back(reviewed_week))["projects"]}
