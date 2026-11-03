# Implementation Plan: Split Tasks-and-Calendar Planning Layout

**Branch**: `002-split-planning-layout` | **Date**: 2026-11-02 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/002-split-planning-layout/spec.md`

## Summary

The default screen becomes a **planner**: a task column (filters, search, draggable tasks) on the
left and a time-grid calendar on the right. Dropping a task on a slot writes **only the Vikunja
due date** (constitution Principle VII). The calendar block is derived (due − 1h → due) and is
never stored as a separate Vikunja date.

The repository already has a list-style calendar with drag and drop that writes Vikunja
`start_date`/`end_date`. This feature changes that in four ways:

1. **Backend scheduling moves to the due date.** `PUT /tasks/{id}/schedule` writes `due_date`
   (and an all-day form for date-only drops). The Vikunja adapter stops writing and reading
   `start_date`/`end_date`. The block times are derived in one place in the domain layer.
2. **Task list API gains filters and search**: `due=today|tomorrow|week|all|none|overdue`, `q`,
   and a counts endpoint for the filter badges.
3. **One new per-user setting** (`random_time_on_date_drop`, default off) with a settings API.
4. **New Flutter planner screen** (two panes, time grid with 15-minute snapping, narrow-screen
   tabs) as the route `/`. The old Today view moves to `/daily`.

No new third-party dependency is needed on either side.

## Technical Context

**Language/Version**: Python 3.12 (backend); Dart/Flutter stable (frontend) — unchanged from
spec 001.

**Primary Dependencies**: Existing only: FastAPI, pydantic v2, SQLAlchemy 2.x, Alembic, httpx;
Flutter with Riverpod, go_router, dio. The time grid and drag handling use Flutter built-ins
(`Draggable`/`LongPressDraggable`, `DragTarget`, `CustomScrollView`).

**Storage**: One Alembic migration (`0006`): add `users.random_time_on_date_drop` (bool, default
false). No new table. `tasks.scheduled_start/scheduled_end` stay as cached, *derived* columns
(see research R-02).

**Testing**: pytest (unit, integration with mocked Vikunja HTTP, migration test with
pytest-alembic, e2e); `flutter test` widget tests for drag and drop, filters, search and the
narrow layout; Flutter golden tests that generate the new documentation screenshots.

**Target Platform**: As spec 001 (Linux desktop, Android, web). Two-pane layout at widths
≥ 840 dp, tabbed layout below.

**Project Type**: Web service + multi-platform client (existing repository layout).

**Performance Goals**: Filtered/search list responses < 200 ms p95 from the local cache for
2,000 tasks (SQLite). Drag feedback at 60 fps with a week of 100 blocks. SC-006: search to
first drag < 10 s with 200 open tasks (UI debounce 200 ms).

**Writing style**: ASD-STE100 for all new prose; Vale checks it (Principle VI).

**Constraints**: Due date is the only stored planning date for Vikunja. A failed write MUST NOT
leave the UI showing the task as scheduled (no optimistic state that survives an error).
Date-only is represented in the adapter, not in core logic (Principle IV).

**Scale/Scope**: One new screen, one settings entry, 3 changed endpoints, 2 new endpoints, one
migration, about 4 user-guide pages touched.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design. Checked against constitution v1.4.0.*

| Principle | Status | How the plan satisfies it |
|-----------|--------|---------------------------|
| I. Python backend, Flutter frontend | PASS | Backend changes in Python; the planner is Flutter. |
| II. Justfile is the single interface | PASS | No new commands. Existing recipes (`just backend::test`, `just frontend::test`, `just docs::screenshots`, `just lint`) cover all work. Docs and quickstart reference recipes only. |
| III. Reproducible environments via devbox | PASS | No new tool or dependency. |
| IV. Pluggable backends | PASS | Core works with a backend-neutral *planned time* (`due_at` plus `all_day`). The Vikunja adapter alone maps all-day to its due-date convention (R-03). Block derivation lives in `domain/`, not in the adapter. A contract test runs against the fake and the recorded Vikunja backend. |
| V. Documented, tested, CI-verified | PASS | Each requirement maps to a test (see Test Plan). Migration has an alembic test. Docs updated in the same change. |
| VI. Documentation for two audiences | PASS | New user guide `docs/user/planner.md` with screenshots (golden tests via `just docs::screenshots`, fake data, alt text); `scheduling.md`, `daily-planning.md`, `shortcuts.md`, `getting-started.md` updated; developer `architecture.md` gets the due-date rule and a diagram. |
| VII. Vikunja due date is canonical | PASS | Scheduling writes `due_date` only. Derived block times are not written back. The adapter no longer touches `start_date`/`end_date`. A contract test asserts that no request body written by a schedule call contains `start_date` or `end_date`. |

No violations, so Complexity Tracking is empty. Re-check after Phase 1 design: still PASS.

## Project Structure

### Documentation (this feature)

```text
specs/002-split-planning-layout/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── api.md          # changed and new endpoints (delta on spec 001 api.md)
├── checklists/requirements.md
└── tasks.md            # created later by /speckit-tasks
```

### Source Code (repository root)

```text
backend/
├── migrations/versions/0006_user_random_time_setting.py     # NEW
├── src/tefteri/
│   ├── domain/
│   │   ├── planning_time.py          # NEW: block derivation, all-day, 15-min snap, random pick
│   │   ├── entities.py               # RemoteTask: planned time = due_at + all_day
│   │   └── ports.py                  # TaskBackend.set_schedule -> set_planned_time(due_at, all_day)
│   ├── adapters/vikunja/adapter.py   # due_date only; all-day convention (R-03)
│   ├── services/
│   │   ├── tasks.py                  # schedule_at / schedule_date / unschedule; filters; counts
│   │   ├── mirror.py                 # derive scheduled_start/end from due_at
│   │   └── settings.py               # NEW: per-user settings
│   ├── db/models/user.py             # + random_time_on_date_drop
│   └── api/routers/
│       ├── tasks.py                  # due/q filters, /tasks/counts, schedule bodies
│       ├── calendar.py               # tasks from due_at, all-day items
│       └── settings.py               # NEW: GET/PATCH /me/settings
└── tests/
    ├── unit/test_planning_time.py                  # NEW
    ├── integration/test_scheduling.py              # CHANGED: due-date semantics
    ├── integration/test_task_filters.py            # NEW
    ├── integration/test_user_settings.py           # NEW
    ├── integration/adapters/test_vikunja_*.py      # CHANGED: no start/end writes
    └── migrations/                                  # CHANGED: 0006 round trip

