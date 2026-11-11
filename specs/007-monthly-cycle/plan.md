# Implementation Plan: Monthly Planning and Review

**Branch**: `007-monthly-cycle` (developed on the session branch) | **Date**: 2026-11-11 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/007-monthly-cycle/spec.md`, the decisions in `specs/planning-cycles/decisions.md`, and the design of features 003, 004 and 006 (`specs/003-project-classification/`, `specs/004-weekly-milestones/`, `specs/006-annual-planning/`). Feature 005 has a spec only, so its numbers are read through a small reader (research R-08).

## Summary

Add the monthly cycle on top of the milestones of 004 and the key results of 006. The user picks three to five theme projects for a month and gives each an optional milestone-count target (none and 0 are different values). The picks are stored as a monthly focus with a log of mid-month swaps, adds, removes and target changes that can be undone. The focus gets its real reader: `MonthlyFocusService` implements the `FocusProvider` seam that feature 004 defined (default `NoFocus`), so the weekly picker shows the focus themes first and weekly planning can mark "outside focus". At month end the review counts done milestones by the done date and the theme at done that 004 stores, shows each key result with its latest value and time stamp from the 006 series (it never pulls), writes manual values typed in the review into that series, shows milestones shipped beside key result movement, shows the counts per work category and the hidden count from 005 with the off-plan trend, and lets the user decide per theme: carry forward, drop, replace or decide later. Finishing stores an immutable, versioned review snapshot (`monthly_review_snapshots`, JSON payload) that 008 reads. The goal-based Month view is replaced by the theme-based monthly screens. Old month goal rows and the old stored period review stay untouched. The monthly checklist stays. No task, project or label is written to the task manager.

## Technical Context

**Language/Version**: Python 3.13 (backend), Dart 3.13 / Flutter 3.47 (client)

**Primary Dependencies**: FastAPI, SQLAlchemy 2 async, Alembic, httpx (existing); flutter_riverpod, go_router, dio (existing). No new dependency.

**Storage**: SQLite or PostgreSQL through Alembic. New migration `0022_monthly_cycle` (down revision `0021`) adds `monthly_focuses`, `monthly_focus_entries`, `focus_changes`, `monthly_reviews` and `monthly_review_snapshots` ([data-model.md](data-model.md)). No existing table changes.

**Testing**: pytest (unit, integration with in-memory fakes, e2e, migrations incl. Postgres, OpenAPI snapshot, schema coverage test, live Vikunja and a smoke test of the real server over HTTP), `flutter test` widget tests with `fake_api.dart`, screenshot tests, a Playwright (Chromium) browser walkthrough against a seeded live Vikunja.

**Target Platform**: Linux server in a container; Flutter web, Linux and Android clients.

**Project Type**: Web service plus Flutter client (existing layout).

**Performance Goals**: The review of a month with 500 completed tasks opens in under 3 s on SQLite and makes no call to a key result source (SC-010). The planning screen with 300 themes in the picker loads in under 1 s and the picker filters as the user types. A plan save of five themes takes under 200 ms. The weekly focus read (`themes_for_month`) is one query.

**Constraints**: No label, field, project or task is written to the task app (SC-008). The only write outside this feature's own tables is one `key_result_values` row per manual value typed in a review, through the 006 service. The core layers never name Vikunja (constitution IV, `tach`). Theme tokens only in the UI. Docs in ASD-STE100. No hours, duration or effort anywhere (FR-040). A stored snapshot is never updated or deleted by code. No step of planning or review blocks the user (FR-044).

**Scale/Scope**: One user has tens to a few hundred themes, plans three to five a month, and has up to nine key results in play. 1 migration, 5 tables, 1 pure domain module, 2 services (plus a small reader interface), 1 router with 12 routes, 1 rewritten screen with about 14 widgets, 2 new doc pages, 5 doc pages changed.

## Constitution Check

| Principle | Status | How |
|---|---|---|
| I. Python backend, Flutter frontend | Pass | Same stack. |
| II. Justfile is the single interface | Pass | Every command in the quickstart and in [tasks.md](tasks.md) is a `just` recipe: `just backend::test`, `just backend::e2e`, `just backend::test-postgres`, `just backend::openapi`, `just backend::live-vikunja`, `just backend::vikunja-up`, `just backend::seed-demo` (added by feature 006), `just frontend::test`, `just frontend::analyze`, `just frontend::format-check`, `just docs::screenshots`, `just docs::check`, `just docs::build`, `just lint`, `just serve`. The smoke test of the real server runs inside `just backend::live-vikunja`. No inline CI logic. |
| III. Devbox | Pass | No new tool. The session sources `/root/tefteri-env.sh` only because devbox is not available there. |
| IV. Pluggable backends | Pass | No port operation and no adapter change. `domain/monthly.py` and the services never name a task app. Themes and milestones are read from `project_labels` and `milestones`. `grep -ri vikunja backend/src/tefteri --include=*.py -l` lists only `adapters/vikunja`, `config`, the registry and the existing weekly router URL helper. `tach check` stays green: `domain` has no dependency, `db` depends on `domain` and `security`, `services` on `domain` and `db`, `api` on `services`. |
| V. Documented, tested, CI-verified | Pass | All behaviour has a test, written first, listed per phase in [tasks.md](tasks.md). Migration test with old rows, OpenAPI snapshot, a schema coverage test (every enum and `Literal` value of a response model is built and serialized), a smoke test of the real server over HTTP, docstrings on all new public modules, classes and functions. |
| VI. Two-audience docs, STE, screenshots | Pass | User guide `docs/user/monthly-planning.md` and developer guide `docs/developer/monthly-cycle.md`, in ASD-STE100, checked by Vale in `just lint`. Screenshots from `just docs::screenshots` with fake data and alt text. The glossary words are used as written. |
| VII. Due date is canonical | Pass | The feature writes no planning date and no due date. Targets and months are Tefteri values. |
| UI rules of `AGENTS.md` | Pass | Colors, fonts, spacing and radii come from `context.tefteri`, `Space` and `Corner`. `EmptyState` and `Loading` for empty and loading states. No `Color(0x...)`, no `Colors.*` and no font name in `lib/features`. No stock app bar, no elevated card or bare list tile as the main structure. `frontend/test/theme/design_rules_test.dart` enforces it. Screenshots are looked at in light and dark and at phone and desktop widths (tasks T090 and T094). |

Re-check after design: Pass. One note: the review needs three reads from other features (done milestones of 004, series of 006, category counts of 005). They are read through existing services and, for 005, one small reader interface, so nothing is calculated twice (research R-08). No complexity violation.

## Design decisions in short

The reasons and rejected options are in [research.md](research.md).

- **Own tables, no change to others** (R-01): the focus and the review are new tables. Weekly and annual tables stay as they are.
- **Entries edited, changes logged** (R-02): the log is append only and undo adds rows.
- **None is not zero** (R-03): nullable integer, one parse rule, one error code.
- **The real `FocusProvider`** (R-04): `None` without a saved focus, a set (maybe empty) with one. Only `main.py` changes in the weekly code.
- **One counting rule** (R-05): done date and theme at done from 004, a window per entry, outside focus and "no theme" listed apart.
- **Snapshot** (R-06): JSON payload in an immutable row, versions, a pointer on the header.
- **Key results** (R-07): read the 006 series, never pull, write only typed manual values in the finish step.
- **Categories** (R-08) and **trend** (R-09): counts from 005 through a reader, shares computed on display.
- **Decisions** (R-10): part of the snapshot, suggestions computed on read.
- **Draft on the device** (R-11), **Month view replaced** (R-12), **month and time zone** (R-13).

## Changes to existing behaviour

The spec marks FR-033 as a change of existing behaviour. This is the full list of what changes.

### Existing code that changes

| File | Change |
|---|---|
| `backend/src/tefteri/main.py` | Create `MonthlyFocusService` and `MonthlyReviewService`; pass the focus service to `WeeklyService` in place of `NoFocus`; wire the category reader of 005; include the monthly router. |
| `backend/src/tefteri/api/errors_map.py` | Map the new service errors (`InvalidTarget`, `NotAFocusTheme`, `LeftThisMonth`, `UseChanges`, `PastMonth`, `NotCurrentMonth`, `FutureMonth`, `ConfirmRequired`, `NoSuchVersion`, `NotUndoable`) to the codes of contracts/api.md. |
| `backend/src/tefteri/domain/enums.py` | Add `FocusEntryStatus`, `FocusChangeKind`, `ThemeDecision`, `TargetMarker`, `KeyResultUpdate`, `TrendState`, `CountNote`, `MonthState`. |
| `backend/src/tefteri/db/models/__init__.py` | Export the new models. |
| `backend/src/tefteri/api/schemas.py` | No change expected. The schemas of the new router are in the router file, as in the existing routers. |
| `docs/openapi.json` | Regenerate. |
| `frontend/lib/features/month/month_screen.dart` | Rewritten: the theme-based Month screen. It drops `monthViewProvider` and `PeriodPage`. It keeps the keys `period-label`, `today-button`, `prev-period`, `next-period` and the `PlanningChecklist` banner. |
| `frontend/lib/core/planning_api.dart` | Remove `monthView` (no caller is left). |
| `frontend/lib/features/projects/term_hint.dart` | New terms: monthly focus, key result, work categories, outside focus, review snapshot. |
| `frontend/lib/features/settings/checklists_screen.dart` | No change expected. A test proves that the monthly checklist example still shows. |
| `docs/user/planning-checklists.md` (006 splits it from `planning-goals.md`) | The monthly checklist is now on the new Month screen: change the sentence and the link. |
| `docs/user/annual-planning.md`, `docs/user/weekly-planning.md`, `docs/user/reviews-and-retrospectives.md`, `docs/user/index.md`, `docs/user/getting-started.md`, `docs/user/planner.md`, `docs/user/android-widget.md`, `docs/user/shortcuts.md` | Add links to the monthly guide; change every sentence that says the Month view shows goals. |
| `docs/developer/index.md`, `architecture.md`, `weekly-planning.md` (focus seam section), `testing.md`, `android-widget.md` | Add the new guide, the tables and tests; the focus seam now has a real provider. |
| `scripts/check_docs.sh` | Add `user/monthly-planning.md` and `developer/monthly-cycle.md` to the required list. |
| `scripts/seed_demo.py` | Add the monthly demo data (themes, done milestones in three months, key results with series, category tasks). |
| `docs/images/` | Regenerate `planning-month.png` (now the new screen, from `monthly_test.dart`). Add `monthly-*.png`. |

### Existing tests that must change

| Test | File | Why | Change |
|---|---|---|---|
| `shows month goals and progress, but no single tasks` | `frontend/test/features/month/month_screen_test.dart` | The Month screen shows themes, not goals (FR-033). | Rewrite: shows the focus, targets, progress and key results; no goal list; no single tasks. |
| `does not list the events of the month` | same | The new screen has no event list and no `PeriodView`. | Keep the intent (no events, no task list); use the monthly fake. |
| the next-month test (`GET /views/month/2026-12-01`) | same | The screen loads `GET /monthly/2026-12`. | Update routes and finders. |
| `the month page shows the monthly checklist` | `frontend/test/features/checklists/period_checklists_test.dart` | Fixtures use `GET /views/month/...`. | Add `GET /monthly/2026-11` fixtures; assertions on the checklist stay the same (FR-034). |
| `moving to the next month loads that month's clean list` | same | Same. | Same; the checklist call per month stays. |
| `Month: Today returns to the current month` | `frontend/test/today_button_test.dart` | `FakeApi({})` has no monthly route. | Use the monthly empty fixture; the keys `period-label` and `today-button` stay. |
| the month screenshot (`planning-month`) | `frontend/test/screenshots/planning_test.dart` | The old screen is gone. | Remove it there; the new one is in `monthly_test.dart`. |
| the route-to-screen map | `frontend/test/core/home_screen_widget_test.dart` | `'/month': MonthScreen`. | No change expected; run it. The type name stays. |
| shell and shortcut tests | `frontend/test/shell_test.dart`, `frontend/test/core/shortcuts_test.dart` | Route `/month` stays. | No change expected; run them. |
| the fake API | `frontend/test/support/fake_api.dart` | New routes. | Add `monthlyJson` helpers and the `/monthly/...` routes. |
| the term hint tests | `frontend/test/features/projects/projects_screen_test.dart` (term hints) | New terms. | Add the five terms. |
| `test_single_head_revision`, `test_up_down_consistency` | `backend/tests/migrations/test_migrations.py` | New head `0022`. | Must pass. Add the 0022 tests. |
| the OpenAPI snapshot | `backend/tests/unit/test_openapi_snapshot.py` with `docs/openapi.json` | New routes. | Regenerate with `just backend::openapi`. |
| the isolation test | `backend/tests/integration/test_isolation.py` | New private data. | Extend with the monthly routes: user B gets 404 for the focus, the changes and the snapshots of user A. |
| the orphan test | `backend/tests/integration/test_orphans.py` | Orphaned theme and milestone in the monthly screens (SC-007). | Extend, do not weaken. |
| the Postgres app test | `backend/tests/e2e/test_postgres_app.py` | Monthly flow on Postgres. | Add a short monthly flow. |
| the weekly focus tests | `backend/tests/integration/test_weekly_focus.py` (004) | They use a fake provider. | No change. A new test uses the real provider. |
| docs check | `scripts/check_docs.sh` | New required guides. | Add them to the list. |

