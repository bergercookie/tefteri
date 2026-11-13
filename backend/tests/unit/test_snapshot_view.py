"""Tests of the tolerant monthly snapshot reader (spec 008, R-02)."""

from datetime import date

from tefteri.domain.snapshot_view import read_snapshot
from tefteri.domain.work_categories import CategoryCounts


def test_a_full_payload_loads_every_field() -> None:
    view = read_snapshot(
        {
            "schema_version": 1,
            "month": "2025-03-01",
            "themes": [
                {
                    "project_id": "p1",
                    "name": "Theme",
                    "target": 2,
                    "done": 1,
                    "status": "in_focus",
                    "milestones": [
                        {"milestone_id": "m1", "name": "One", "done_on": "2025-03-03"}
                    ],
                    "key_result_ids": ["kr"],
                }
            ],
            "outside_focus": [
                {
                    "milestone_id": "m2",
                    "name": "Outside",
                    "done_on": "2025-03-04",
                    "theme_project_id": "p1",
                    "theme_name": "Theme",
                }
            ],
            "categories": {
                "goal_aligned": 1,
                "maintenance": 2,
                "off_plan": 3,
                "hidden": 4,
            },
            "key_results": [
                {
                    "key_result_id": "kr",
                    "latest_value": 12,
                    "latest_at": "2025-03-03T12:00:00Z",
                }
            ],
        }
    )
    assert view.month == "2025-03-01"
    assert view.themes[0].milestones[0].done_on == date(2025, 3, 3)
    assert view.outside_focus[0].theme_name == "Theme"
    assert view.categories == CategoryCounts(1, 2, 3, 4)
    assert view.key_results["kr"].latest_value == 12


def test_missing_and_unknown_fields_do_not_fail() -> None:
    assert read_snapshot({}).key_results == {}
    assert read_snapshot({"schema_version": 99, "new": True}).themes == []
    malformed = read_snapshot(
        {
            "categories": {"goal_aligned": "many"},
            "key_results": [{"key_result_id": "kr", "latest_value": "high"}],
        }
    )
    assert malformed.categories is None
    assert malformed.key_results["kr"].latest_value is None
