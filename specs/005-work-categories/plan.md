# Implementation Plan: Work Categories and Statistics

**Branch**: `005-work-categories` (developed on the session branch) | **Date**: 2026-11-11 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/005-work-categories/spec.md`

## Summary

Put every completed task into one of three work categories (goal-aligned, maintenance, off-plan) or into the hidden count of ignored projects, once, when Tefteri first sees the task as completed, and never recompute it. A pure rule in the domain layer decides from the label the project had on the completion day (feature 003 history), the labels of its ancestors (decision 10: work inside a routine project is maintenance) and the weekly commitment of the completion week (feature 004). The result goes into a new table `task_categories` that the sync never overwrites. A statistics service builds every count from these stored rows: a day is a grouped query, a week and a month are sums of days, a year is the sum of its months, so the views always agree. Lists load in pages with a keyset cursor, so the old limit of 200 tasks done outside the plan is gone. Two new routes serve the week, the month and the year (`GET /statistics`, `GET /statistics/tasks`). The cadence and burndown arithmetic moves from Dart to the server. The Flutter client gets one visual language (a style that does not rely on colour), a proportion bar, counts that open a drill-down list, a quiet hidden line, last-sync text and empty states with inline actions. Feature 007 reads the daily counts through `StatisticsService.daily_counts`.

## Technical Context

**Language/Version**: Python 3.13 (backend), Dart 3.13 / Flutter 3.47 (client)

**Primary Dependencies**: FastAPI, SQLAlchemy 2 async, Alembic (existing); flutter_riverpod, go_router, dio (existing). No new dependency.

**Storage**: SQLite or PostgreSQL through Alembic. New migration `0021_work_categories` (revision `0021`, down revision `0020`) adds the table `task_categories` ([data-model.md](data-model.md)). The migration copies no data (research R-15).

**Testing**: pytest (unit, integration with in-memory fakes, e2e over the ASGI client, performance, migrations incl. Postgres, live task app, smoke test of the real server over HTTP), `flutter test` widget tests with `fake_api.dart`, screenshot tests, a browser walkthrough with Playwright (Chromium).

**Target Platform**: Linux server in a container; Flutter web, Linux and Android clients.

**Project Type**: Web service plus Flutter client (existing layout).

**Performance Goals**: A week of 1,000 completed tasks returns its counts and the first page of 50 tasks in under 2 s (SC-003). A year of 20,000 completed tasks returns its counts and bar in under 3 s. The recorder classifies 20,000 tasks in batches of 500 without one query per task.

**Constraints**: No category is ever recomputed after it is stored. No time is recorded, shown or estimated (FR-014). No Vikunja name in the core layers (constitution IV, `tach`). No write to the task app. Theme tokens only in the UI. Docs in ASD-STE100. Percentages are never stored. A deleted or orphaned project or a moved task never breaks a screen.

**Scale/Scope**: One user has up to tens of thousands of completed tasks. 1 migration, 1 table, 2 domain modules, 3 services (1 seam), 1 new router, 2 routes, 1 route field removed, about 12 new widgets, 2 new doc pages and 4 changed.

## Constitution Check

| Principle | Status | How |
|---|---|---|
| I. Python backend, Flutter frontend | Pass | Same stack. |
| II. Justfile is the single interface | Pass | Every command in the quickstart and in `tasks.md` is a `just` recipe (`just backend::test`, `just backend::e2e`, `just backend::test-postgres`, `just backend::openapi`, `just backend::live-vikunja`, `just frontend::test`, `just frontend::analyze`, `just docs::screenshots`, `just docs::check`, `just lint`). The walkthrough uses `just serve`. The smoke test is part of `just backend::live-vikunja`. No new inline CI logic. |
| III. Devbox | Pass | No new tool. The session sources `/root/tefteri-env.sh` only because devbox is not available there. |
| IV. Pluggable backends | Pass | No new port operation. The new modules `domain/work_categories.py` and `domain/week_progress.py` import no database, adapter or task app name. `services/*` depend on `domain` and `db`; `api` on `services`; `tach check` stays green. The link to a task in the task app is built by `api/task_links.py`, moved unchanged from the weekly router. `grep -ri vikunja backend/src/tefteri --include=*.py -l` still lists only `adapters/vikunja`, `config`, the registry and that one URL helper. |
| V. Documented, tested, CI-verified | Pass | Tests first in every phase of [tasks.md](tasks.md). Migration test with old rows, OpenAPI snapshot, docstrings on every new public module, class and function, widget docs. A smoke test of the real server over HTTP (research R-17). |
| VI. Two-audience docs, STE, screenshots | Pass | User guide `docs/user/work-categories.md` and developer guide `docs/developer/work-categories.md`, plus changes to the weekly and planning guides. Prose in ASD-STE100, checked by Vale in `just lint`. Screenshots from `just docs::screenshots` with fake data and alt text. |
| VII. Due date is canonical | Pass | This feature reads completion times only and writes no planning date. |
| UI rules of `AGENTS.md` | Pass | Colors, fonts, spacing and radii from `context.tefteri`, `Space` and `Corner`. `EmptyState` and `Loading` for empty and loading states. No `Color(0x...)`, no `Colors.*`, no font names in `lib/features`. `frontend/test/theme/design_rules_test.dart` enforces it. Screenshots are looked at in light and dark, at phone and desktop width, and in greyscale (tasks T074, T077 and T078). |
| Constitution: "never track time" (FR-014) | Pass | No field, column, route or widget holds a duration. A test scans the OpenAPI schemas and the model for time words (task T046). |

Re-check after design: Pass. One note: the design adds a seam `CommitmentProvider` (research R-05). It is the smallest way to prove FR-026 and to read feature 004 without a hard import of its models in the recorder. No complexity violation.

## Project Structure

### Documentation (this feature)

```text
specs/005-work-categories/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/api.md
├── checklists/requirements.md
└── tasks.md          # created by speckit-tasks
```

### Source Code (repository root): every file this feature touches

```text
backend/
├── migrations/versions/0021_work_categories.py          # NEW: 1 table, 3 indexes, no data
├── src/tefteri/
│   ├── domain/
│   │   ├── enums.py                  # WorkCategory, CategoryReason
│   │   ├── work_categories.py        # NEW pure rules: categorize, label_on, percentages,
│   │   │                             #   CategoryCounts, LabelEntry, ProjectContext, Decision
│   │   └── week_progress.py          # NEW port of week_progress.dart (cadence, burndown)
│   ├── db/models/
│   │   ├── task_category.py          # NEW TaskCategory
│   │   └── __init__.py               # export it
│   ├── services/
│   │   ├── commitments.py            # NEW CommitmentProvider seam + WeeklyCommitments (reads 004)
│   │   ├── category_recorder.py      # NEW first-seen recorder: batches, label history, ancestors
│   │   ├── statistics.py             # NEW StatisticsService: daily_counts, counts, summary,
│   │   │                             #   task pages, week progress, last sync, empty reason
│   │   ├── sync.py                   # snapshot of open tasks before the upserts, call the recorder
│   │   ├── tasks.py                  # complete() calls the recorder after the task app confirmed
│   │   └── weekly.py                 # REMOVE ExtraDone, MAX_EXTRA_DONE, done_outside_plan
│   ├── api/
│   │   ├── task_links.py             # NEW task_base_url moved from routers/weekly.py
│   │   └── routers/
│   │       ├── statistics.py         # NEW GET /statistics, GET /statistics/tasks
│   │       └── weekly.py             # REMOVE ExtraDoneOut and done_outside_plan, use task_links
│   └── main.py                       # wire CommitmentProvider, recorder, statistics, router
└── tests/
    ├── unit/test_work_categories.py, test_week_progress.py, test_statistics_schema.py   # NEW
    ├── integration/
    │   ├── test_work_categories_recording.py, test_work_categories_stability.py,
    │   │   test_work_categories_unusual.py, test_statistics_periods.py,
    │   │   test_statistics_tasks_paging.py, test_statistics_week_progress.py,
    │   │   test_statistics_performance.py              # NEW
    │   ├── test_weekly.py                               # changed (table below)
    │   ├── test_orphans.py                              # extended: statistics with an orphan
    │   ├── test_isolation.py                            # extended: statistics are private
    │   ├── test_tasks.py                                # extended: complete() records
    │   └── test_connections_sync.py                     # extended: sync records, backfill
    ├── e2e/test_statistics_api.py                       # NEW
    ├── migrations/test_migrations.py                    # 0021 with old rows
    ├── unit/test_openapi_snapshot.py                    # snapshot via docs/openapi.json
    └── live/test_vikunja_live.py, test_statistics_live.py   # live loop and the HTTP smoke test

frontend/
├── lib/features/statistics/                  # NEW feature folder
│   ├── statistics_models.dart                # CategoryCounts, PartCounts, StatisticsSummary,
│   │                                         #   WeekProgressData, StatisticsTask, TaskPage
│   ├── statistics_api.dart                   # summary(period, day), tasks(...) + provider
│   ├── statistics_providers.dart             # summary family, paged list controller
│   ├── category_style.dart                   # the one mapping: icon, fill, outline, hatch, label
│   ├── proportion_bar.dart                   # bar with minimum segment width and semantics
│   ├── category_counts_row.dart              # three tappable counts with percentages
│   ├── categories_card.dart                  # counts, bar, hidden line, sync line, empty state
│   ├── category_task_list.dart               # paged list grouped by project, "unsorted" note
│   ├── completed_by_category.dart            # week list: three groups with their counts
│   └── drilldown_screen.dart                 # route /statistics, tasks behind one count
├── lib/features/weekly/
│   ├── week_progress.dart                    # keeps the data class and fromJson, drops the math
│   ├── week_progress_card.dart               # server numbers, category counts per day, no extra list
│   └── weekly_models.dart                    # REMOVE ExtraDoneTask and doneOutsidePlan
├── lib/features/week/week_screen.dart        # categories card, completed list, helper line
├── lib/features/month/month_screen.dart      # categories card above the existing page
├── lib/features/year/year_screen.dart        # categories card above the existing page
├── lib/features/projects/term_hint.dart      # terms: goal-aligned, maintenance, off-plan, unsorted, hidden
├── lib/app.dart                              # route /statistics for the drill-down
└── test/
    ├── features/statistics/                  # NEW widget tests (one file per widget)
    ├── features/weekly/week_progress_test.dart, weekly_fake.dart        # changed
    ├── features/week/week_screen_test.dart                              # changed
    ├── features/month/month_screen_test.dart, year/year_screen_test.dart  # changed
    ├── screenshots/planning_test.dart, statistics_test.dart             # changed, new
    ├── support/fake_api.dart                 # routes for the statistics
    ├── app_routes_test.dart                  # the new route
    └── theme/design_rules_test.dart          # must pass

docs/
├── user/work-categories.md                   # NEW, with screenshots and alt text
├── user/weekly-planning.md                   # section "Tasks done outside the plan" rewritten
├── user/planning-goals.md                    # Month and Year views: counts and bar
├── user/organizing-projects.md               # one line: labels decide categories
├── user/troubleshooting.md                   # numbers drop after a delete, hidden line, unsorted
├── user/index.md, developer/index.md         # toctree entries
├── developer/work-categories.md              # NEW: table, rules, recorder, hooks, snapshots (007)
├── developer/weekly-planning.md              # the hand-over section is closed
├── developer/sync.md                         # the recorder step after the task sync
├── developer/testing.md                      # new test files and the smoke test
├── developer/design.md                       # the category style
├── images/categories-*.png, planning-*.png   # new and regenerated
└── openapi.json                              # regenerated
```

**Structure Decision**: Follow the existing layers and the Flutter feature-folder pattern. The rules sit in `domain/work_categories.py` so they are unit tested without a database and reused by features 007 and 008. The recorder and the statistics service are separate files because they have different jobs: one writes once, the other only reads. The weekly service loses code and gains none.

## Migration `0021_work_categories`

- Revision `0021`, down revision `0020`. File `backend/migrations/versions/0021_work_categories.py`. The file of `0020` exists when this is written (feature 006 comes first in the delivery order). The single-head test catches a fork.
- Creates `task_categories` with the unique constraint on `task_id`, the check on `category` and the three indexes. No backfill and no `UPDATE` (research R-15).
- Downgrade drops the table.
- Numbers 0022 and 0023 stay free for features 007 and 008.

## Existing tests that must change

| Test | File | Why | Change |
|---|---|---|---|
| `test_tasks_done_outside_the_plan_are_listed_with_their_day` | `backend/tests/integration/test_weekly.py` | `done_outside_plan` is removed (R-14). | Move the scenario to `test_statistics_periods.py`: a task of another project is off-plan with its day, a task of a committed project is goal-aligned, no completion time is not counted. Delete the old test. |
| `test_the_week_follows_the_time_zone_of_the_user` | same | Same field. | Same scenario against `GET /statistics?period=week`; add the Monday 00:30 edge in both directions. |
| `test_nothing_is_listed_before_the_plan_is_committed` | same | Old rule: no plan, no list. New rule: the list does not depend on a plan; a week without a committed plan has no goal-aligned task. | Rewrite: with a draft plan a task in a milestone is off-plan, in a routine project maintenance. |
| `test_an_extra_task_has_its_project_color_and_link` | same | Field removed. | Move to the task list route: colour, link and stored project name. |
| the helper `_extra` and the `done_outside_plan` assertions | same | Field removed. | Remove the helper; use `GET /statistics/tasks`. |
| the OpenAPI snapshot | `backend/tests/unit/test_openapi_snapshot.py` with `docs/openapi.json` | New routes, removed field. | Regenerate with `just backend::openapi`. |
| migration tests | `backend/tests/migrations/test_migrations.py` | New head `0021`. | Add 0021 tests; `test_single_head_revision` and `test_up_down_consistency` must pass. |
| sync tests that call `_sync_tasks` or count queries | `backend/tests/unit/test_sync_service.py`, `backend/tests/integration/test_sync_performance.py` | The sync now calls the recorder and takes a snapshot. | Keep the assertions; add the recorder to the fake wiring; the query budget of the performance test gets the recorder's batched queries. |
| complete-task tests | `backend/tests/integration/test_tasks.py` | `complete()` records the category. | Extend, do not weaken. |
| `frontend/test/features/weekly/week_progress_test.dart` | | The `extra` argument, `extraByDay`, `extraDone` and the `done_outside_plan` JSON are gone; the math is on the server. | The math cases become `test_week_progress.py`. Keep the card widget tests: feed them the server `progress` block and the category counts. |
| `frontend/test/features/weekly/weekly_fake.dart` | | `done_outside_plan` is gone. | Remove it from the JSON. |
| `frontend/test/features/week/week_screen_test.dart` | | The week screen gains the categories card and the list. | Add the statistics routes to the fake; assert the helper line. |
| `frontend/test/features/month/month_screen_test.dart`, `year/year_screen_test.dart` | | The screens gain a card. | Add the fake routes; keep the existing assertions. |
| `frontend/test/screenshots/planning_test.dart` | | The fixture has `done_outside_plan` (line 53). | Replace it with the statistics fixture; regenerate `planning-week.png`, `planning-month.png`, `planning-year.png`. |
| `frontend/test/support/fake_api.dart` | | New routes. | Add `GET /statistics` and `GET /statistics/tasks` with paging. |
| `scripts/check_docs.sh` image check | | New images need alt text. | No code change; the check must pass. |

Tests that must **not** change: the burndown drawing and cadence text tests that only read numbers (they keep their expected values, because the server returns the same arithmetic), every 003 classification test, every 004 test not listed above, and the spread, park and archive tests of the weekly page.

## Delivery order (milestones)

1. **M1 Domain and data**: enums, pure rules, week progress port, model, migration `0021`, tests. Done when unit and migration tests pass on SQLite and Postgres and `tach check` passes.
2. **M2 Recording**: commitment seam, recorder, hooks in sync and in `complete()`. Done when the integration tests for recording, stability and unusual projects pass and the changed sync and task tests pass.
3. **M3 Statistics service**: daily counts, sums, task pages, week progress, removal of `done_outside_plan` from the weekly service. Done when the period, paging, progress and performance tests pass.
4. **M4 API**: router, schemas, moved URL helper, weekly router change, OpenAPI snapshot. Done when the e2e tests, the schema test and the snapshot test pass.
5. **M5 Client**: models, API, style, bar, card, lists, drill-down, week, month and year screens, hints, empty states. Done when widget tests, `flutter analyze` and the design rules test pass.
6. **M6 Docs and proof**: user and developer docs, screenshots, the smoke test of the real server, the browser walkthrough against a seeded live task app, usability fixes, converge and analyze. Done when `just lint`, `just docs::check`, all tests and the walkthrough are clean.

## Hand-over from feature 004 and to feature 007

- From 004: `done_outside_plan` was left unchanged for this feature. M3 and M4 remove it. 004's `docs/developer/weekly-planning.md` has the section "Hand-over to feature 005"; task T073 closes it.
- To 007: `StatisticsService.daily_counts(db, user_id, start, end)` and `counts(...)` return `CategoryCounts` with the hidden count. 007 stores them in its snapshot and reads no percentages. `docs/developer/work-categories.md` states this contract.

## Complexity Tracking

No violations. The separate table `task_categories` and the seam `CommitmentProvider` are the simpler choices compared with columns on `tasks` and a hard dependency on the weekly models (research R-01, R-05).

## Open points for the project owner (beyond the spec)

1. **No daily count table.** FR-025 says the system keeps the count per category per day. The plan derives it by a grouped query over the stored per-task rows (R-07). A table of daily counts can be added later if the owner wants one.
2. **Ignored beats routine.** A project labelled ignored, or inside an ignored project, is hidden even when it also sits inside a maintenance project (R-06). FR-029 says "whatever the label of its own project is" and can be read the other way.
3. **Project when a task was moved and completed between two syncs.** The last project seen with the task open decides (R-03).
4. **Cadence and burndown arithmetic moves to the server** (R-12), because the assumptions say so, although FR-011 names categories only.
5. **The completion day is frozen** in the time zone of the user at the first sight (R-09). A later change of time zone does not move a task.
6. **A done task with no completion time is counted nowhere**, as in the list today.
7. **First sync after the upgrade classifies the whole history** with the labels and commitments that exist then (R-15). Commitments edited before the upgrade are not replayed.
8. **Only the exact project is tested against the commitment.** A task in a sub-project of a committed milestone is off-plan unless that sub-project is committed itself. Ancestor labels use the last known parent links, because 003 keeps no history of moves (R-04).
9. **Month and year screens keep their goal and due-task sections.** The new card is added above them; feature 006 removes the goals. `done_outside_plan` leaves the weekly API without a deprecation period, because only the Tefteri client reads it (R-14).
10. **Names in the UI.** The category is called "Maintenance" in the statistics and "Routine (maintenance)" in the first-use hint of the Projects screen. The hidden line is also a drill-down (R-16).