Tests that must **not** change (they guard behaviour that stays): the checklist tests of `frontend/test/features/checklists/` apart from the fixtures above, `backend/tests/integration/test_checklists.py`, `backend/tests/integration/test_planning.py` (the view route `/views/month/{day}` stays), every 003, 004, 005 and 006 test, and `frontend/test/features/review/review_screens_test.dart` (the old stored period reviews still load, FR-028).

## Project Structure

### Documentation (this feature)

```text
specs/007-monthly-cycle/
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
├── migrations/versions/0022_monthly_cycle.py            # NEW: 5 tables, no UPDATE of old rows
├── src/tefteri/
│   ├── domain/
│   │   ├── enums.py                  # FocusEntryStatus, FocusChangeKind, ThemeDecision, TargetMarker,
│   │   │                             #   KeyResultUpdate, TrendState, CountNote, MonthState
│   │   └── monthly.py                # NEW pure rules: parse_target, count_note, result_marker, month_state,
│   │                                 #   classify_done, key_result_flags, key_result_status, off_plan_share,
│   │                                 #   trend, decision_effect, build_suggestions, build_payload, CategoryCounts
│   ├── db/models/
│   │   ├── monthly.py                # NEW MonthlyFocus, MonthlyFocusEntry, FocusChange,
│   │   │                             #   MonthlyReview, MonthlyReviewSnapshot
│   │   └── __init__.py               # export the new models
│   ├── services/
│   │   ├── errors.py                 # new error classes with codes
│   │   ├── monthly_focus.py          # NEW MonthlyFocusService: plan, save, change, undo, history,
│   │   │                             #   themes, themes_for_month (the FocusProvider)
│   │   └── monthly_review.py         # NEW MonthlyReviewService: draft, suggestions, store, versions, make current,
│   │                                 #   current_snapshots; CategoryCountsReader (protocol) and its 005 adapter
│   ├── api/
│   │   ├── errors_map.py             # codes of the new errors
│   │   └── routers/monthly.py        # NEW router and schemas (see contracts/api.md)
│   └── main.py                       # wiring (see the table above)
└── tests/
    ├── unit/
    │   ├── test_monthly.py                       # NEW: target, notes, markers, windows, outside focus
    │   ├── test_monthly_review_rules.py          # NEW: key result rules, trend, decisions, suggestions, payload
    │   └── test_monthly_schemas.py               # NEW: every enum and Literal value serializes
    ├── integration/
    │   ├── test_monthly_focus.py                 # NEW
    │   ├── test_monthly_changes.py               # NEW
    │   ├── test_monthly_focus_provider.py        # NEW: real provider with the weekly service
    │   ├── test_monthly_key_results.py           # NEW
    │   ├── test_monthly_review_counts.py         # NEW
    │   ├── test_monthly_review_values.py         # NEW
    │   ├── test_monthly_review_categories.py     # NEW
    │   ├── test_monthly_decisions.py             # NEW
    │   ├── test_monthly_snapshot.py              # NEW
    │   ├── test_monthly_legacy.py                # NEW
    │   ├── test_monthly_no_task_app_writes.py    # NEW
    │   ├── test_monthly_performance.py           # NEW
    │   ├── test_isolation.py, test_orphans.py    # CHANGED
    ├── e2e/test_monthly_api.py                   # NEW
    ├── e2e/test_postgres_app.py                  # CHANGED
    ├── fakes/                                    # no change (no port operation); CategoryCounts fake in the tests
    ├── migrations/test_migrations.py, test_postgres.py   # CHANGED: 0022
    └── live/
        ├── conftest.py                           # CHANGED: fixture that starts the real server on a port
        ├── test_monthly_live.py                  # NEW: the cycle against a real Vikunja (in process)
        └── test_monthly_http_live.py             # NEW: smoke test of the real server over HTTP

frontend/
├── lib/features/month/
│   ├── month_screen.dart             # REWRITTEN: month header, focus, progress, review entry, checklist
│   ├── month_api.dart                # NEW calls for /monthly/...
│   ├── month_models.dart             # NEW MonthPlan, FocusEntry, KeyResultRow, Suggestion, ReviewData,
│   │                                 #   Snapshot, ThemeResult, Decision, Trend ...
│   ├── month_controller.dart         # NEW Riverpod providers, draft state of the review per month
│   ├── focus_section.dart            # NEW the focus entries with target, progress, markers
│   ├── theme_picker.dart             # NEW searchable, grouped picker with the empty state and inline actions
│   ├── target_field.dart             # NEW whole number or empty, validation message
│   ├── key_result_strip.dart         # NEW key results next to a theme, flags
│   ├── suggestions_card.dart         # NEW carried-forward themes as editable suggestions
│   ├── focus_change_dialog.dart      # NEW swap, add, remove, target: effect first, undo
│   ├── focus_history_sheet.dart      # NEW the change log with undo
│   ├── review_screen.dart            # NEW the review (draft or stored), sections below
│   ├── review_results_section.dart   # NEW target against result per theme, outside focus, swapped out
│   ├── review_key_results_section.dart # NEW values, prompts, "not updated this month", the gap
│   ├── review_categories_section.dart  # NEW counts, hidden line, trend
│   ├── theme_decision_card.dart      # NEW carry, drop, replace, decide later, effect, swap-or-replace hint
│   ├── review_versions_sheet.dart    # NEW versions, make current, the new-version notice
│   └── earlier_format_view.dart      # NEW read-only old month goals
├── lib/core/planning_api.dart        # CHANGED: monthView removed
├── lib/features/projects/term_hint.dart   # CHANGED: new terms
├── lib/app.dart                      # route /month/review (the review screen); /month stays
└── test/
    ├── features/month/
    │   ├── month_screen_test.dart            # REWRITTEN
    │   ├── month_fake.dart                   # NEW server fake for /monthly/...
    │   ├── theme_picker_test.dart, target_field_test.dart, key_result_strip_test.dart,
    │   │   suggestions_card_test.dart, focus_change_test.dart, review_results_test.dart,
    │   │   review_key_results_test.dart, review_categories_test.dart, decisions_test.dart,
    │   │   snapshot_versions_test.dart, earlier_format_test.dart, orphan_month_test.dart   # NEW
    ├── features/checklists/period_checklists_test.dart   # CHANGED (fixtures)
    ├── today_button_test.dart                            # CHANGED (fixture)
    ├── screenshots/monthly_test.dart                     # NEW; planning_test.dart CHANGED
    ├── support/fake_api.dart                             # CHANGED
    └── theme/design_rules_test.dart                      # must pass

docs/
├── user/monthly-planning.md          # NEW, with screenshots and alt text
├── developer/monthly-cycle.md        # NEW
├── user/…, developer/…               # changed pages (see the table above)
├── images/monthly-*.png, planning-month.png
└── openapi.json                      # regenerated

scripts/check_docs.sh                 # CHANGED: required list
scripts/seed_demo.py                  # CHANGED: demo data for the walkthrough (made by feature 006)
```

