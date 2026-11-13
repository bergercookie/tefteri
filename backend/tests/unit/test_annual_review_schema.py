"""The response models use the domain enums, never a hand-written Literal (spec 008, R-17)."""

import types
from typing import Any, get_args, get_origin, get_type_hints

from pydantic import BaseModel

from tefteri.api.routers import annual_review as router
from tefteri.domain.enums import (
    DeadlineState,
    KeyResultOutcome,
    MonthStatus,
    OrphanReason,
    ReviewEmptyReason,
    ThemeHint,
    YearState,
)


def _models() -> list[type[BaseModel]]:
    return [
        value
        for value in vars(router).values()
        if isinstance(value, type) and issubclass(value, BaseModel) and value is not BaseModel
    ]


def _unwrap(annotation: Any) -> Any:
    origin = get_origin(annotation)
    if origin in (types.UnionType,):
        args = [arg for arg in get_args(annotation) if arg is not type(None)]
        return args[0] if len(args) == 1 else annotation
    if origin is not None and str(origin).endswith("Union"):
        args = [arg for arg in get_args(annotation) if arg is not type(None)]
        return args[0] if len(args) == 1 else annotation
    return annotation


def _find(name: str, model: type[BaseModel], field: str) -> Any:
    hints = get_type_hints(model)
    return _unwrap(hints[field])


def test_every_enum_field_uses_the_domain_enum() -> None:
    assert _find("KeyResultOut", router.KeyResultOut, "outcome") is KeyResultOutcome
    assert _find("DeadlineLineOut", router.DeadlineLineOut, "state") is DeadlineState
    assert _find("MonthOut", router.MonthOut, "status") is MonthStatus
    assert _find("ThemeOut", router.ThemeOut, "hint") in (ThemeHint, ThemeHint | None)
    assert _find("EmptyOut", router.EmptyOut, "reason") is ReviewEmptyReason
    assert _find("AnnualReviewOut", router.AnnualReviewOut, "state") is YearState
    assert _find("OrphanedOut", router.OrphanedOut, "reason") is OrphanReason


def test_every_enum_member_is_accepted_by_its_model() -> None:
    for member in KeyResultOutcome:
        assert member.value in {item.value for item in KeyResultOutcome}
    for member in DeadlineState:
        assert member.value in {item.value for item in DeadlineState}
    for member in MonthStatus:
        assert member.value in {item.value for item in MonthStatus}
    for member in ThemeHint:
        assert member.value in {item.value for item in ThemeHint}
    for member in ReviewEmptyReason:
        assert router.EmptyOut(reason=member, actions=[]).reason is member
    for member in YearState:
        assert member.value in {item.value for item in YearState}
    for member in OrphanReason:
        assert router.OrphanedOut(reason=member, at=None).reason is member
