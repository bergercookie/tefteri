"""Annual planning routes for the signed-in user."""

import uuid
from datetime import date
from typing import Annotated, cast

from fastapi import APIRouter, Query, Request
from pydantic import BaseModel, Field

from tefteri.api.deps import CurrentUser, Db
from tefteri.domain.annual_plan import today_in
from tefteri.domain.enums import UpdateSource, ValueSource
from tefteri.services.annual_plan import (
    AnnualPlan,
    AnnualPlanService,
    BulkGoalDraft,
    BulkKeyResultDraft,
    GoalOut,
    KeyResultOut,
    utc,
)
from tefteri.services.errors import Invalid
from tefteri.services.key_results import KeyResultService, SeriesPoint
from tefteri.services.project_labels import load_trees

router = APIRouter(tags=["annual"])


def _annual(request: Request) -> AnnualPlanService:
    return cast(AnnualPlanService, request.app.state.annual_service)


def _key_results(request: Request) -> KeyResultService:
    return cast(KeyResultService, request.app.state.key_result_service)


def _retire_answer(effect: object, batch_id: uuid.UUID | None) -> dict[str, object]:
    """The answer of a retire: the effect, and the batch when it was written."""
    if batch_id is None:
        return {"effect": effect}
    return {"batch_id": batch_id, "effect": effect}


def _today(request: Request, user: CurrentUser) -> date:
    """Today in the user's time zone, from the clock of the key result service."""
    return today_in(user.timezone, _key_results(request)._clock())


async def _plan_of(request: Request, db: Db, user: CurrentUser, year: int) -> AnnualPlan:
    return await _annual(request).plan(db, user.id, year, tz=user.timezone)


async def _goal_from_plan(plan: object, goal_id: uuid.UUID) -> GoalOut | None:
    goals: list[GoalOut] = list(getattr(plan, "goals", []))
    for goal in goals:
        if goal.id == goal_id:
            return goal
    for goal in cast(list[GoalOut], list(getattr(plan, "retired_goals", []))):
        if goal.id == goal_id:
            return goal
    return None


async def _key_result_from_plan(plan: object, key_result_id: uuid.UUID) -> KeyResultOut | None:
    all_goals = cast(list[GoalOut], list(getattr(plan, "goals", []))) + cast(
        list[GoalOut], list(getattr(plan, "retired_goals", []))
    )
    for goal in all_goals:
        for key_result in goal.key_results:
            if key_result.id == key_result_id:
                return key_result
    return None


class BulkKeyResultIn(BaseModel):
    """One key result in a bulk create."""

    metric: str
    start_value: float
    target: float
    deadline: date
    update_source: UpdateSource | str = UpdateSource.MANUAL
    theme_ids: list[uuid.UUID] = Field(default_factory=list)
    seeded_from_key_result_id: uuid.UUID | None = None


class BulkGoalIn(BaseModel):
    """One goal of a bulk create."""

    title: str
    seeded_from_goal_id: uuid.UUID | None = None
    key_results: list[BulkKeyResultIn] = Field(default_factory=list)


class BulkGoalsIn(BaseModel):
    """Data to create several goals and their key results in one batch."""

    seeded_from: int | None = None
    goals: list[BulkGoalIn] = Field(default_factory=list)


class GoalEditIn(BaseModel):
    """New title for an annual goal."""

    title: str = Field(min_length=1, max_length=500)


class KeyResultCreateIn(BaseModel):
    """Data to create a key result."""

    metric: str
    start_value: float
    target: float
    deadline: date
    update_source: UpdateSource | str = UpdateSource.MANUAL
    theme_ids: list[uuid.UUID] = Field(default_factory=list)


class KeyResultEditIn(BaseModel):
    """Editable fields of a key result."""

    metric: str | None = None
    target: float | None = None
    deadline: date | None = None
    update_source: UpdateSource | str | None = None


class RetireIn(BaseModel):
    """Data for a retire or restore request."""

    reason: str | None = None
    dry_run: bool = False


class ThemeSetIn(BaseModel):
    """Theme ids to link to one key result."""

    theme_ids: list[uuid.UUID] = Field(default_factory=list)
    dry_run: bool = False


class ThemeCreateIn(BaseModel):
    """Create a theme project in a task app."""

    connection_id: uuid.UUID
    name: str


