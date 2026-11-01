"""Conflict snapshots capture the user-visible fields of both versions."""

from datetime import UTC, datetime

from tefteri.domain.entities import RemoteEntry, RemoteTask
from tefteri.services.conflicts import entry_snapshot, task_snapshot


def test_task_snapshot_of_remote_task() -> None:
    remote = RemoteTask(
        "1", "c", "Title", "v1", done=True, due_at=datetime(2026, 11, 2, tzinfo=UTC)
    )
    assert task_snapshot(remote) == {
        "title": "Title",
        "description": "",
        "status": "done",
        "due_at": "2026-11-02T00:00:00+00:00",
    }


def test_entry_snapshot_of_remote_entry() -> None:
    start = datetime(2026, 11, 2, 9, tzinfo=UTC)
    remote = RemoteEntry("1", "c", "Standup", start, start.replace(hour=10), "v1", location="Room")
    snap = entry_snapshot(remote)
    assert snap["title"] == "Standup" and snap["location"] == "Room"
    assert snap["start"] == "2026-11-02T09:00:00+00:00"
