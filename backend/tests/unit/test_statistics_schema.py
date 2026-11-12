"""The statistics response models cover every category and reason, and carry no time (spec 005)."""

import uuid
from datetime import UTC, date, datetime
from pathlib import Path
from typing import Any

import pytest

from tefteri.api.routers import statistics as router
from tefteri.api.routers.statistics import ProjectOut, StatTaskOut
from tefteri.db.models.task_category import TaskCategory
from tefteri.domain.enums import CategoryReason, ProjectLabel, WorkCategory
from tefteri.domain.work_categories import ProjectContext, categorize
from tefteri.openapi import openapi_document

ALLOWED = {
    WorkCategory.GOAL_ALIGNED: {CategoryReason.COMMITTED_MILESTONE},
    WorkCategory.MAINTENANCE: {CategoryReason.MAINTENANCE_LABEL, CategoryReason.INSIDE_ROUTINE},
    WorkCategory.OFF_PLAN: {
        CategoryReason.MILESTONE_NOT_COMMITTED,
        CategoryReason.THEME,
        CategoryReason.UNCLASSIFIED,
        CategoryReason.NO_PROJECT,
    },
    WorkCategory.HIDDEN: {CategoryReason.IGNORED, CategoryReason.IGNORED_ANCESTOR},
}


def _item(category: WorkCategory | str, reason: CategoryReason | str) -> StatTaskOut:
    return StatTaskOut(
        id=uuid.uuid4(),
        title="A task",
        completed_at=datetime(2030, 3, 4, tzinfo=UTC),
        completed_day=date(2030, 3, 4),
        category=category,
        reason=reason,
        unsorted=False,
        project=ProjectOut(id=None, name=None, color=None, orphaned=False),
        url=None,
    )


@pytest.mark.parametrize("category", list(WorkCategory))
def test_the_response_model_accepts_every_work_category(category: WorkCategory) -> None:
    assert _item(category, CategoryReason.THEME).model_dump(mode="json")["category"] == category


@pytest.mark.parametrize("reason", list(CategoryReason))
def test_the_response_model_accepts_every_reason(reason: CategoryReason) -> None:
    assert _item(WorkCategory.OFF_PLAN, reason).reason == reason


def test_every_allowed_pair_of_the_data_model_validates() -> None:
    pairs = [(c, r) for c, reasons in ALLOWED.items() for r in reasons]
    assert {r for _, r in pairs} == set(CategoryReason)  # no reason is left out
    for category, reason in pairs:
        _item(category, reason)


def test_no_value_is_missing_from_the_response_enums() -> None:
    schemas = openapi_document()["components"]["schemas"]
    assert set(schemas["StatTaskOut"]["properties"]["reason"]["$ref"].split("/")[-1:]) == {
        "CategoryReason"
    }
    assert set(schemas["CategoryReason"]["enum"]) == {r.value for r in CategoryReason}
    assert set(schemas["WorkCategory"]["enum"]) == {c.value for c in WorkCategory}


def test_every_result_of_categorize_is_an_allowed_pair() -> None:
    labels = [None, *ProjectLabel]
    for own in labels:
        for ancestor in labels:
            for committed in (True, False):
                d = categorize(ProjectContext(True, own, [ancestor]), committed)
                assert d.reason in ALLOWED[d.category]
    d = categorize(ProjectContext(False), False)
    assert d.reason in ALLOWED[d.category]


def test_the_response_models_use_the_enum_classes_and_no_hand_written_literal() -> None:
    source = Path(router.__file__).read_text(encoding="utf-8")
    assert "Literal[" not in source
    assert "category: WorkCategory" in source and "reason: CategoryReason" in source


_TIME_WORDS = ("duration", "hours", "minutes", "spent", "estimate", "effort")


def _properties(schema: Any, schemas: dict[str, Any], seen: set[str]) -> set[str]:
    names: set[str] = set()
    if isinstance(schema, dict):
        ref = schema.get("$ref")
        if ref:
            key = ref.split("/")[-1]
            if key not in seen:
                seen.add(key)
                names |= _properties(schemas[key], schemas, seen)
        names |= set(schema.get("properties", {}))
        for value in schema.values():
            names |= _properties(value, schemas, seen)
    elif isinstance(schema, list):
        for value in schema:
            names |= _properties(value, schemas, seen)
    return names


def test_no_statistics_schema_holds_a_property_about_time_spent() -> None:
    doc = openapi_document()
    schemas = doc["components"]["schemas"]
    found: set[str] = set()
    for path in ("/api/v1/statistics", "/api/v1/statistics/tasks"):
        found |= _properties(doc["paths"][path]["get"]["responses"]["200"], schemas, set())
    assert {"counts", "parts", "progress", "reason", "project"} <= found
    assert not [n for n in found if any(w in n.lower() for w in _TIME_WORDS)], found


def test_the_model_of_a_stored_category_has_no_time_spent_column() -> None:
    columns = [c.name for c in TaskCategory.__table__.columns]
    assert not [c for c in columns if any(w in c.lower() for w in _TIME_WORDS)], columns
