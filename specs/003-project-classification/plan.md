# Implementation Plan: Project Classification and Onboarding

**Branch**: `003-project-classification` (developed on the session branch) | **Date**: 2026-11-11 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/003-project-classification/spec.md`

## Summary

Add a label (theme, milestone, maintenance, ignored) for every task-app project, stored only in Tefteri and keyed on the project identity. Tefteri proposes the labels from the tree and from past weekly plans, and the user confirms or corrects them on one `Projects` screen. Labels survive renames, moves and removal: a project that leaves the task app is marked orphaned, not deleted. A label history keeps every change so later features know which label a project had on a day. Renaming from Tefteri writes to the task app first. Connectors declare capabilities, and a connector that lacks a required one is refused when it is connected. Ignored and maintenance projects leave the weekly project picker. The screen is made for a first-time user: suggestions are already filled in, one button accepts them, every change can be undone and every term is explained once.

## Technical Context

**Language/Version**: Python 3.13 (backend), Dart 3.13 / Flutter 3.47 (client)

**Primary Dependencies**: FastAPI, SQLAlchemy 2 async, Alembic, httpx (existing); flutter_riverpod, go_router, dio (existing). No new dependency.

**Storage**: SQLite or PostgreSQL through Alembic. New migration `0018_project_labels` adds `project_labels` and `project_label_history` ([data-model.md](data-model.md)).

**Testing**: pytest (unit, integration with in-memory fakes, shared adapter contract tests, migrations incl. Postgres, live Vikunja), `flutter test` widget tests with `fake_api.dart`, screenshot tests, a browser walkthrough with Playwright.

**Target Platform**: Linux server in a container; Flutter web, Linux and Android clients.

**Project Type**: Web service plus Flutter client (existing layout).

**Performance Goals**: The classification payload for 500 projects loads in under 1 s on SQLite. A label save of 100 projects takes under 1 s. The tree stays smooth with 500 rows (lazy list).

**Constraints**: No label, field or tag is written to the task app (FR-003). The core layers never name Vikunja (constitution IV, `tach`). Theme tokens only in the UI. Docs in ASD-STE100.

**Scale/Scope**: One user has tens to a few hundred projects. 1 migration, 2 tables, 1 service, 1 router, 2 port operations, 1 screen, about 8 widgets, 2 doc pages.

## Constitution Check

| Principle | Status | How |
|---|---|---|
| I. Python backend, Flutter frontend | Pass | Same stack. |
| II. Justfile is the single interface | Pass | Every command in the quickstart is a `just` recipe. |
| III. Devbox | Pass | No new tool. The session installs the devbox packages by hand only because devbox is not available there. |
| IV. Pluggable backends | Pass | New operations are on the `TaskBackend` port with capability flags. Only `adapters/vikunja` names Vikunja. The shared contract test runs on every adapter. |
| V. Documented, tested, CI-verified | Pass | Tests listed in R-10. Migration test, OpenAPI snapshot, docstrings, docs. |
| VI. Two-audience docs, STE, screenshots | Pass | `docs/user/organizing-projects.md` and `docs/developer/project-classification.md`. Screenshots by `just docs::screenshots` from fake data. Vale and markdownlint run in `just lint`. |
| VII. Due date is canonical | Pass | This feature does not touch dates. |

Re-check after design: Pass. No complexity violations.

## Project Structure

### Documentation (this feature)

```text
specs/003-project-classification/
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
├── migrations/versions/0018_project_labels.py
├── src/tefteri/
│   ├── domain/
│   │   ├── enums.py                  # Capability additions, ProjectLabel, OrphanReason
│   │   ├── ports.py                  # TaskBackend.rename_container, restore_container
│   │   ├── classification.py         # NEW pure rules: propose, effective label, parent theme, eligible
│   │   └── capabilities.py           # NEW REQUIRED_TASK_CAPABILITIES, check function
│   ├── db/models/project_label.py    # NEW ProjectLabel, ProjectLabelHistory
│   ├── services/
│   │   ├── classification.py         # NEW tree, save, undo, preview, rename, create+label, restore
│   │   ├── sync.py                   # reconcile project_labels, mark orphans
│   │   ├── projects.py               # archive keeps the label row, marks archived
│   │   ├── connections.py            # capability check on connect and check
│   │   └── weekly.py                 # candidates use weekly-eligible
│   ├── api/routers/projects.py       # NEW
│   ├── api/routers/connections.py    # capabilities in responses
│   └── adapters/vikunja/adapter.py   # rename_container, restore_container, capabilities
└── tests/
    ├── unit/test_classification.py
    ├── integration/test_classification_service.py, test_orphans.py, test_weekly_picker_eligibility.py
    ├── integration/adapters/test_vikunja.py        # rename, restore
    ├── test_backend_contracts.py                   # contract additions; fakes get the new ops
    ├── migrations/test_migrations.py
    └── live/test_vikunja_live.py

frontend/
├── lib/features/projects/
│   ├── projects_screen.dart          # the Projects screen
│   ├── project_tree.dart, project_row.dart, label_chips.dart
│   ├── unsorted_card.dart            # entry card after first sync and in the weekly picker
│   ├── effect_dialog.dart, rename_dialog.dart, term_hint.dart
│   ├── projects_api.dart, projects_models.dart, projects_controller.dart
├── lib/app.dart                      # route /projects, navigation entry
├── lib/features/weekly/projects_step.dart   # unsorted reminder and empty-picker action
├── lib/features/settings/            # connection result shows missing capabilities
└── test/features/projects/, test/screenshots/projects_screens_test.dart, test/support/fake_api.dart

docs/
├── user/organizing-projects.md       # with screenshots and alt text
├── developer/project-classification.md
├── images/projects-*.png
└── openapi.json                      # regenerated
```

**Structure Decision**: Follow the existing layers and the Flutter feature-folder pattern. The pure rules sit in `domain` so they can be unit tested and reused by features 004 to 008 without importing the database.

## Delivery order (milestones)

1. **M1 Domain and data**: enums, capabilities, pure rules, models, migration, tests. Done when unit and migration tests pass on SQLite and Postgres.
2. **M2 Port and adapter**: rename and restore on the port, fake and Vikunja adapter, contract tests, live tests. Done when the contract tests and the live tests pass.
3. **M3 Service and sync**: reconcile and orphan handling, classification service (tree, save, preview, undo, rename, create+label, archive, restore), connect-time check, weekly picker eligibility. Done when the integration tests pass and the old weekly and archive tests are updated and pass.
4. **M4 API**: router, schemas, OpenAPI snapshot. Done when the e2e tests and the snapshot test pass.
5. **M5 Client**: screen, entry points, hints, undo, empty states, error messages, widget tests. Done when widget tests and `flutter analyze` pass.
6. **M6 Docs and proof**: user and developer docs, screenshots, browser walkthrough on a live Vikunja, usability fixes from what the walkthrough shows. Done when `just lint`, `just docs::check`, all tests and the walkthrough are clean.

## Complexity Tracking

No violations. The separate `project_labels` table is the simpler choice compared with changing every reader of `source_containers` (research R-01).
