# Implementation Plan: Annual Review

**Branch**: `008-annual-review` (developed on the session branch) | **Date**: 2026-11-11 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/008-annual-review/spec.md`, the decisions in `specs/planning-cycles/decisions.md`, the finished feature 003 (`specs/003-project-classification/`) as the model of depth, and the designs of features 004, 005, 006 and 007 that this feature reads.

## Summary

Replace the Year view with a read-only annual review. For one planning year it reads the current monthly review snapshots of feature 007 and the plan of feature 006 (goals, key results, links, history), and it computes nothing from tasks. For each key result it shows the start value, the target, the last stored value, one fixed result (hit when the last value in the year reached the target in its direction), a second line "reached by deadline", and twelve monthly values with visible gaps. For each key result it lists the linked themes with the milestones shipped inside the link dates, next to the key result movement, with a quiet hint when many milestones shipped and the key result moved less than 25% of its span. It shows the year split of goal-aligned, maintenance and off-plan work as one proportion bar and twelve month rows, summed from snapshot counts, with the hidden count apart. The drill-down reuses the statistics list of feature 005 and says that it is live. Missing months are marked and offer a way to open that month's review. A year with no snapshots, a year in progress, retired goals, orphaned themes and old snapshot shapes all open. "Start next year" opens annual planning with "from year N" and creates nothing. The only new stored data is one note for the year and one for each goal (`review_notes`). One migration, `0023_annual_review`.

## Technical Context

**Language/Version**: Python 3.13 (backend), Dart 3.13 / Flutter 3.47 (client)

**Primary Dependencies**: FastAPI, SQLAlchemy 2 async, Alembic, httpx (existing); flutter_riverpod, go_router, dio (existing). No new dependency.

**Storage**: SQLite or PostgreSQL through Alembic. New migration `0023_annual_review` adds `review_notes` ([data-model.md](data-model.md)). No existing table changes.

**Testing**: pytest (unit, integration with an in-memory snapshot reader and stored rows, e2e, migrations incl. Postgres, OpenAPI snapshot, a smoke test of the real server over HTTP against the live task app), `flutter test` widget tests with `fake_api.dart`, screenshot tests, a Playwright walkthrough against a seeded live task app.

**Target Platform**: Linux server in a container; Flutter web, Linux and Android clients.

**Project Type**: Web service plus Flutter client (existing layout).

**Performance Goals**: The review of a year with 20 themes, 10 key results and 12 snapshots is built in under 500 ms on SQLite with a fixed number of queries (R-14). It opens in under 2 s on a typical phone (SC-007).

**Constraints**: No recomputation of any month from tasks (FR-001, a test fails when the service reads `tasks`, `milestones` or `weekly_plans`). No write except notes (SC-002). The core layers never name the task app (constitution IV, `tach`). Theme tokens only in the UI. Docs in ASD-STE100. No hours or effort anywhere. The page never fails on missing, partial or old data (FR-027).

**Scale/Scope**: One user has a few goals per year, up to three key results per goal, up to about twenty themes and twelve snapshots. 1 migration, 1 table, 2 services (review read, notes), 1 router with 3 routes, 2 pure domain modules, 1 screen with about 12 widgets, 2 doc pages.

## Constitution Check

| Principle | Status | How |
|---|---|---|
| I. Python backend, Flutter frontend | Pass | Same stack. |
| II. Justfile is the single interface | Pass | Every command in the quickstart is a `just` recipe. The demo seed for the walkthrough gets the recipe `just backend::seed-annual-review` (task T074), not a raw script call. |
| III. Devbox | Pass | No new tool. The session helper `source /root/tefteri-env.sh` stands in for `devbox shell`. |
| IV. Pluggable backends | Pass | No port operation, no capability, no adapter change. `domain/annual_review.py` and `domain/snapshot_view.py` import only the standard library, `domain/enums.py`, `domain/key_results.py` (006) and `domain/work_categories.py` (005). Themes are read from `project_labels` (003). Check: `grep -ri vikunja backend/src/tefteri --include=*.py -l` lists only `adapters/vikunja`, `config` and the registry, as before. |
| V. Documented, tested, CI-verified | Pass | Tests first in every phase. Migration test, OpenAPI snapshot, a schema test for every enum value, a no-write test, a no-task-read test, a smoke test of the real server over HTTP. Docstrings on all public items. |
| VI. Two-audience docs, STE, screenshots | Pass | `docs/user/annual-review.md` and `docs/developer/annual-review.md`. Screenshots by `just docs::screenshots` from fake data with alt text. Vale and markdownlint run in `just lint`. Every doc that describes the Year view or the goal review history is changed in the same change (FR-024). |
| VII. Due date is canonical | Pass | The review shows key result deadlines of 006 (a Tefteri value). It writes no date to the task app. |

**Layer gates (tach)**: `tefteri.domain` has no dependency. `tefteri.db` models import `tefteri.db` and `tefteri.domain` only. `tefteri.services` imports `domain`, `db`, `auth` and `security`. The review service calls the services of 005, 006 and 007 through small protocols declared in `services/annual_review.py`, and `main.py` wires them. `tefteri.api` imports services, never an adapter. `tach check` must pass at the end of every milestone.

**Theme-token gate (frontend)**: all new UI takes colors, fonts, spacing and radii from `context.tefteri`, `Space` and `Corner`. It uses `EmptyState` and `Loading`. It follows the visual language of the work categories of 005 (the proportion bar and the category styles are reused, not copied). `frontend/test/theme/design_rules_test.dart` must pass. No Material default: no stock app bar, no elevated card, no bare list tile as the main structure. The series strip is drawn with a `CustomPainter` that takes its colors from the tokens, and it does not rely on color alone (gaps are drawn as an open marker with a label for screen readers).

Re-check after design: Pass. No complexity violations (see Complexity Tracking).

## Design decisions in short

The reasons and rejected options are in [research.md](research.md).

- **One reader of snapshots** (R-01): a protocol `SnapshotReader`, the real one wraps `MonthlyReviewService.current_snapshots` of 007. A fake serves the tests.
- **Tolerant payload reading** (R-02): `read_snapshot` returns `None` for every missing field. Old shapes load and show "not stored".
- **One hit rule, one owner** (R-03): `is_met` of 006 decides. The review chooses the value: the last value in the year from the snapshots. "Reached by deadline" gives `is_met` the last value stored on or before the deadline.
- **Contribution by date range** (R-04): milestones are counted by `done_on` inside the link dates. The year total counts distinct milestones.
- **Hint rule** (R-05): shipped at or above the sum of the monthly targets, at least one shipped, movement under 25% of the span. The mirror hint uses the same 25%.
- **Split from stored counts** (R-06): sum of snapshot counts, hidden apart, percentages from 005 on display.
- **Live drill-down is not ours** (R-07): reuse `GET /statistics/tasks`.
- **One note per scope** (R-08): `review_notes`, undo by writing the text again.
- **The unmet count is the count of planning** (R-09): called in process from 006.
- **Year view replaced, old reviews kept** (R-10).

## Open points that need a decision from the project owner

These are decisions beyond the spec. Each one has a default in the design. Change them in the spec first (speckit-clarify), then in the design files.

1. **Snapshot precision of "reached by deadline"** (R-03): the line is computed from the monthly snapshots, so a value entered and replaced inside one month is not seen. The alternative is a live call of `value_on(deadline)` of 006, which is exact but breaks "snapshots only".
2. **Sum of monthly targets and the guard "at least one shipped"** in the hint rule (R-05), and the symmetric 25% for "moved a lot".
3. **One note per goal and per year** instead of a list of notes (R-08).
4. **The unmet count equals the planning count** (R-09), so it can differ from the number of "missed" rows when a value was entered after the last snapshot.
5. **Connections** (R-12): no filter by the active connection, because goals and snapshots have no connection.
6. **`GET /views/year/{year}` stays** on the server for now (R-10).
7. **A note after the year ends**: allowed for a past year, refused for a future year.

## Changes to existing behaviour

| File | Change |
|---|---|
| `frontend/lib/features/year/year_screen.dart` | Deleted. The route `/year` shows `AnnualReviewScreen`. The year checklist banner (`PlanningChecklist`, kind year) moves into the new screen unchanged. |
| `frontend/lib/app.dart` | `/year` builds `AnnualReviewScreen`. New route `/year/:year`. The route `/review` reads the query `period` and `year` and filters the history. |
| `frontend/lib/core/shell.dart`, `frontend/lib/core/shortcuts/keymap.dart` | The view `Year` is named `Year review`. Path and key `y` stay. |
| `frontend/lib/core/planning_api.dart` | `yearView` is removed. `PeriodView` is still used by month and week (and by 007 until it removes `monthView`). |
| `frontend/lib/features/review/plan_history_screen.dart` | Accepts a period type and a year as filter, shown as a chip with a clear action. No change to the data it loads. |
| `frontend/test/support/fake_api.dart` | Add `annualReviewJson`, `reviewNoteJson` and snapshot fixtures. |
| `frontend/test/features/year/year_screen_test.dart` | Deleted. Replaced by `test/features/annual_review/*`. |
| `frontend/test/features/checklists/period_checklists_test.dart` | The year case builds `AnnualReviewScreen` with a fake review and checks that the annual checklist and the hint still show. |
| `frontend/test/today_button_test.dart` | The two year cases build `AnnualReviewScreen`. The period label stays. |
| `frontend/test/shell_test.dart`, `frontend/test/core/shortcuts_test.dart` | The label `Year review`. |
| `frontend/test/screenshots/planning_test.dart` | Remove the `planning-year` screenshot and the `_yearGoal` fixture use for it. |
| `frontend/test/features/review/review_screens_test.dart` | Add the filter case of `/review?period=year&year=N`. |
| `backend/tests/integration/test_isolation.py` | Add the review and the notes (another user: 404, no data). |
| `backend/tests/integration/conftest.py` | Add the helpers `store_snapshot` and `store_review_note` (R-15). |
| `backend/tests/migrations/test_migrations.py` | Add the 0023 tests. The single-head test now sees `0023`. |
| `backend/src/tefteri/main.py` | Create and register `AnnualReviewService` and `ReviewNoteService`; include the router; wire the readers. |
| `backend/src/tefteri/domain/enums.py`, `db/models/__init__.py` | Add the five enums, export `ReviewNote`. |
| `docs/openapi.json` | Regenerate. |
| `docs/user/reviews-and-retrospectives.md` | The section about a year plan points to the annual review. The stored period reviews stay described. |
| `docs/user/annual-planning.md` (006) | "Start a new year" links to the annual review. |
| `docs/user/index.md`, `docs/developer/index.md`, `docs/user/shortcuts.md` | Index entries, the new guide, `Y` opens the year review. |
| `docs/developer/annual-planning.md` (006), `docs/developer/testing.md` | How 008 reads the plan and the seed script; the new tests. |
| `scripts/check_docs.sh` | Required list: add `user/annual-review.md` and `developer/annual-review.md`. |
| `docs/images/` | Remove `planning-year.png`. Add `annual-review-*.png`. |

Tests that must **not** change (a check in T069): `backend/tests/integration/test_planning.py` and `test_checklists.py` calls of `GET /views/year/{year}` keep passing, because the server route stays.

## Project Structure

### Documentation (this feature)

```text
specs/008-annual-review/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/api.md
├── checklists/requirements.md
└── tasks.md          # created by speckit-tasks
```

### Source Code (repository root)

```text
backend/
├── migrations/versions/0023_annual_review.py
├── src/tefteri/
│   ├── domain/
│   │   ├── enums.py                  # KeyResultOutcome, DeadlineState, MonthStatus, ThemeHint, ReviewEmptyReason
│   │   ├── snapshot_view.py          # NEW tolerant reader of a snapshot payload
│   │   └── annual_review.py          # NEW pure rules: outcome, last value, deadline line, series, peak,
│   │                                 #   link months, contribution, hint, split, coverage, month status
│   ├── db/models/review_note.py      # NEW ReviewNote
│   ├── services/
│   │   ├── annual_review.py          # NEW AnnualReviewService, protocols SnapshotReader, PlanReader, SeedCounter
│   │   └── review_notes.py           # NEW ReviewNoteService
│   ├── api/routers/annual_review.py  # NEW /annual-review/...
│   └── main.py                       # CHANGED wiring
├── tests/
│   ├── unit/test_annual_review_rules.py, test_snapshot_view.py, test_annual_review_schema.py
│   ├── integration/test_annual_review_service.py, test_annual_review_contribution.py,
│   │   test_annual_review_split.py, test_annual_review_missing.py, test_annual_review_history.py,
│   │   test_annual_review_next_year.py, test_annual_review_no_write.py, test_review_notes.py,
│   │   test_annual_review_performance.py, test_isolation.py, conftest.py
│   ├── e2e/test_annual_review_api.py
│   ├── migrations/test_migrations.py
│   └── live/test_annual_review_live.py        # the smoke test of the real server over HTTP
└── scripts: ../scripts/seed_annual_review.py  # run by `just backend::seed-annual-review`

frontend/
├── lib/
│   ├── app.dart, core/shell.dart, core/shortcuts/keymap.dart, core/planning_api.dart   # CHANGED
│   └── features/
│       ├── annual_review/
│       │   ├── annual_review_screen.dart, rule_card.dart, month_coverage_strip.dart
│       │   ├── goal_review_card.dart, key_result_row.dart, series_strip.dart
│       │   ├── theme_contribution_list.dart, year_split_card.dart, drill_down_sheet.dart
│       │   ├── note_editor.dart, next_year_card.dart
│       │   └── annual_review_api.dart, annual_review_models.dart, annual_review_controller.dart
│       ├── review/plan_history_screen.dart   # CHANGED (filter)
│       └── year/                             # DELETED
└── test/features/annual_review/, test/screenshots/annual_review_screens_test.dart, test/support/fake_api.dart

docs/
├── user/annual-review.md
├── developer/annual-review.md
├── images/annual-review-*.png
└── openapi.json
```

**Structure Decision**: Follow the existing layers and the Flutter feature-folder pattern. The pure rules sit in `domain` so they are unit tested without a database. The service reads other features through protocols so it can be tested with fakes and so `tach` stays green. The review is a new feature folder, and the old `features/year` folder is deleted because the Year view is replaced.

## Requirement coverage

| Requirements | Milestone | Main files |
|---|---|---|
| FR-001, FR-014, FR-026 | M1, M2 | `services/annual_review.py` (reader), test `test_annual_review_no_write.py` |
| FR-002, FR-003, FR-004, FR-025 | M1, M2, M4 | `domain/annual_review.py`, `key_result_row.dart`, `series_strip.dart` |
| FR-005 to FR-007 | M1, M2, M4 | `domain/annual_review.py`, `theme_contribution_list.dart` |
| FR-008, FR-009 | M1, M2, M4 | `domain/annual_review.py`, `year_split_card.dart`, `drill_down_sheet.dart` |
| FR-010, FR-011, FR-012, FR-027 | M2, M4 | `month_coverage_strip.dart`, `annual_review_screen.dart` (states) |
| FR-013, FR-015 | M2, M4 | `services/annual_review.py`, `goal_review_card.dart` |
| FR-016 | M1 | `domain/snapshot_view.py` |
| FR-017 | M1, M2, M3, M4 | `db/models/review_note.py`, `services/review_notes.py`, `note_editor.dart` |
| FR-018 to FR-020 | M2, M4 | `services/annual_review.py` (`SeedCounter`), `next_year_card.dart` |
| FR-021 | M5 | `app.dart`, `plan_history_screen.dart` |
| FR-022 | M3 | router, `test_isolation.py` |
| FR-023, FR-028 | M4, M6 | widgets, term hints, screenshots, walkthrough |
| FR-024 | M6 | docs |
| FR-029 | M2, M4 | `moved_after_snapshot` |

## Delivery order (milestones)

1. **M1 Domain and data**: enums, tolerant snapshot reader, pure rules, `review_notes` model, migration `0023`, tests. Done when unit and migration tests pass on SQLite and Postgres and `tach check` passes.
2. **M2 Service**: the review read (outcomes, series, contributions, split, coverage, mid-year, orphans, next year), the notes service, wiring. Done when the integration tests pass, including the no-write, no-task-read and performance tests.
3. **M3 API**: router, schemas, OpenAPI snapshot, e2e tests, the smoke test of the real server over HTTP. Done when the e2e tests, the snapshot test and the live smoke test pass.
4. **M4 Client**: models, API, controller, screen and widgets, terms, states, notes with undo, next year. Done when widget tests and `flutter analyze` pass.
5. **M5 Year view replaced**: route, nav, shortcuts, history filter, removal of the old screen, update of the old tests. Done when `just frontend::test` passes and nothing still imports `features/year`.
6. **M6 Docs and proof**: user and developer docs, screenshots, the seed recipe, the browser walkthrough on a live task app, usability fixes, lint, analyze and converge. Done when `just lint`, `just docs::check`, all tests and the walkthrough are clean.

## Complexity Tracking

No violations. Two choices add a little structure, and each is the simpler option compared with the alternative: protocols for the three readers (R-01, R-09) instead of importing the other services' internals, and one note per scope (R-08) instead of a list of notes.