class ValueIn(BaseModel):
    """A manual value entry."""

    value: float
    on_date: date | None = Field(default=None, alias="date")

    model_config = {"populate_by_name": True}


class UndoIn(BaseModel):
    """A batch to undo."""

    batch_id: uuid.UUID


@router.get("/annual/themes")
async def get_theme_picker(
    request: Request,
    db: Db,
    user: CurrentUser,
) -> object:
    """Return the eligible theme projects and task connections."""
    return await _annual(request).themes(db, user.id, year=_today(request, user).year)


@router.get("/annual/push-token")
async def get_push_token_status(
    request: Request,
    db: Db,
    user: CurrentUser,
) -> dict[str, object]:
    """Return whether a push token exists and, if so, its hint and times. Never the token."""
    status = await request.app.state.push_token_service.status(db, user.id)
    if not status.exists:
        return {"exists": False}
    return {
        "exists": True,
        "hint": status.hint,
        "created_at": utc(status.created_at),
        "last_used_at": utc(status.last_used_at),
    }


@router.post("/annual/push-token")
async def create_or_rotate_push_token(
    request: Request,
    db: Db,
    user: CurrentUser,
) -> dict[str, str]:
    """Create or rotate the user's push token."""
    service = request.app.state.push_token_service
    token, hint = await service.issue(db, user.id)
    return {"token": token, "hint": hint}


@router.delete("/annual/push-token", status_code=204)
async def delete_push_token(
    request: Request,
    db: Db,
    user: CurrentUser,
) -> None:
    """Revoke the user's push token."""
    await request.app.state.push_token_service.revoke(db, user.id)


@router.get("/annual/{year}")
async def get_annual_plan(
    year: int,
    request: Request,
    db: Db,
    user: CurrentUser,
) -> object:
    """Return the annual plan read model for one year."""
    return await _plan_of(request, db, user, year)


@router.get("/annual/{year}/history")
async def get_annual_history(
    year: int,
    request: Request,
    db: Db,
    user: CurrentUser,
    goal_id: uuid.UUID | None = None,
    key_result_id: uuid.UUID | None = None,
) -> dict[str, object]:
    """Return the changes of the year in time order, oldest first (FR-019).

    ``undone`` is true for the rows of a batch that a later undo reverted.
    """
    service = _annual(request)
    changes = await service.history(db, user.id, year, goal_id=goal_id, key_result_id=key_result_id)
    return {"year": year, "changes": changes}


@router.get("/annual/{year}/suggestions")
async def get_suggestions(
    year: int,
    request: Request,
    db: Db,
    user: CurrentUser,
    from_year: int | None = None,
) -> dict[str, object]:
    """Suggest goals and unmet key results of year N for a new year (FR-016, FR-017, R-10).

    ``from_year`` defaults to the year before. Nothing is read for writing and nothing is
    stored: the client accepts suggestions through ``POST /annual/{year}/goals/bulk``.
    """
    source = year - 1 if from_year is None else from_year
    if source >= year:
        raise Invalid("The source year must be earlier than the new year.")
    return await _annual(request).suggestions_view(db, user.id, year, from_year=source)


@router.get("/annual/key-results/{key_result_id}/value-on")
async def get_value_on(
    key_result_id: uuid.UUID,
    request: Request,
    db: Db,
    user: CurrentUser,
    date_: Annotated[date, Query(alias="date")],
) -> object:
    """Return the last value on or before the selected date."""
    service = _key_results(request)
    return await service.value_on(db, user.id, key_result_id, date_)


@router.get("/annual/key-results/{key_result_id}/values")
async def get_key_result_values(
    key_result_id: uuid.UUID,
    request: Request,
    db: Db,
    user: CurrentUser,
) -> list[SeriesPoint]:
    """Return the full value series of one key result, newest first."""
    key_result = await _key_results(request).get(db, user.id, key_result_id)
    return await _key_results(request).series(db, user.id, key_result)