**Structure Decision**: Follow the existing layers and the Flutter feature-folder pattern. The pure rules sit in `domain/monthly.py` so they are unit tested without a database and reused by feature 008. The month screen stays in `features/month/`, where the old screen was. The weekly code is not edited except for the wiring in `main.py`, because 004 defined the seam on purpose.

## Migration `0022_monthly_cycle`

- Revision `0022`, down revision `0021`. File `backend/migrations/versions/0022_monthly_cycle.py`. Uses `batch_alter_table` where SQLite needs it. If a lower number is still missing when this is written, the down revision is the newest existing one, and the single-head test catches a fork.
- Creates `monthly_focuses`, `monthly_focus_entries`, `focus_changes`, `monthly_reviews`, `monthly_review_snapshots` with the unique constraints and checks of data-model.md. It changes no existing table and runs no `UPDATE` (so month goals and stored period reviews are not touched, FR-028, FR-035).
- Downgrade drops the five tables. Focus, history and snapshots are lost on downgrade, and the migration test says so.
- Numbers 0019 to 0021 and 0023 belong to the other features. No other revision may use `0022`.
- Check: a migration test builds a database at `0021` with month goals, a stored period review and a monthly checklist, upgrades, and compares every row and id before and after.

## Delivery order (milestones)

1. **M1 Domain and data**: enums, pure rules, models, migration `0022`, tests. Done when unit and migration tests pass on SQLite and Postgres and `tach check` passes.
2. **M2 Focus service and the weekly seam**: plan, targets, changes, undo, history, picker list, the real `FocusProvider`, orphan handling. Done when the integration tests pass and the weekly picker shows the focus first with the real provider.
3. **M3 Review service**: counting, suggestions, key results and the gap, manual value write, category counts and trend, decisions, snapshot with versions, the 008 reader, no task app writes, performance. Done when the integration tests pass.
4. **M4 API**: router, schemas, error codes, OpenAPI snapshot, schema coverage test. Done when the e2e tests and the snapshot test pass.
5. **M5 Client**: screen, picker, targets, key results, changes, review, decisions, versions, earlier format, hints, empty states. Done when widget tests, `flutter analyze` and the design rules test pass.
6. **M6 Docs and proof**: user and developer docs, screenshots, smoke test of the real server over HTTP, browser walkthrough on a seeded live Vikunja, usability fixes, analyze and converge. Done when `just lint`, `just docs::check`, all tests and the walkthrough are clean.

