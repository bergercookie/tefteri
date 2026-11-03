---

description: "Task list for the Split Tasks-and-Calendar Planning Layout"
---

# Tasks: Split Tasks-and-Calendar Planning Layout

**Input**: Design documents from `/specs/002-split-planning-layout/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/api.md, quickstart.md

**Tests**: Included. Constitution Principle V (non-negotiable) requires tests for all new behaviour. In each story the test tasks come first and MUST fail before the implementation.

**Documentation**: Constitution Principle VI applies. Each story ships its user guide change in ASD-STE100 with screenshots (golden tests, `just docs::screenshots`, fake data, alt text). Vale (`just lint`) and `just docs::build` MUST pass.

**Organization**: Tasks are grouped by user story (US1-US5, from spec.md). All commands run through `just` recipes (constitution Principle II). The Vikunja due date is the only stored planning date (constitution Principle VII): no task may write `start_date` or `end_date`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1 split view, US2 filters and search, US3 drag and drop scheduling, US4 dated tasks on the calendar, US5 small screens
- Paths are relative to the repository root

## Phase 1: Setup

**Purpose**: Confirm the starting point before changing behaviour

- [X] T001 Run `just backend::test` and `just frontend::test` on the branch and record the baseline in `specs/002-split-planning-layout/research.md` (one line under a new "Baseline" heading); fix nothing here
- [X] T002 [P] Record the Vikunja date-only check (research R-03) in `specs/002-split-planning-layout/research.md`: state clearly whether it was verified against a real Vikunja instance or only against the fake in `backend/tests/fakes/http/vikunja.py`, and keep the all-day constants in one place (`backend/src/tefteri/adapters/vikunja/adapter.py`)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Move scheduling to the due date, derive blocks in one place, add the setting and the shared client plumbing. No user story can finish before this phase.

**CRITICAL**: Complete before any user story.

### Tests first

- [X] T003 [P] Write `backend/tests/unit/test_planning_time.py`: `block_for` returns `[due-1h, due]`; a timed due in the first hour of the day gives `clipped_start=True` and start 00:00; all-day gives no block; `snap_to_quarter` rounds to the nearest 15 minutes; `pick_random_start` returns only 15-minute marks from 08:00 to 19:45 local time (the start lies within 08:00 to 20:00, FR-017); fixed `random.Random(seed)` makes it exact; DST-day time zones (for example Europe/Athens) keep local times
- [X] T004 [P] Update `backend/tests/integration/adapters/test_vikunja.py`: replace `test_set_schedule_writes_start_and_end` with tests that `set_planned_time` writes only `due_date` (assert the request body has no `start_date` or `end_date`), that clearing writes a null due date, that an all-day date is written as 00:00 in the user's time zone, and that a read of a due date at exactly 00:00 local gives `all_day=True`
- [X] T005 [P] Update `backend/tests/integration/test_backend_contracts.py` and `backend/tests/fakes/memory.py` so the in-memory fake and the Vikunja fake pass the same `set_planned_time` contract (timed, all-day, clear, version conflict)
- [X] T006 [P] Add a pytest-alembic case for migration `0006` in `backend/tests/migrations/` (upgrade adds `users.random_time_on_date_drop` with default false and keeps existing users; downgrade removes it)
- [X] T007 [P] Write `backend/tests/integration/test_user_settings.py`: `GET /me/settings` returns `{"random_time_on_date_drop": false}` by default; `PATCH` changes it; unknown fields give 422; a user cannot read or change another user's setting

### Implementation

- [X] T008 Create `backend/src/tefteri/domain/planning_time.py` with pure functions `block_for`, `snap_to_quarter`, `pick_random_start(day, tz, rng)` and a `TaskBlock` dataclass (`start`, `end`, `clipped_start`), with docstrings; it MUST NOT import from `adapters`, `db` or `services` (tach)
- [X] T009 Change `TaskBackend` in `backend/src/tefteri/domain/ports.py`: replace `set_schedule(remote_id, start, end, expected_version)` with `set_planned_time(remote_id, due_at, all_day, expected_version)`; `due_at=None` clears; update the docstring to say the due date is the only planning date
- [X] T010 Change `RemoteTask` in `backend/src/tefteri/domain/entities.py`: remove `scheduled_start` and `scheduled_end` (they are derived now); keep `due_at` and `all_day`
- [X] T011 Update the Vikunja adapter in `backend/src/tefteri/adapters/vikunja/adapter.py`: stop reading `start_date` and `end_date` in `_task`; implement `set_planned_time` writing only `due_date`; encode all-day as 00:00 in the user's time zone and decode a due time of exactly 00:00 local as `all_day=True` (constants in one place, see T002); update `capabilities()` text
- [X] T012 [P] Update `backend/tests/fakes/memory.py` and `backend/tests/fakes/http/vikunja.py` to match T009 to T011
- [X] T013 Update `backend/src/tefteri/services/mirror.py` so `task_values` sets `scheduled_start = due_at - 1h` and `scheduled_end = due_at` for a timed due date, and null for all-day or no due date (data-model.md, "Task (cached mirror)")
- [X] T014 Add migration `backend/migrations/versions/0006_user_random_time_setting.py` adding `users.random_time_on_date_drop` as a boolean, `server_default` false, not null; add the field to `backend/src/tefteri/db/models/user.py` with a docstring
- [X] T015 [P] Create `backend/src/tefteri/services/settings.py` (get and update the per-user setting) and `backend/src/tefteri/api/routers/settings.py` (`GET` and `PATCH /me/settings`, pydantic body with `extra="forbid"`); register the router in `backend/src/tefteri/main.py` and keep `tach.toml` valid
- [X] T016 Rework `TaskService.set_schedule` in `backend/src/tefteri/services/tasks.py` into `schedule_at(start)` (due = snapped start + 1h), `schedule_date(date)` (all-day, or random timed start when the user's setting is on, using an injected `random.Random`) and `unschedule()`; all call `set_planned_time`; keep the "write to the app first, then cache" order, the overlap result and the conflict handling
- [X] T017 Update `backend/src/tefteri/api/routers/tasks.py`: `PUT /tasks/{id}/schedule` takes exactly one of `{start}` or `{date}` (422 otherwise, the old `end` field is removed); `DELETE` unchanged; keep the response `{task, overlaps}`
- [X] T018 [P] Update the Flutter client plumbing in `frontend/lib/core/planning_api.dart` and `frontend/lib/core/planning_models.dart`: `scheduleTaskAt(id, start)`, `scheduleTaskOnDate(id, date)`, `unscheduleTask`, `taskCounts(context)`, `tasks(due:, q:, context:)`, `getSettings`, `updateSettings`; `CalendarItem` gets `allDay` and `clippedStart`
- [X] T019 [P] Create the pure layout functions in `frontend/lib/features/planner/time_grid.dart` (`offsetToMinutes`, `snapMinutes(15)`, `minutesToOffset`, `layoutOverlaps` giving each block a column index and column count) and their tests in `frontend/test/features/planner/time_grid_test.dart`
- [X] T020 Run `just backend::test`, `just backend::openapi` and `just lint`; commit `docs/openapi.json` with the new contract

**Checkpoint**: Backend schedules by due date only; clients can call the new API; layout maths is tested.

---

## Phase 3: User Story 1 - Plan my day in a task-and-calendar split view (Priority: P1) 🎯 MVP

**Goal**: The default screen shows tasks on the left and the calendar on the right.

**Independent Test**: Open the app with connected apps. The first screen has a task list on the left and a calendar on the right, both with real data. The work/life filter and sync update both. Other views still open.

### Tests for User Story 1 ⚠️

- [X] T021 [P] [US1] Widget test in `frontend/test/features/planner/planner_screen_test.dart`: at width 1200 `/` shows `task-pane` left of `calendar-pane`; the context filter and the sync button reload both panes (FR-001, FR-003)
- [X] T022 [P] [US1] Widget test in `frontend/test/shell_test.dart` (changed): navigation reaches Day, Week, Month, Year, Goals, Reviews, Notes; the planner is reachable again from the drawer (FR-015)
- [X] T023 [P] [US1] Update `frontend/test/core/shortcuts_test.dart`: `p` opens the planner, `t` opens the day view

### Implementation for User Story 1

- [X] T024 [P] [US1] Create `frontend/lib/features/planner/planner_providers.dart`: week start, selected task, and loaders for tasks and calendar items that reload when the context filter or a sync changes
- [X] T025 [P] [US1] Create `frontend/lib/features/planner/task_pane.dart` with a plain task list (no filters yet) of open tasks, each marked scheduled or unscheduled (FR-002)
- [X] T026 [P] [US1] Create `frontend/lib/features/planner/calendar_pane.dart` with a week time grid built on `time_grid.dart`: day columns, hour lines, calendar entries and task blocks drawn in different styles, an all-day row (display only in this story)
- [X] T027 [US1] Create `frontend/lib/features/planner/planner_screen.dart` using `AppShell`: a `Row` of `task-pane` (fixed width 360 dp) and `calendar-pane` (expanded); full narrow handling comes in US5
- [X] T028 [US1] Update `frontend/lib/app.dart`: `/` builds `PlannerScreen`, `/daily` builds `DailyScreen`, `/calendar` redirects to `/`; update `frontend/lib/core/shortcuts/keymap.dart` (`Planner` `/` `p`, `Day` `/daily` `t`) and fix the existing daily tests that assume `/`
- [X] T029 [P] [US1] Create `frontend/test/screenshots/planner_test.dart` (golden, fake data, wide layout) to generate `docs/images/planner-split.png`
- [X] T030 [P] [US1] Write `docs/user/planner.md` (STE): what the planner is, what the two columns show, how work/life and sync apply to both; add it to `docs/user/index.md`; update `docs/user/getting-started.md` and `docs/user/shortcuts.md` (`p` and `t`); every image has alt text

**Checkpoint**: US1 works alone. Tasks and calendar show side by side; no scheduling yet.

---

## Phase 4: User Story 3 - Drag a task onto the calendar to schedule it (Priority: P1)

**Goal**: One drag schedules a task. Moves and "back to the list" work. Errors are clear.

**Independent Test**: Drag an undated task onto a slot. The block shows there and, after sync, Vikunja has due = slot + 1h and no start or end date.

### Tests for User Story 3 ⚠️

- [X] T031 [P] [US3] Integration test in `backend/tests/integration/test_scheduling.py` (changed): `schedule_at` stores due = start + 1h and rounds to 15 minutes (FR-008); a move stores the new due (FR-005); `DELETE` clears the due date; the response lists overlapping calendar entries; no request to Vikunja contains `start_date` or `end_date` (FR-006)
- [X] T032 [P] [US3] Integration test in `backend/tests/integration/test_scheduling.py`: `{date}` stores an all-day due by default; with `random_time_on_date_drop` on and a fixed rng it stores a timed due whose block starts between 08:00 and 19:45 (FR-017)
- [X] T033 [P] [US3] Integration test in `backend/tests/integration/test_scheduling.py`: Vikunja unreachable gives the error with connection name and reason, and the cached task is unchanged (FR-012); a remote change since the last sync records a conflict and does not overwrite (FR-013)
- [X] T034 [P] [US3] Widget tests in `frontend/test/features/planner/drag_drop_test.dart`: dropping a task on Wednesday 14:00 calls `scheduleTaskAt` with 14:00; dragging a block to another slot calls it with the new start; dragging a block onto the task pane calls `unscheduleTask`; a drop on the all-day row calls `scheduleTaskOnDate`; an API error shows the banner and the task is not shown as scheduled (FR-004, FR-005, FR-012, FR-017)
- [X] T035 [P] [US3] Widget test in `frontend/test/features/planner/overlap_test.dart`: a task dropped on a slot that holds an entry shows both blocks side by side (FR-011)

### Implementation for User Story 3

- [X] T036 [US3] Add drag sources in `frontend/lib/features/planner/task_pane.dart` and in task blocks of `calendar_pane.dart` (`Draggable` on desktop and web, `LongPressDraggable` on touch), with a pending state while the request runs
- [X] T037 [US3] Add one `DragTarget` per day column and one for the all-day row in `frontend/lib/features/planner/calendar_pane.dart`; convert the drop offset with `time_grid.dart` to a 15-minute start; show a ghost block during the drag; add a `DragTarget` on `task_pane.dart` for unscheduling
- [X] T038 [US3] Wire drops to the API with no optimistic state in `frontend/lib/features/planner/planner_providers.dart`: show the block only after success; on error show the existing `ErrorBanner` with the server message and reload from the cache
- [X] T039 [P] [US3] Add the "Date-only drops get a random time" switch (default off) to `frontend/lib/features/settings/connections_screen.dart` (or a new `planner_settings_card.dart` in the same folder) backed by `GET` and `PATCH /me/settings`, with a widget test in `frontend/test/features/settings/`
- [X] T040 [P] [US3] Add golden screenshots to `frontend/test/screenshots/planner_test.dart` (drag in progress, block placed, error banner, settings switch) and write the matching steps in `docs/user/planner.md`; rewrite `docs/user/scheduling.md` for due-date scheduling (drag, move, drag back, date-only drops, random-time setting, the "due time is one hour after the slot" rule, the 00:00 note and the upgrade note from research R-02)

**Checkpoint**: US1 and US3 work together: the MVP scheduling loop is complete.

---

## Phase 5: User Story 4 - See already-dated tasks in the right slot (Priority: P1)

**Goal**: Tasks with a due date or datetime, set anywhere, show in the right slot after load and sync.

**Independent Test**: Set due dates and times in Vikunja, sync, and see each task in the calendar at the right slot or in the all-day row.

### Tests for User Story 4 ⚠️

- [X] T041 [P] [US4] Integration test in `backend/tests/integration/test_calendar_tasks.py`: tasks with a timed due date appear as `type: task` items with `start = due-1h` and `end = due`; a due time in the first hour of the day sets `clipped_start`; date-only tasks appear with `all_day: true`; done tasks carry their done status; tasks without a due date do not appear (FR-007, FR-009, FR-010)
- [X] T042 [P] [US4] Integration test in `backend/tests/integration/test_connections_sync.py` (changed): after a sync, a due date set in the fake Vikunja shows in `GET /calendar` and a due date removed there disappears (SC-002)
- [X] T043 [P] [US4] Widget tests in `frontend/test/features/planner/dated_tasks_test.dart`: timed block at the right offset and height; all-day item in the all-day row; done state shown; "continues from previous day" marker; task and event styles differ (FR-011)

### Implementation for User Story 4

- [X] T044 [US4] Update `backend/src/tefteri/api/routers/calendar.py` and `backend/src/tefteri/api/schemas.py` (`CalendarItem.of_task`) to build task items from `due_at` with `planning_time.block_for`, add `all_day` and `clipped_start`, and apply the user's time zone for the day split
- [X] T045 [P] [US4] Update the other readers that used `scheduled_start or due_at` to use the shared helper, so all views agree: `backend/src/tefteri/api/routers/views.py`, `backend/src/tefteri/api/routers/planning.py`, `backend/src/tefteri/services/reviews.py`, and `backend/src/tefteri/api/routers/tasks.py` (`unscheduled` means `due_at` is null)
- [X] T046 [US4] Draw timed blocks, all-day items, the done state and the clipped marker in `frontend/lib/features/planner/calendar_pane.dart`
- [X] T047 [P] [US4] Add golden screenshots (dated tasks, all-day row, overlap with an event) to `frontend/test/screenshots/planner_test.dart` and describe them in `docs/user/planner.md` and `docs/user/daily-planning.md`

**Checkpoint**: The calendar shows every dated task in the right place.

---

## Phase 6: User Story 2 - Find the right task with filters and search (Priority: P1)

**Goal**: Clickable filters with counts and a search bar at the top of the task column.

**Independent Test**: With tasks due on different days, each filter lists exactly the matching open tasks; searching finds a task by title and it can be dragged to a slot.

### Tests for User Story 2 ⚠️

- [X] T048 [P] [US2] Integration test in `backend/tests/integration/test_task_filters.py` with an injected clock and a non-UTC user time zone: `today`, `tomorrow`, `week` (Monday to Sunday), `all`, `none`, `overdue` return exactly the expected open tasks; done tasks never appear; all-day tasks count for their date; an all-day task due today is not overdue; a timed task due earlier today is overdue (FR-018)
- [X] T049 [P] [US2] Integration test in `backend/tests/integration/test_task_filters.py`: `GET /tasks/counts` equals the list length for each filter and respects `context`; `q` matches titles case-insensitively across all open tasks and ignores `due`; no match gives an empty list; the work/life filter still applies (FR-019)
- [X] T050 [P] [US2] Widget tests in `frontend/test/features/planner/task_pane_test.dart`: six chips with counts; "Today" is active at start; the active chip is marked; typing in the search bar (200 ms debounce) updates the list and ignores the chip; no results shows the empty message and a clear button; clearing returns to the active filter; a found task can be dragged (US3 drag test reuses it) (FR-018, FR-019)

### Implementation for User Story 2

- [X] T051 [US2] Add `due` and `q` parameters and `GET /tasks/counts` to `backend/src/tefteri/api/routers/tasks.py`; put the filter logic in `backend/src/tefteri/services/tasks.py` (or a new `backend/src/tefteri/services/task_filters.py`) using the user's time zone and an injectable clock; default `status` to `open` when `due` or `q` is used
- [X] T052 [US2] Add the filter chips with counts and the search bar to `frontend/lib/features/planner/task_pane.dart`; keep filter and query in `planner_providers.dart` (default `today`); refresh counts after every schedule change and sync
- [X] T053 [P] [US2] Add golden screenshots (each filter, search with results, empty search) to `frontend/test/screenshots/planner_test.dart` and document the filters and search in `docs/user/planner.md`; list the six filters, the "week starts on Monday" rule and that search covers all open tasks

**Checkpoint**: Planning from a long list is quick.

---

## Phase 7: User Story 5 - Use the layout on small screens (Priority: P3)

**Goal**: Below 840 dp, tabs replace the two columns and a Schedule action replaces drag and drop.

**Independent Test**: In a narrow window both views are reachable and a task can be scheduled in three steps or fewer.

### Tests for User Story 5 ⚠️

- [X] T054 [P] [US5] Widget tests in `frontend/test/features/planner/narrow_layout_test.dart`: at width 400 two tabs (Tasks, Calendar) show; filter, search text and week survive a tab switch; "Schedule…" on a task opens the dialog; choosing a date and a time in 15-minute steps calls `scheduleTaskAt`; scheduling takes three steps or fewer (Schedule…, choose the time, confirm) (FR-014, SC-005)

### Implementation for User Story 5

- [X] T055 [US5] Make `frontend/lib/features/planner/planner_screen.dart` switch with `LayoutBuilder` at 840 dp between the two-pane `Row` and a `TabBar`/`TabBarView` that keeps state (`AutomaticKeepAliveClientMixin`)
- [X] T056 [US5] Create `frontend/lib/features/planner/schedule_dialog.dart` (date and a time list in 15-minute steps) based on the existing dialog in `frontend/lib/features/calendar/calendar_screen.dart`; add a "Schedule…" action to each task row (slot-tap scheduling was dropped: the dialog is enough for FR-014)
- [X] T057 [P] [US5] Add a narrow golden screenshot to `frontend/test/screenshots/planner_test.dart` and a "Use the planner on a phone" section in `docs/user/planner.md`

**Checkpoint**: All five stories work.

---

## Phase 8: Polish & Cross-Cutting Concerns

- [X] T058 Remove the old list calendar: delete `frontend/lib/features/calendar/calendar_screen.dart` and its tests once nothing imports it (keep the `/calendar` redirect for one release); move any still-used helper such as `ScheduleDialog` before deleting
- [X] T059 [P] Update `docs/developer/architecture.md` with the due-date rule, a Mermaid diagram of "drop → due date → derived block" and the layer that owns each step; update `docs/developer/adding-an-adapter.md` with the `set_planned_time` contract and the all-day mapping each adapter must provide
- [X] T060 [P] Add release notes text for the upgrade note (tasks scheduled only through Vikunja start and end dates show as unscheduled) in `docs/developer/releases.md` and `docs/user/troubleshooting.md`
- [X] T061 [P] Update `specs/001-daily-planning-framework/contracts/api.md` and `contracts/backend-ports.md` to point to spec 002 for `PUT /tasks/{id}/schedule`, the calendar task items and `set_planned_time`
- [X] T062 Performance checks: add a test in `backend/tests/integration/test_task_filters.py` that lists 2,000 tasks with a filter and with `q` in under 200 ms p95 on SQLite (mark it like the existing performance tests); add a widget test that a week with 100 blocks builds without overflow
- [X] T063 Run the full gate: `just lint`, `just test`, `just docs::screenshots` (commit the images), `just docs::build`, `just backend::openapi` (commit `docs/openapi.json`) **Run partly:** `just lint` (pre-commit) could not run in the build container, because yamllint, markdownlint, Vale, shellcheck, taplo and hadolint are not installed there. These ran instead: `ruff check`, `ruff format --check`, `mypy`, `tach check`, `dart format --set-exit-if-changed`, `flutter analyze`, `just docs::build` (with `-W`), `scripts/check_docs.sh`, and a small script that applies the STE rules of `.vale/styles/STE` (0 findings). The 3 Postgres tests were not run (no Postgres). Run `just lint` and `just backend::test-postgres` before merging.
- [X] T064 Walk through `specs/002-split-planning-layout/quickstart.md` against the e2e fake world (extend `backend/tests/e2e/test_daily_flow.py` with a planner scenario for steps 3 to 7) and note any gap in `research.md`

---

## Dependencies & Execution Order

- **Setup (Phase 1)** → **Foundational (Phase 2)** → user stories → **Polish (Phase 8)**.
- **US1** needs Foundational only (it is the MVP shell).
- **US3** needs US1 (panes) and the Foundational backend.
- **US4** needs US1; it can run in parallel with US3 (T044 and T045 are backend-only; T046 edits `calendar_pane.dart`, so run it after T037).
- **US2** needs US1; it can run in parallel with US3 and US4, but T052 edits `task_pane.dart` (after T036).
- **US5** needs US1, US2 and US3 (it re-arranges the finished panes).
- Inside a story: tests first (they must fail), then implementation.

### Parallel examples

- Foundational tests T003 to T007 can all be written at the same time (separate files).
- T018 and T019 (client plumbing and layout maths) run in parallel with T008 to T017 (backend).
- US3 tests T031 to T035 run in parallel. US4 backend tasks T044 and T045 run while T036 to T038 are in progress.
- Screenshot and docs tasks T029/T030, T040, T047, T053 and T057 are parallel to code work in other files, but they all edit `planner_test.dart` and `docs/user/planner.md`, so merge them one story at a time.

## Implementation Strategy

1. **MVP**: Phases 1 to 4 (US1 + US3). The user can see the split view and drag a task to schedule it by due date.
2. Add US4 so every dated task shows in the right slot, then US2 for filters and search.
3. Finish with US5 (small screens) and Polish.
4. Commit after each phase. After each phase run `just lint` and the tests of the touched area.