@router.post("/annual/{year}/goals/bulk", status_code=201)
async def bulk_create_goals(
    year: int,
    body: BulkGoalsIn,
    request: Request,
    db: Db,
    user: CurrentUser,
) -> dict[str, object]:
    """Create several goals and key results in one transaction and one batch."""
    service = _annual(request)
    goals = [
        BulkGoalDraft(
            title=g.title,
            key_results=[
                BulkKeyResultDraft(
                    metric=kr.metric,
                    start_value=kr.start_value,
                    target=kr.target,
                    deadline=kr.deadline,
                    update_source=(
                        UpdateSource(kr.update_source)
                        if isinstance(kr.update_source, str)
                        else kr.update_source
                    ),
                    theme_ids=kr.theme_ids,
                    seeded_from_id=kr.seeded_from_key_result_id,
                )
                for kr in g.key_results
            ],
        )
        for g in body.goals
    ]
    batch_id = uuid.uuid4()
    created = await service.bulk_create(
        db,
        user.id,
        year,
        goals,
        seeded_from=body.seeded_from,
        tz=user.timezone,
        batch_id=batch_id,
    )
    plan = await _plan_of(request, db, user, year)
    return {
        "batch_id": batch_id,
        "goals": [await _goal_from_plan(plan, goal.id) or goal for goal in created],
    }


@router.patch("/annual/goals/{goal_id}")
async def edit_goal(
    goal_id: uuid.UUID,
    body: GoalEditIn,
    request: Request,
    db: Db,
    user: CurrentUser,
) -> GoalOut:
    """Edit the title of one goal and record the change in plan history."""
    goal = await _annual(request).edit_goal(db, user.id, goal_id, body.title, tz=user.timezone)
    plan = await _plan_of(request, db, user, goal.period_start.year)
    found = await _goal_from_plan(plan, goal_id)
    if found is None:
        return GoalOut(
            id=goal.id,
            title=goal.title,
            status=goal.status,
            legacy_done=False,
            criteria_suggestion=None,
            progress=0.0,
            flags=[],
            notes=[],
            updated_at=goal.updated_at,
            key_results=[],
        )
    return found


@router.post("/annual/goals/{goal_id}/key-results", status_code=201)
async def create_key_result(
    goal_id: uuid.UUID,
    body: KeyResultCreateIn,
    request: Request,
    db: Db,
    user: CurrentUser,
) -> object:
    """Create a new key result for one goal."""
    service = _annual(request)
    goal = await service._goal(db, user.id, goal_id)
    service.require_open(goal.period_start.year, tz=user.timezone)
    trees = await load_trees(db, user.id)
    key_result = await _key_results(request).create(
        db,
        user.id,
        goal,
        metric=body.metric,
        start_value=body.start_value,
        target=body.target,
        deadline=body.deadline,
        update_source=(
            UpdateSource(body.update_source)
            if isinstance(body.update_source, str)
            else body.update_source
        ),
        theme_ids=body.theme_ids,
        trees=trees,
    )
    plan = await _plan_of(request, db, user, goal.period_start.year)
    return await _key_result_from_plan(plan, key_result.id)


@router.patch("/annual/key-results/{key_result_id}")
async def edit_key_result(
    key_result_id: uuid.UUID,
    body: KeyResultEditIn,
    request: Request,
    db: Db,
    user: CurrentUser,
) -> object:
    """Edit the editable fields of a key result."""
    kr_service = _key_results(request)
    key_result = await kr_service.get(db, user.id, key_result_id)
    _annual(request).require_open(key_result.year, tz=user.timezone)
    await kr_service.edit(
        db,
        user.id,
        key_result,
        metric=body.metric,
        target=body.target,
        deadline=body.deadline,
        update_source=(
            UpdateSource(body.update_source)
            if isinstance(body.update_source, str)
            else body.update_source
        ),
    )
    plan = await _plan_of(request, db, user, key_result.year)
    return await _key_result_from_plan(plan, key_result_id)


@router.post("/annual/goals/{goal_id}/retire")
async def retire_goal(
    goal_id: uuid.UUID,
    body: RetireIn,
    request: Request,
    db: Db,
    user: CurrentUser,
) -> object:
    """Retire a goal with all its active key results, or only show the effect (``dry_run``).

    The answer is ``{"effect": ...}`` for a dry run, else ``{"batch_id", "effect"}`` (FR-021).
    """
    outcome = await _annual(request).retire_goal(
        db,
        user.id,
        goal_id,
        body.reason,
        dry_run=body.dry_run,
        tz=user.timezone,
    )
    return _retire_answer(outcome.effect, outcome.batch_id)