## Requirement coverage

| Requirements | Milestone | Main files |
|---|---|---|
| FR-001 to FR-005, FR-009, FR-010, FR-043 | M1, M2, M4, M5 | `domain/monthly.py`, `services/monthly_focus.py`, `services/monthly_review.py` (suggestions), `routers/monthly.py`, `theme_picker.dart`, `suggestions_card.dart` |
| FR-006 to FR-008 | M2, M5 | `services/monthly_focus.py`, `key_result_strip.dart` |
| FR-011 | M2 | `services/monthly_focus.py` (`themes_for_month`), `main.py` |
| FR-012 to FR-015, FR-044 | M2, M5 | `services/monthly_focus.py`, `focus_change_dialog.dart`, `focus_history_sheet.dart` |
| FR-016 to FR-018 | M1, M3, M5 | `domain/monthly.py`, `services/monthly_review.py`, `review_results_section.dart` |
| FR-019 to FR-022 | M3, M5 | `services/monthly_review.py`, `review_key_results_section.dart` |
| FR-023, FR-024 | M3, M5 | `services/monthly_review.py` (reader), `review_categories_section.dart` |
| FR-025, FR-026 | M3, M5 | `domain/monthly.py` (`decision_effect`, `build_suggestions`), `theme_decision_card.dart` |
| FR-027 to FR-032 | M1, M3, M5 | `db/models/monthly.py`, `services/monthly_review.py`, `review_versions_sheet.dart` |
| FR-033 to FR-036 | M5, M6 | `month_screen.dart`, `earlier_format_view.dart`, docs |
| FR-037, FR-038 | M2, M3 | all services, `domain/monthly.py` |
| FR-039, FR-040 | M2, M3, M4 | services (user scoping), tests |
| FR-041, FR-042 | M5, M6 | `term_hint.dart`, docs |

