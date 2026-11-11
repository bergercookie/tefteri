# Implementation Plan: Annual Planning, Goals and Key Results

**Branch**: `006-annual-planning` (developed on the session branch) | **Date**: 2026-11-11 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/006-annual-planning/spec.md`, the decisions in `specs/planning-cycles/decisions.md`, and the finished feature 003 (`specs/003-project-classification/`).

## Summary

Change the existing goals code in place so that goals exist only for a planning year. A goal keeps its row in `goals`. It gains up to three key results (a number with a start value, a target and a deadline), a dated series of values, and per-year links from each key result to theme projects. The links, the retirements and every edit are kept as history. The planning screen shows three flags (no key result, no usable theme, overdue), all warnings that never block. A missing theme is created with the shared "create project and label it" rule of feature 003. A new year is seeded from year N (default: the year before) with the rule "unmet = last value did not reach the target". The user enters values by hand. An automatic key result also accepts one inbound push (one token per user, key result id, value, time stamp). A past year allows value entry only. Month and week goals leave the flow: existing rows stay as read-only history, and the weekly planning, the month and week views and the look-back stop offering goals. One migration, `0020_annual_planning`, adds the tables and keeps every existing goal, task link and stored period review.

## Technical Context

**Language/Version**: Python 3.13 (backend), Dart 3.13 / Flutter 3.47 (client)

**Primary Dependencies**: FastAPI, SQLAlchemy 2 async, Alembic, httpx (existing); flutter_riverpod, go_router, dio (existing). No new dependency.

**Storage**: SQLite or PostgreSQL through Alembic. Migration `0020_annual_planning` ([data-model.md](data-model.md)) adds three columns to `goals` and five tables: `key_results`, `key_result_values`, `key_result_themes`, `plan_changes`, `value_push_tokens`. Numbers are stored as double precision (`Float`), checked to be finite.

**Testing**: pytest (unit, integration with in-memory fakes, e2e, migrations incl. Postgres, OpenAPI snapshot), `flutter test` widget tests with `fake_api.dart`, screenshot tests, a Playwright walkthrough against a seeded live Vikunja.

**Target Platform**: Linux server in a container; Flutter web, Linux and Android clients.

**Project Type**: Web service plus Flutter client (existing layout).

**Performance Goals**: The plan of one year (10 goals, 30 key results, 100 links, 2000 values) loads in under 500 ms on SQLite. The suggestions of year N load in under 2 s (SC-006). A pushed value is the current value on the next read, within 5 s (SC-007).

**Constraints**: No Vikunja name in core (`tach`). No task or project is written to the task app, except the creation of a theme through feature 003. Theme tokens only in the UI. Docs in ASD-STE100. No flag or limit blocks a save (FR-014, FR-032). A goal never has more than three active key results, also under concurrent saves (SC-008).

**Scale/Scope**: One user has a few goals per year and at most three key results per goal. 1 migration, 5 new tables, 3 new columns, 3 services, 2 routers, 2 pure domain modules, 1 screen with about 12 widgets, 3 doc pages.

## Constitution Check

| Principle | Status | How |
|---|---|---|
| I. Python backend, Flutter frontend | Pass | Same stack. |
| II. Justfile is the single interface | Pass | Every command in the quickstart is a `just` recipe. The demo seed for the walkthrough gets the recipe `just backend::seed-demo` (task T098), not a raw script call. |
| III. Devbox | Pass | No new tool. The session helper `source /root/tefteri-env.sh` stands in for `devbox shell`. |
| IV. Pluggable backends | Pass | The core (`domain`, `services`, `db`, `api`) never names a task app. Themes are read from `project_labels` (feature 003) and created through `ClassificationService.create_and_label`, which uses the `TaskBackend` port. The inbound push is a plain HTTP contract, not an adapter. Check: `grep -ri vikunja backend/src/tefteri --include=*.py -l` lists only `adapters/vikunja`, `config` and the registry, as before. |
| V. Documented, tested, CI-verified | Pass | Tests first in every phase. Migration test with counts before and after (SC-004). OpenAPI snapshot. Docstrings on all public items. Regression tests for the three flags and for the limit of three under concurrency. |
| VI. Two-audience docs, STE, screenshots | Pass | `docs/user/annual-planning.md` and `docs/developer/annual-planning.md`, with screenshots by `just docs::screenshots` from fake data and alt text. Vale and markdownlint run in `just lint`. Every doc that describes month or week goals is changed in the same change (FR-031). |
| VII. Due date is canonical | Pass | A key result deadline is a Tefteri value, not a task date. No Vikunja field is written. |

**Layer gates (tach)**: `tefteri.domain` has no dependency. `domain/key_results.py` and `domain/annual_plan.py` import only the standard library and `domain/enums.py` and `domain/classification.py`. `tefteri.db` models import `tefteri.db` and `tefteri.domain` only. `tefteri.services` imports `domain`, `db`, `auth` and `security`. `tefteri.api` imports services, never an adapter. The new token helper goes into `tefteri.security` (no dependency). `tach check` must pass at the end of every milestone.

**Theme-token gate (frontend)**: all new UI takes colors, fonts, spacing and radii from `context.tefteri`, `Space` and `Corner`. It uses `EmptyState` and `Loading`. `frontend/test/theme/design_rules_test.dart` must pass. No Material default: no stock app bar, no elevated card or bare list tile as the main structure.

Re-check after design: Pass. No complexity violations (see Complexity Tracking).

## Design decisions in short

The reasons and rejected options are in [research.md](research.md).

- **In place, not rebuilt** (R-01): `goals` stays. Year rows become annual goals. Month and week rows are never read by new flows and have no write route.
- **Derived current value** (R-02): the current value is the latest value of the series, or the start value when the series is empty. It is never stored on the key result.
- **Limit of three by a slot column** (R-03): `key_results.slot` (1 to 3, null when retired) with a unique constraint on (`goal_id`, `slot`). Two concurrent adds cannot both win on SQLite or on PostgreSQL.
- **Links as rows with dates** (R-04): `key_result_themes` rows with `started_at` and `ended_at`. Nothing is deleted. A partial unique index allows one active link per key result and project.
- **One history table** (R-05): `plan_changes`, append-only, one `batch_id` per user action. Undo adds new rows and never edits old ones, the same pattern as feature 003.
- **Push token** (R-07): one row per user in `value_push_tokens`, only the SHA-256 is stored. The token works only on the push route.
- **Past year** (R-09): value entry allowed, every structure change refused with `past_year`.
- **Seeding** (R-10): computed on read, never stored. Accepting creates real rows in one batch.

## Changes to existing behaviour

### Data migration plan for existing goals

Migration `0020_annual_planning` runs in this order. Every step is covered by a test in `backend/tests/migrations/test_migrations.py` (T012 to T015).

1. Add `updated_at`, `retired_at`, `retired_reason` and `position` to `goals`, and the index `ix_goals_user_period` on (`user_id`, `period_type`, `period_start`). `updated_at` is set to the migration time for every existing row.
2. Create the five new tables.
3. Year goals (`period_type = 'year'`): keep the row, the title, the description, the criteria text, the id and every `tasks.goal_id` link. Status `active` stays `active`. Status `dropped` becomes `retired`, with `retired_at` set to the migration time and `retired_reason` set to `Dropped before annual planning`. Status `done` stays `done`. The annual plan treats `done` like `active` and shows the note "Marked complete before annual planning". Reason: a stored period review can still be refreshed, and it counts `done` as completed (R-01).
4. For each year goal whose status changed or that has a criteria text, write one `plan_changes` row with `kind = 'migrated'`, `source = 'migration'`, the old status in `old_value`, and no key result. The row makes the move visible in the history of the year.
5. Month and week goals: no change at all. Not the row, not the status, not the parent link, not the `tasks.goal_id` links. They are read only through `GET /goals/history`.
6. `period_reviews` and `plans`: no change. A stored review loads as before (FR-027).
7. No key result is created. The criteria text is offered as a suggestion for the metric of a new key result (FR-024) while the goal has no key result.
8. Downgrade: drop the five tables and the four columns, set `retired` year goals back to `dropped`. Key results, values, links and history are lost on downgrade. The migration test says so.

The check for SC-004: the test builds a copy of data with year, month and week goals, goal-linked tasks and stored reviews, counts rows before and after upgrade, and asserts equal counts and equal ids, titles, criteria, parents and links.

### Existing code that changes

| File | Change |
|---|---|
| `backend/src/tefteri/db/models/goal.py` | Add `updated_at`, `retired_at`, `retired_reason`, `position`. Update the docstrings: annual only, month and week rows are history. |
| `backend/src/tefteri/db/models/__init__.py` | Export the new models. |
| `backend/src/tefteri/services/goals.py` | Remove `create`, `create_many`, `update`, `breakdown`, `delete`, `ChildGoal`, `ChildTask`. Keep `compute_progress` (stored reviews use it), `get`, `all`, `progress` (read only), and the plan functions. |
| `backend/src/tefteri/services/reviews.py` | `compute_review` skips goals with status `retired` as well as `dropped`. Nothing else changes. |
| `backend/src/tefteri/api/routers/planning.py` | Remove the goal routes (`POST /goals`, `POST /goals/bulk`, `PATCH /goals/{id}`, `DELETE /goals/{id}`, `POST /goals/{id}/breakdown`) and the `GoalIn`, `GoalsIn`, `GoalPatch`, `ChildGoalIn`, `ChildTaskIn`, `BreakdownIn`, `BreakdownOut` models. Replace `GET /goals` by `GET /goals/history` (read only, legacy rows). Remove `goals` from `PeriodView` and `PlanOut`; add `goal_titles` to `PeriodView`. Keep `/plans` and the three views. |
| `backend/src/tefteri/api/routers/tasks.py` | Check the goal on `PATCH /tasks/{id}` with `AnnualPlanService.linkable_goal` (an active annual goal of the current year, or clearing, or the unchanged value). |
| `backend/src/tefteri/api/routers/reviews.py` | No code change. A test proves that it still loads old reviews. |
| `backend/src/tefteri/api/schemas.py` | No change to `TaskOut.goal_id`. |
| `backend/src/tefteri/main.py` | Create and register `AnnualPlanService`, `KeyResultService`, `PushTokenService`; include the new routers. |
| `backend/tests/unit/test_goals.py` | Keep the period and progress tests. Add a test that `compute_progress` is unchanged for retired goals. |
| `backend/tests/integration/test_planning.py` | Rewrite. Drop the hierarchy, breakdown, delete and status tests (the routes are gone). Keep and update the plans, views and isolation tests. |
| `backend/tests/integration/test_goal_bulk_and_criteria.py` | Delete. Replaced by `test_annual_plan.py` and `test_legacy_goals.py`. |
| `backend/tests/integration/test_reviews.py`, `test_review_performance.py` | Seed goals with the helper `legacy_goal()` in `backend/tests/integration/conftest.py` (direct rows), because the write routes are gone. Add a retired-goal case. |
| `backend/tests/integration/test_isolation.py` | Replace the goal calls with the annual routes. Add key results, values, links and the push token. |
| `backend/tests/e2e/test_postgres_app.py` | Replace `POST /goals` and the progress assertions (lines 84 to 101) with an annual goal, a key result and a value. |
| `backend/tests/migrations/test_migrations.py` | Add the 0020 tests. |
| `docs/openapi.json` | Regenerate. |
| `frontend/lib/core/planning_api.dart`, `planning_models.dart` | Remove goal create, bulk, update, status, delete, breakdown and `PlanGoal`, `GoalDraft`; `PeriodView` loses `goals`. `linkTaskToGoal` stays. |
| `frontend/lib/features/goals/*` | Delete `goals_screen.dart`, `goal_dialog.dart`, `breakdown_dialog.dart`, `goal_widgets.dart`, `goal_providers.dart`. Move `periods.dart` to `frontend/lib/core/periods.dart` and `period_page.dart` to `frontend/lib/features/period/period_page.dart`. |
| `frontend/lib/features/week/week_screen.dart`, `month/month_screen.dart`, `year/year_screen.dart` | No goal section. The year screen shows the annual plan read only, with a link to it. The week screen keeps the task link to an annual goal. |
| `frontend/lib/features/weekly/weekly_card.dart`, `weekly_screen.dart`, `weekly_widgets.dart`, `review/plan_history_screen.dart`, `review/review_screen.dart` | Only the import of `periods.dart` changes. A test proves that no goal is offered. |
| `frontend/lib/features/review/review_screen.dart`, `review_models.dart` | The text "planned goals" stays for stored reviews and reads "goals (history)" for month and week plans. |
| `frontend/lib/app.dart`, `core/shell.dart`, `core/shortcuts/keymap.dart` | The route `/goals` becomes `/annual` (a redirect keeps old links). The view `Goals` becomes `Annual plan`, key `g` stays. |
| `frontend/lib/features/settings/checklists_screen.dart` | The example items say "Review the goals of the year" only for the year list. The month example no longer mentions goals. |
| `frontend/test/support/fake_api.dart` | Remove `goalJson`, `goals` in `periodJson`. Add annual fixtures. |
| `frontend/test/features/goals/goals_screen_test.dart` | Delete. Replaced by `test/features/annual/*`. |
| `frontend/test/features/week/week_screen_test.dart`, `month/month_screen_test.dart`, `year/year_screen_test.dart` | Update: no goals in week and month; annual summary in year. |
| `frontend/test/features/review/review_screens_test.dart`, `test/screenshots/review_test.dart` | Update the fixtures that use `goalJson`. |
| `frontend/test/shell_test.dart`, `test/core/shortcuts_test.dart`, `test/core/new_task_shortcut_test.dart`, `test/today_button_test.dart`, `test/app_routes_test.dart` | Update the route `/goals`, the label `Goals`, and the import of `periods.dart`. |
| `frontend/test/screenshots/planning_test.dart`, `planner_test.dart` | Remove the goals and breakdown screenshots. Regenerate week, month, year. |
| `docs/user/planning-goals.md` | Renamed to `docs/user/annual-planning.md` and rewritten. The checklist section moves to `docs/user/planning-checklists.md`. |
| `docs/user/index.md`, `getting-started.md`, `weekly-planning.md`, `reviews-and-retrospectives.md`, `shortcuts.md`, `accounts-and-sign-in.md` | Change the links and the sentences about month and week goals. |
| `docs/developer/index.md`, `architecture.md`, `weekly-planning.md`, `testing.md` | Add the new guide, the tables and the tests; remove month and week goals. |
| `scripts/check_docs.sh` | Required list: replace `user/planning-goals.md` by `user/annual-planning.md` and `user/planning-checklists.md`. |
| `docs/images/` | Remove `planning-goals.png`, `planning-breakdown.png`. Regenerate `planning-week.png`, `planning-month.png`, `planning-year.png`. Add `annual-*.png`. |

## Project Structure

### Documentation (this feature)

```text
specs/006-annual-planning/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/api.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
backend/
├── migrations/versions/0020_annual_planning.py
├── src/tefteri/
│   ├── domain/
│   │   ├── enums.py                  # GoalState, UpdateSource, ValueSource, PlanChangeKind, LinkEndReason
│   │   ├── key_results.py            # NEW pure rules: progress, is_met, is_overdue, current value, value on or before, validation, flags
│   │   └── annual_plan.py            # NEW pure rules: year state (past, current, future), limit of three, seeding, deadline shift
│   ├── security/tokens.py            # NEW new_push_token, digest (shared with auth if it fits)
│   ├── db/models/
│   │   ├── goal.py                   # CHANGED columns
│   │   ├── key_result.py             # NEW KeyResult, KeyResultValue, KeyResultTheme, PlanChange
│   │   └── push_token.py             # NEW ValuePushToken
│   ├── services/
│   │   ├── annual_plan.py            # NEW AnnualPlanService: plan read, goals, bulk create, retire, restore, undo, seeding, history, themes
│   │   ├── key_results.py            # NEW KeyResultService: create, edit, retire, restore, links, values, value on a date, flags
│   │   ├── value_push.py             # NEW PushTokenService: issue, revoke, authenticate, push
│   │   ├── goals.py                  # CHANGED (trimmed)
│   │   └── reviews.py                # CHANGED (retired goals)
│   ├── api/routers/
│   │   ├── annual.py                 # NEW /annual/... for the signed-in user
│   │   ├── push.py                   # NEW inbound push (push token, not a session)
│   │   ├── planning.py               # CHANGED
│   │   └── tasks.py                  # CHANGED goal check
│   └── main.py                       # CHANGED wiring
└── tests/
    ├── unit/test_key_results.py, test_annual_plan_rules.py, test_goals.py
    ├── integration/test_annual_plan.py, test_key_results.py, test_key_result_links.py,
    │   test_key_result_flags.py, test_annual_seed.py, test_plan_history_undo.py,
    │   test_value_series.py, test_value_push.py, test_legacy_goals.py, test_annual_past_year.py,
    │   test_planning.py, test_reviews.py, test_review_performance.py, test_isolation.py
    ├── e2e/test_annual_api.py, test_postgres_app.py
    └── migrations/test_migrations.py

frontend/
├── lib/
│   ├── core/periods.dart             # MOVED from features/goals
│   ├── core/planning_api.dart, planning_models.dart   # CHANGED
│   ├── app.dart, core/shell.dart, core/shortcuts/keymap.dart   # CHANGED
│   └── features/
│       ├── annual/
│       │   ├── annual_screen.dart, goal_card.dart, key_result_tile.dart, key_result_form.dart
│       │   ├── value_dialog.dart, theme_picker.dart, create_theme_dialog.dart, flag_chip.dart
│       │   ├── retire_dialog.dart, seed_panel.dart, plan_history_view.dart, legacy_goals_view.dart
│       │   ├── push_token_dialog.dart, annual_term_hint.dart
│       │   └── annual_api.dart, annual_models.dart, annual_controller.dart
│       ├── period/period_page.dart   # MOVED from features/goals
│       ├── week/, month/, year/      # CHANGED
│       └── goals/                    # DELETED
└── test/features/annual/, test/screenshots/annual_screens_test.dart, test/support/fake_api.dart

docs/
├── user/annual-planning.md, user/planning-checklists.md
├── developer/annual-planning.md
├── images/annual-*.png
└── openapi.json

scripts/seed_demo.py                  # NEW seed for the walkthrough, run by `just backend::seed-demo`
```

**Structure Decision**: Follow the existing layers and the Flutter feature-folder pattern. The pure rules sit in `domain` so features 007 and 008 can reuse them without the database. The value-on-a-date answer (FR-034) is a service method, `KeyResultService.value_on`, that feature 007 calls in process. This feature does not push or pull towards other features.

## Requirement coverage

| Requirements | Milestone | Main files |
|---|---|---|
| FR-001 to FR-009, FR-018 | M1, M2, M3 | `domain/key_results.py`, `db/models/key_result.py`, `services/key_results.py`, `services/annual_plan.py` |
| FR-010 | M4 | `services/value_push.py`, `api/routers/push.py`, [contracts/api.md](contracts/api.md) |
| FR-011 to FR-014 | M3 | `services/key_results.py`, `domain/key_results.py` |
| FR-015 | M3 | `services/annual_plan.py` (calls feature 003) |
| FR-016, FR-017 | M4 | `domain/annual_plan.py`, `services/annual_plan.py` |
| FR-019 to FR-021, FR-032 | M3 | `services/annual_plan.py` (history, undo, effect preview) |
| FR-022 to FR-027 | M2, M4, M5, M7 | migration, `api/routers/planning.py`, frontend removal tasks |
| FR-028, FR-029 | M3, M5 | no write in 003 code, `user_id` on every row |
| FR-030, FR-034 | M3, M4 | `GET /annual/{year}`, `KeyResultService.value_on` |
| FR-031, FR-035 | M6, M8 | docs, `annual_term_hint.dart` |
| FR-033 | M3 | `domain/annual_plan.py` year state, guard in services |

## Delivery order (milestones)

1. **M1 Domain**: enums, pure rules for key results, flags, the limit, year state and seeding, with unit tests. Done when the unit tests pass and `tach check` passes.
2. **M2 Data and migration**: models, `0020_annual_planning`, the data migration of existing goals, migration tests on SQLite and Postgres. Done when the counts before and after match.
3. **M3 Services**: goals, key results, links, flags, create theme, retire, restore, undo, history, past-year guard. Done when the integration tests pass.
4. **M4 Seeding, values, push, legacy**: seed from year N, value series and value on a date, push token and push, legacy removal in the backend and the task goal check. Done when the integration tests pass and the old tests are updated.
5. **M5 API**: routers, schemas, OpenAPI snapshot, e2e tests, the changed old backend tests. Done when `just backend::test`, `just backend::e2e`, `just backend::test-postgres` pass.
6. **M6 Client annual plan**: the annual screen, key result editor, picker, flags, values, seed panel, history, token dialog, hints. Done when the widget tests and `flutter analyze` pass.
7. **M7 Client goals leave the flow**: remove month and week goals, move shared files, update old widget tests, legacy history view, task goal picker. Done when `just frontend::test` passes and no screen offers a month or week goal.
8. **M8 Docs and proof**: user and developer docs, screenshots, browser walkthrough on a live Vikunja, usability fixes, converge. Done when `just lint`, `just docs::check`, all tests and the walkthrough are clean.

## Complexity Tracking

No violations. Three choices add structure, and each one is the simpler option compared with the alternative (R-02, R-03, R-05): a derived current value instead of a stored one, a slot column instead of a lock, one history table instead of one table per entity.