@router.post("/annual/key-results/{key_result_id}/retire")
async def retire_key_result(
    key_result_id: uuid.UUID,
    body: RetireIn,
    request: Request,
    db: Db,
    user: CurrentUser,
) -> object:
    """Retire one key result, or only show the effect (``dry_run``). Its links end too."""
    key_result = await _key_results(request).get(db, user.id, key_result_id)
    _annual(request).require_open(key_result.year, tz=user.timezone)
    trees = await load_trees(db, user.id)
    nodes = {k: v for tree in trees for k, v in tree.nodes.items()}
    links_of = {key_result_id: await _key_results(request).active_links(db, key_result)}
    result = await _key_results(request).retire(
        db,
        user.id,
        key_result,
        reason=body.reason,
        dry_run=body.dry_run,
        today=_today(request, user),
        nodes=nodes,
        links_of=links_of,
    )
    return _retire_answer(result.effect, result.batch_id)


@router.post("/annual/goals/{goal_id}/restore")
async def restore_goal(
    goal_id: uuid.UUID,
    request: Request,
    db: Db,
    user: CurrentUser,
) -> object:
    """Restore a retired goal and its key results."""
    return await _annual(request).restore_goal(db, user.id, goal_id, tz=user.timezone)


@router.post("/annual/key-results/{key_result_id}/restore")
async def restore_key_result(
    key_result_id: uuid.UUID,
    request: Request,
    db: Db,
    user: CurrentUser,
) -> object:
    """Restore a retired key result if a free slot exists."""
    key_result = await _key_results(request).get(db, user.id, key_result_id)
    _annual(request).require_open(key_result.year, tz=user.timezone)
    trees = await load_trees(db, user.id)
    return await _key_results(request).restore(db, user.id, key_result, trees=trees)


@router.put("/annual/key-results/{key_result_id}/themes")
async def set_key_result_themes(
    key_result_id: uuid.UUID,
    body: ThemeSetIn,
    request: Request,
    db: Db,
    user: CurrentUser,
) -> object:
    """Set the active theme links of one key result."""
    key_result = await _key_results(request).get(db, user.id, key_result_id)
    _annual(request).require_open(key_result.year, tz=user.timezone)
    trees = await load_trees(db, user.id)
    nodes = {k: v for tree in trees for k, v in tree.nodes.items()}
    batch_id = uuid.uuid4()
    effect = await _key_results(request).set_themes(
        db,
        user.id,
        key_result,
        body.theme_ids,
        dry_run=body.dry_run,
        trees=trees,
        today=_today(request, user),
        nodes=nodes,
        batch_id=batch_id,
    )
    if body.dry_run:
        return {"effect": effect}
    plan = await _plan_of(request, db, user, key_result.year)
    return {
        "batch_id": batch_id,
        "key_result": await _key_result_from_plan(plan, key_result_id),
    }


@router.post("/annual/undo")
async def undo_batch(
    body: UndoIn,
    request: Request,
    db: Db,
    user: CurrentUser,
) -> dict[str, int]:
    """Undo the changes of one batch."""
    count = await _annual(request).undo(db, user.id, body.batch_id, tz=user.timezone)
    return {"restored": count}


@router.post("/annual/themes", status_code=201)
async def create_theme(
    body: ThemeCreateIn,
    request: Request,
    db: Db,
    user: CurrentUser,
) -> object:
    """Create a theme project through the task app and label it as a theme."""
    return await _annual(request).create_theme(db, user.id, body.connection_id, body.name)


@router.post("/annual/key-results/{key_result_id}/values", status_code=201)
async def create_value(
    key_result_id: uuid.UUID,
    body: ValueIn,
    request: Request,
    db: Db,
    user: CurrentUser,
) -> object:
    """Store a manual value for a key result."""
    key_result = await _key_results(request).get(db, user.id, key_result_id)
    row, on_date = await _key_results(request).enter_value(
        db,
        user.id,
        key_result,
        body.value,
        body.on_date,
        tz=user.timezone,
        source=ValueSource.MANUAL,
    )
    plan = await _plan_of(request, db, user, key_result.year)
    return {
        "id": row.id,
        "value": row.value,
        "at": utc(row.at),
        "on_date": on_date,
        "source": row.source,
        "key_result": await _key_result_from_plan(plan, key_result_id),
    }