## Open points for the project owner

These are choices beyond the spec. The plan takes the default and the tests follow it. Each one can change without touching the data model, except where noted.

- **O-1**: A swapped-out theme counts the milestones that became done from `counts_from` to the day it left. Work done under it after it left goes to the outside-focus list (research R-05). The spec does not say which. Alternative: count the whole month.
- **O-2**: A theme that left the focus cannot be added again in the same month. The user undoes the change instead (`left_this_month`, research R-02). Alternative: allow it and reset `counts_from` (needs a second window per entry, which changes the data model).
- **O-3**: The "latest value" of a key result is the newest series value even when its time stamp is after the month's end (a review done in the next month). The payload says so (`after_month_end`). Alternative: use the last value on or before the last day of the month (research R-07).
- **O-4**: The trend compares the month with the two calendar months before it. Each needs at least one completed task, else the answer is "not enough history". The share leaves the hidden count out (research R-09).
- **O-5**: The draft of a review lives on the device for the session, not on the server (research R-11). A restart of the app loses it.
- **O-6**: A plan save is refused for a past month and a mid-month change only works in the current month (research R-19). A late first plan for a past month is not possible.
- **O-7**: The focus provider returns `None` for a month without a saved focus, and a set without the swapped-out themes for a month with one (research R-04).
- **O-8**: The route `GET /views/month/{day}` stays although no client calls it (research R-12). Alternative: remove it with a note in the changelog.
- **O-9**: The reader of feature 005 (`CategoryCountsReader`) is shaped here. Task T001 checks the real name and shape in the code or design of 005 and adapts the adapter, not the reader.
- **O-10**: A decision "decide later" and "drop" give no suggestion. A carried theme that is no longer eligible is left out with a note (research R-10).
- **O-11**: The first plan of a month that is already in progress counts milestones from the first day of the month, not from the day of saving (research R-05).
- **O-12**: "Create a theme" in the picker uses the route `POST /annual/themes` of 006 (research R-14).

## Complexity Tracking

No violations. The five small tables are the simpler choice compared with a JSON column on a month row or columns on `weekly_plans` (research R-01 and R-06). The reader interface for 005 is one protocol and one adapter.
