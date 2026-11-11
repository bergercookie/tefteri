---

description: "Task list for feature 003-project-classification"
---

# Tasks: Project Classification and Onboarding

**Input**: Design documents in `/specs/003-project-classification/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/api.md, quickstart.md

**Tests**: Required (constitution V). Tests come first inside each phase.

**Organization**: Phases are the milestones M1 to M6 of plan.md. Inside a phase every task carries the user story it serves. Each phase ends with a completion-criteria task that must pass before the next phase starts.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (other files, no dependency on an unfinished task)
- **[US#]**: user story of spec.md: US1 review and fix labels, US2 routine and dormant projects, US3 survive rename/move/removal, US4 rename from Tefteri, US5 capability check, US6 new projects proposed later
- Commands use `source /root/tefteri-env.sh` in this session. On a normal machine use `devbox shell`.

## Phase 1: M1 Domain and data

- [x] T001 [P] [US1] Write unit tests for the proposal rule in `backend/tests/unit/test_classification.py`: top-level gives theme (`top_level`), deeper gives milestone (`nested`), a project in a past weekly plan gives milestone (`was_committed`) even at top level; the proposal is never `maintenance` or `ignored`
- [x] T002 [P] [US2] Write unit tests for effective label, eligible (FR-007: not orphaned, not ignored, no ignored ancestor, unclassified counts as its proposal) and weekly-eligible (FR-008: also not maintenance) in `backend/tests/unit/test_classification.py`
- [x] T003 [P] [US1] Write unit tests for parent theme (FR-021: nearest ancestor with effective label theme; none gives "no theme"; milestone under milestone; cycle in parent links does not loop) in `backend/tests/unit/test_classification.py`
- [x] T004 [P] [US5] Write unit tests for the required-capability check in `backend/tests/unit/test_capabilities.py`: returns the names of missing required capabilities in a stable order
- [x] T005 [P] Write migration tests for 0018 in `backend/tests/migrations/test_migrations.py`: tables `project_labels` and `project_label_history` exist, unique (`connection_id`, `remote_id`), cascade delete from connection, upgrade and downgrade work
- [x] T006 [US1] Add `ProjectLabel` (`theme`, `milestone`, `maintenance`, `ignored`) and `OrphanReason` (`missing`, `archived`) to `backend/src/tefteri/domain/enums.py`; add `Capability` members `RENAME_PROJECTS`, `RESTORE_PROJECTS`, `PROJECT_TREE`, `STABLE_PROJECT_IDS`, `CREATE_TASKS`, `COMPLETION_TIMES`
- [x] T007 [P] [US1] Implement the pure rules in `backend/src/tefteri/domain/classification.py` (`propose`, `effective_label`, `parent_theme`, `is_eligible`, `is_weekly_eligible`) with docstrings; no database or adapter import
- [x] T008 [P] [US5] Implement `REQUIRED_TASK_CAPABILITIES` (`SUBPROJECTS`, `ARCHIVE_PROJECTS`, `PROJECT_TREE`, `STABLE_PROJECT_IDS`, `CREATE_TASKS`, `COMPLETION_TIMES`) and `missing_required(capabilities)` in `backend/src/tefteri/domain/capabilities.py`
- [x] T009 [US1] Add models `ProjectLabel` and `ProjectLabelHistory` in `backend/src/tefteri/db/models/project_label.py` exactly as in data-model.md (`label` string(16) null; `orphaned_reason` string(16) null; unique (`connection_id`,`remote_id`); history `label` null, `from_at`, `batch_id` null, `source` string(16)); export them in `db/models/__init__.py`
- [x] T010 [US1] Write migration `backend/migrations/versions/0018_project_labels.py` and make T005 pass
- [x] T011 Completion criteria for M1: `just backend::test` and `just backend::test-postgres` pass; `just lint` passes for the backend files; `tach check` passes

## Phase 2: M2 Port and adapter

- [x] T012 [P] [US4] Add contract tests for `rename_container` and `restore_container` in `backend/tests/test_backend_contracts.py`: rename changes the title and keeps the id; restore returns an archived project to the list; a refused write raises and changes nothing
- [x] T013 [P] [US4] Add Vikunja adapter tests with the recorded HTTP fake in `backend/tests/integration/adapters/test_vikunja.py`: rename sends the title and reads the project back; a read-back that differs raises `NotSaved`; restore sends `is_archived=false`
- [x] T014 [US4] Add `rename_container(container, name)` and `restore_container(container)` to the `TaskBackend` protocol in `backend/src/tefteri/domain/ports.py`
- [x] T015 [P] [US4] Implement them in the in-memory fake `backend/tests/fakes/memory.py` and the Vikunja HTTP fake `backend/tests/fakes/http/vikunja.py`
- [x] T016 [US4] Implement them in `backend/src/tefteri/adapters/vikunja/adapter.py` and declare the new capabilities in `capabilities()`; do not declare `MOVE_TASKS`
- [x] T017 [P] [US4] Add live tests for rename and restore in `backend/tests/live/test_vikunja_live.py`
- [x] T018 Completion criteria for M2: `just backend::test` and `just backend::live-vikunja` pass; `grep -ri vikunja backend/src/tefteri --include=*.py -l` lists only `adapters/vikunja`, `config` and the registry as before

## Phase 3: M3 Service and sync

- [x] T019 [P] [US3] Integration test in `backend/tests/integration/test_orphans.py`: a project that is renamed and moved in the app keeps its label after sync (FR-009, FR-014); a project that is removed is marked orphaned with reason `missing`, keeps label and history, and every service that reads projects still works (SC-004); a project that returns clears the mark (FR-011)
- [x] T020 [P] [US1] Integration test in `backend/tests/integration/test_classification_service.py`: tree with proposals and `unsorted_count`; save one label and a batch; history rows are appended with one `batch_id` and never edited; `dry_run` writes nothing and returns the same effect as the real save; undo adds new history rows and a second undo of the same batch gives a conflict (FR-022, FR-023)
- [x] T021 [P] [US4] Integration test in the same file: rename writes to the app first and keeps the old name on failure (FR-013); the rename of an orphaned project is refused; `create project and label it` writes the app first and records nothing when the app fails (FR-024)
- [x] T022 [P] [US3] Integration test: archive from Tefteri marks the project orphaned with reason `archived`, keeps its label, keeps the plan name, and restore returns it only after the app restore works (FR-010, FR-027); update `backend/tests/integration/test_archive_project.py` for the changed behaviour
- [x] T023 [P] [US2] Integration test in `backend/tests/integration/test_weekly_picker_eligibility.py`: ignored projects, their descendants and maintenance projects are not in the weekly candidates; maintenance tasks still appear in the planner and daily lists; unclassified projects are listed and counted as unsorted (FR-007, FR-008, FR-025)
- [x] T024 [P] [US5] Integration test: connecting a task app that lacks a required capability returns an error that names it; a missing optional capability only turns its flag off (FR-015, FR-016)
- [x] T025 [US3] Implement reconcile in `backend/src/tefteri/services/sync.py`: after `_sync_containers`, create missing `project_labels` rows (label null), update `name` and `parent_remote_id`, clear the orphan mark for listed projects, mark unlisted live rows orphaned `missing`; never delete a label row; keep the existing removal of `SourceContainer` rows
- [x] T026 [US1] Implement `ClassificationService` in `backend/src/tefteri/services/classification.py`: `tree`, `save(changes, dry_run, source)`, `undo(batch_id)`, using `domain/classification.py`
- [x] T027 [US4] Add `rename`, `create_and_label`, `archive` and `restore` to the service; change `ProjectService.archive` in `backend/src/tefteri/services/projects.py` to call it and to mark the project archived instead of forgetting it
- [x] T028 [US5] Check capabilities in `backend/src/tefteri/services/connections.py` on create and on `check`; return `missing_required` and the optional flags
- [x] T029 [US2] Filter `WeeklyService.candidates` in `backend/src/tefteri/services/weekly.py` with `is_weekly_eligible`; add `unsorted_count`; update the weekly tests that list candidates
- [x] T030 Completion criteria for M3: all integration tests above and the whole `just backend::test` pass; `tach check` passes; the old archive and weekly tests are updated, not deleted

## Phase 4: M4 API

- [x] T031 [P] [US1] E2E test in `backend/tests/e2e/test_projects_api.py` for `GET /projects/classification`, `PUT /projects/labels` (with and without `dry_run`), `POST /projects/labels/undo`, private to the user (FR-019): another user gets 404
- [x] T032 [P] [US4] E2E test for `PATCH /projects/{id}`, `POST /projects`, `POST /projects/{id}/archive`, `POST /projects/{id}/restore` with the error codes of contracts/api.md
- [x] T033 [P] [US5] E2E test for the capability fields on `POST /connections` and `POST /connections/{id}/check`
- [x] T034 [US1] Add schemas and the router `backend/src/tefteri/api/routers/projects.py`; register it in the app; keep the old archive route calling the same service
- [x] T035 [US5] Add the capability fields to `backend/src/tefteri/api/routers/connections.py`
- [x] T036 Run `just backend::openapi`, commit `docs/openapi.json`; completion criteria for M4: `just backend::test`, `just backend::e2e` and the OpenAPI snapshot test pass

## Phase 5: M5 Client

- [x] T037 [P] [US1] Widget tests in `frontend/test/features/projects/projects_screen_test.dart`: suggestions are shown and marked as suggestions; groups Unsorted, Themes, Routines, Ignored, "No longer in your task app" with one sentence each; "Accept suggestions" saves all; one tap on a chip changes one project; search and collapse work with 300 projects
- [x] T038 [P] [US1] Widget tests for the effect dialog and undo: the dialog shows the numbers before saving; the snackbar offers Undo; Undo calls the API (FR-023)
- [x] T039 [P] [US2] Widget tests for the weekly picker: unsorted reminder is quiet and does not block; an empty picker offers "Label a project as theme" and "Create a theme" (FR-025)
- [x] T040 [P] [US3] Widget test: orphaned projects show their stored name and the reason in plain words, and have no rename control
- [x] T041 [P] [US4] Widget tests: rename dialog shows the error and keeps the old name when the API refuses; the rename control is hidden when the connection cannot rename
- [x] T042 [P] [US5] Widget test: the connection screen names the missing required capability in plain words
- [x] T043 [US1] Extend `frontend/test/support/fake_api.dart` and add `frontend/lib/features/projects/projects_models.dart`, `projects_api.dart`, `projects_controller.dart` (Riverpod) following the pattern of `features/weekly/weekly_api.dart`
- [x] T044 [US1] Build `projects_screen.dart`, `project_tree.dart`, `project_row.dart`, `label_chips.dart` with theme tokens only (`context.tefteri`, `Space`, `Corner`), `EmptyState` and `Loading`; the user-facing word for maintenance is "Routine" with the hint of research R-09
- [x] T045 [US1] Build `effect_dialog.dart`, `term_hint.dart` (first-use hint, dismissible, remembered per device) and the undo snackbar
- [x] T046 [US4] Build `rename_dialog.dart` and the create-theme action; hide controls by capability
- [x] T047 [US6] Build `unsorted_card.dart`; show it after the first sync of a task connection and in the weekly picker; add the route `/projects` and the navigation entry in `frontend/lib/app.dart` and `lib/core/shell.dart`; add keyboard access following `lib/core/shortcuts/`
- [x] T048 [US5] Show missing capabilities on the connection result in `frontend/lib/features/settings/connection_dialog.dart`
- [x] T049 Completion criteria for M5: `just frontend::test`, `just frontend::analyze`, `just frontend::format-check` pass; `test/theme/design_rules_test.dart` passes

## Phase 6: M6 Docs and proof

- [ ] T050 [P] [US1] Write `docs/user/organizing-projects.md` in simplified technical English: what the labels mean, how to accept suggestions, how to change one, how to undo, what orphaned means, how to rename; add it to the docs index
- [ ] T051 [P] Write `docs/developer/project-classification.md`: the tables, the rules in `domain/classification.py`, the capability table, how to make a new adapter declare them; update `docs/developer/adding-an-adapter.md` and `docs/developer/sync.md`
- [ ] T052 [P] [US1] Add screenshot tests in `frontend/test/screenshots/projects_screens_test.dart` with fake data (tree with suggestions, effect dialog, orphaned group, empty state); run `just docs::screenshots`; commit `docs/images/projects-*.png` with alt text in the guide
- [ ] T053 [US1] Browser walkthrough of quickstart section 2 with Playwright (Chromium) against a seeded live Vikunja and the built web client; save a screenshot per step in the scratchpad; record every confusing point
- [ ] T054 [US1] Fix every usability finding of T053 (wording, spacing, contrast, missing feedback, phone and dark mode); repeat T053 until a first-time run has no stuck point; re-run `just docs::screenshots`
- [ ] T055 Run `just lint` (includes markdownlint and Vale) and fix prose; run `just docs::check`
- [ ] T056 Run `speckit-analyze` and `speckit-converge` for this feature; append any unbuilt work to this file and finish it
- [ ] T057 Completion criteria for the feature: all tasks checked; `just test`, `just lint`, `just backend::e2e`, `just backend::test-postgres`, `just backend::live-vikunja`, `just docs::check` pass; the walkthrough passes; spec status set to Implemented; push

## Dependencies and order

- Phase 1 before all others. Phase 2 before Phase 3 (the service calls the port). Phase 3 before Phase 4. Phase 4 before Phase 5 (the client uses the API). Phase 6 last.
- Inside a phase, tasks marked [P] touch different files and can run together. Tests are written first and must fail before the code that satisfies them.

## MVP

US1, US2 and US3 together are the minimum that gives value: labels, hidden dormant and routine projects, and no loss on rename or removal. US4, US5 and US6 are small additions on the same base and ship in the same feature.

## Totals

57 tasks: Phase 1 11, Phase 2 7, Phase 3 12, Phase 4 6, Phase 5 13, Phase 6 8.