frontend/lib/
├── app.dart                          # '/' -> PlannerScreen, '/daily' -> DailyScreen
├── core/shortcuts/keymap.dart        # Planner 'p', Day 't'
├── core/planning_api.dart            # filters/search/counts, schedule date/start, settings
└── features/planner/                 # NEW
    ├── planner_screen.dart           # two panes (>= 840 dp) or tabs
    ├── task_pane.dart                # filter chips with counts, search bar, draggable list
    ├── calendar_pane.dart            # week time grid, all-day row, drop targets
    ├── time_grid.dart                # layout math: offset <-> 15-min slot, overlap columns
    ├── planner_providers.dart        # active filter, query, week, load/refresh
    └── schedule_dialog.dart          # narrow/touch scheduling (date + time, 15-min steps)
frontend/lib/features/settings/       # + "Date-only drops get a random time" switch
frontend/test/features/planner/       # NEW widget tests
frontend/test/screenshots/planner_test.dart   # NEW goldens for docs

docs/user/planner.md                  # NEW; scheduling.md, daily-planning.md, shortcuts.md,
                                      #   getting-started.md, connect-apps.md? (no) updated
docs/developer/architecture.md        # due-date rule + planned-time diagram
docs/openapi.json                     # regenerated by `just backend::openapi`
```

**Structure Decision**: Reuse the existing backend/frontend layout. The planner is a new
feature folder in the client. The old `calendar` feature folder stays for the `/calendar` route
until the planner replaces it (see R-07).

## Test Plan (requirement → test)

| Requirement | Test |
|-------------|------|
| FR-001, FR-015 | widget: `/` shows task pane left, calendar right; nav still reaches other views |
| FR-002, FR-018 | integration: each `due` filter returns exactly the expected tasks and counts (clock injected); widget: chips mark the active filter |
| FR-019 | integration: `q` matches titles case-insensitively across all open tasks; widget: typing updates list, empty state, clear |
| FR-003 | widget: context filter and sync refresh both panes |
| FR-004, FR-008 | widget: drop at a slot calls API with that start; integration: stored due = start + 1h |
| FR-005 | integration + widget: move writes new due; drag back clears due |
| FR-006, FR-007 | contract: Vikunja write bodies contain `due_date` and never `start_date`/`end_date`; unit: block = [due−1h, due] |
| FR-009, FR-010 | integration: calendar endpoint returns timed blocks and all-day items from due dates set remotely, after sync |
| FR-011 | widget: task block and event card use different styles and overlaps are drawn side by side |
| FR-012, FR-013 | integration: backend failure → error with connection name, cache unchanged; remote change → conflict recorded |
| FR-014 | widget: narrow width shows tabs and the schedule dialog works without drag |
| FR-016 | docs build (`-W`), Vale, alt-text check, golden screenshots |
| FR-017 | unit: random start within 08:00–19:45, snapped to 15 min; integration: setting off → date-only, on → timed |
| Edge: due in first hour | unit: block clipped to 00:00 and marked "continues from previous day" |
| Edge: migration | pytest-alembic: upgrade/downgrade 0006 keeps users |

## Complexity Tracking

*Empty: no constitution violations.*
