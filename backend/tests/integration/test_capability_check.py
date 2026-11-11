"""A task app that lacks a required capability is refused and named (spec 003, FR-015, FR-016)."""

from httpx import AsyncClient

from tefteri.domain.enums import Capability, ConnectionKind
from tefteri.domain.errors import NotSupported  # noqa: F401
from tests.conftest import V1
from tests.fakes.world import FakeWorld


async def _connect(api: AsyncClient) -> object:
    return await api.post(
        f"{V1}/connections",
        json={
            "provider": "vikunja",
            "display_name": "Tasks",
            "settings": {},
            "credentials": {"token": "t"},
        },
    )


async def test_a_task_app_without_a_required_capability_is_refused_with_its_name(
    api: AsyncClient, world: FakeWorld
) -> None:
    world.tasks["default"].supported.discard(Capability.SUBPROJECTS)
    r = await _connect(api)
    assert r.status_code == 422  # type: ignore[attr-defined]
    body = r.json()  # type: ignore[attr-defined]
    assert body["code"] == "missing_capability"
    assert "subprojects" in body["detail"]
    assert (await api.get(f"{V1}/connections")).json() == []  # nothing was stored


async def test_all_missing_capabilities_are_named(api: AsyncClient, world: FakeWorld) -> None:
    world.tasks["default"].supported -= {Capability.COMPLETION_TIMES, Capability.CREATE_TASKS}
    body = (await _connect(api)).json()  # type: ignore[attr-defined]
    assert "completion_times" in body["detail"] and "create_tasks" in body["detail"]


async def test_a_missing_optional_capability_only_turns_its_flag_off(
    api: AsyncClient, world: FakeWorld
) -> None:
    world.tasks["default"].supported -= {Capability.RENAME_PROJECTS}
    r = await _connect(api)
    assert r.status_code == 201  # type: ignore[attr-defined]
    assert r.json()["capabilities"] == {  # type: ignore[attr-defined]
        "missing_required": [],
        "optional": {"rename": False, "restore": True},
    }


async def test_check_reports_a_capability_that_went_missing(
    api: AsyncClient, world: FakeWorld
) -> None:
    made = await _connect(api)
    connection = made.json()["id"]  # type: ignore[attr-defined]
    ok = (await api.post(f"{V1}/connections/{connection}/check")).json()
    assert ok["status"] == "ok"
    assert ok["capabilities"] == {
        "missing_required": [],
        "optional": {"rename": True, "restore": True},
    }
    world.tasks["default"].supported.discard(Capability.ARCHIVE_PROJECTS)
    bad = (await api.post(f"{V1}/connections/{connection}/check")).json()
    assert bad["status"] == "error" and bad["reason"] == "missing_capability"
    assert "archive_projects" in bad["message"]
    assert bad["capabilities"]["missing_required"] == ["archive_projects"]


async def test_a_calendar_has_no_capability_report_to_worry_about(
    api: AsyncClient, world: FakeWorld
) -> None:
    del world
    r = await api.post(
        f"{V1}/connections",
        json={
            "provider": "trilium",
            "display_name": "Notes",
            "settings": {},
            "credentials": {"token": "t"},
        },
    )
    assert r.status_code == 201
    assert r.json()["capabilities"] == {"missing_required": [], "optional": {}}
    assert ConnectionKind.NOTES.value == "notes"
