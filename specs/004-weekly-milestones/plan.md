# Implementation Plan: Weekly Planning and Review with Milestone Projects

**Branch**: `004-weekly-milestones` (developed on the session branch) | **Date**: 2026-11-11 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/004-weekly-milestones/spec.md`

## Summary

Change the existing weekly flow in place. The unit of weekly commitment becomes a milestone project (feature 003 label `milestone`). `WeeklyPlanProject` grows into the milestone commitment: it points to a `milestones` row, keeps the theme at the time and stores the review decision. The cap of three stops being a limit and becomes a warning on milestone count. The look-back choices carry and backlog are replaced by four decisions (keep and recommit, keep but park, close and return tasks, decide later). Old rows are mapped on read and are never rewritten. A recommit writes a rollover event with its own expected marker, and two unmarked events in a row show a nudge. A milestone stores a done date and the theme it had at that moment (read later by features 007 and 008). Closing a milestone moves its open tasks to the parent theme through a new optional port capability `MOVE_TASKS`, declared by the Vikunja adapter, and the close can be undone. The monthly focus (feature 007) is read through a small provider that returns nothing until 007 exists. The weekly "done outside the plan" list (feature 005) is not built yet, so `done_outside_plan` stays as it is and the hand-over is written down.

## Technical Context

**Language/Version**: Python 3.13 (backend), Dart 3.13 / Flutter 3.47 (client)

**Primary Dependencies**: FastAPI, SQLAlchemy 2 async, Alembic, httpx (existing); flutter_riverpod, go_router, dio (existing). No new dependency.

**Storage**: SQLite or PostgreSQL through Alembic. New migration `0019_weekly_milestones` adds `milestones`, `milestone_rollovers`, `milestone_closures` and six nullable columns on `weekly_plan_projects` ([data-model.md](data-model.md)). The numbers 0020 to 0023 are reserved for features 006, 005, 007 and 008.

**Testing**: pytest (unit, integration with in-memory fakes, shared adapter contract tests, migrations incl. Postgres, live Vikunja), `flutter test` widget tests with the weekly fake, screenshot tests, a browser walkthrough with Playwright.

**Target Platform**: Linux server in a container; Flutter web, Linux and Android clients.

**Project Type**: Web service plus Flutter client (existing layout).

**Performance Goals**: The picker for 500 projects loads in under 1 s on SQLite. A review of 10 milestones saves in under 1 s without a close. A close moves tasks one by one, so its time is the task app's time per task; the screen shows progress.

**Constraints**: No Vikunja name in the core layers (`tach`). No label, state or counter is written to the task app (the only task app writes are the ones that exist today, plus the move of a task and the creation of a milestone project and of tasks). Theme tokens only in the UI. Docs in ASD-STE100. A weekly plan never fails when a milestone or theme is orphaned.

**Scale/Scope**: One user has tens to a few hundred projects and plans 1 to 4 milestones a week. 1 migration, 3 tables, 6 columns, 3 services (2 new), 1 new router, 6 new routes on the weekly router, 1 port operation, about 12 new or changed widgets, 4 doc pages changed.

## Constitution Check

| Principle | Status | How |
|---|---|---|
| I. Python backend, Flutter frontend | Pass | Same stack. |
| II. Justfile is the single interface | Pass | Every command in the quickstart and in `tasks.md` is a `just` recipe (`just backend::test`, `just backend::openapi`, `just backend::live-vikunja`, `just frontend::test`, `just docs::screenshots`, `just docs::check`, `just lint`). The browser walkthrough uses `just serve`. No new inline CI logic. |
| III. Devbox | Pass | No new tool. The session sources `/root/tefteri-env.sh` only because devbox is not available there. |
| IV. Pluggable backends | Pass | `MOVE_TASKS` and `move_task` are on the `TaskBackend` port. Only `adapters/vikunja` names Vikunja. The shared contract test runs on every adapter. The new domain module `domain/milestones.py` has no import of a database, an adapter or a task app name. `tach check` stays green: `domain` depends on nothing, `services` on `domain` and `db`, `api` on `services`. The in-memory fake proves the service without a live Vikunja. `grep -ri vikunja backend/src/tefteri --include=*.py -l` still lists only `adapters/vikunja`, `config`, the registry and the existing weekly router URL helper. |
| V. Documented, tested, CI-verified | Pass | Tests are listed per phase in [tasks.md](tasks.md), tests first. Migration test with old rows, OpenAPI snapshot, docstrings on every new public module, class and function, widget docs. |
| VI. Two-audience docs, STE, screenshots | Pass | User guide `docs/user/weekly-planning.md` and `docs/user/organizing-projects.md` changed. Developer guide `docs/developer/weekly-planning.md` changed. Prose in ASD-STE100, checked by Vale in `just lint`. New screenshots from `just docs::screenshots` with fake data and alt text. The glossary words are used as written. |
| VII. Due date is canonical | Pass | The feature writes no planning date. Giving a task a day still uses `TaskService.schedule_date` (due date). The park decision no longer clears due dates (research R-13). A moved task keeps its due date. |
| UI rules of `AGENTS.md` | Pass | Colors, fonts, spacing and radii come from `context.tefteri`, `Space` and `Corner`. `EmptyState` and `Loading` for empty and loading states. No `Color(0x...)`, no `Colors.*` and no font names in `lib/features`. `frontend/test/theme/design_rules_test.dart` enforces it. Screenshots are looked at in light and dark and at phone and desktop widths (task T079). |

Re-check after design: Pass. One note: the design adds a provider seam for the monthly focus (`services/focus.py`). It is the smallest way to read data that does not exist yet without a dependency on feature 007 (research R-14). No complexity violation.

## Project Structure

### Documentation (this feature)

```text
specs/004-weekly-milestones/
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
├── migrations/versions/0019_weekly_milestones.py        # NEW: 3 tables, 6 columns, no UPDATE
├── src/tefteri/
│   ├── domain/
│   │   ├── enums.py                  # MilestoneState, ReviewDecision, Capability.MOVE_TASKS
│   │   ├── milestones.py             # NEW pure rules: commit_kind, completion, needs_rescope,
│   │   │                             #   decision_of, close_options, over_cap, outside_focus, focus_share
│   │   ├── periods.py                # month_of_week
│   │   ├── capabilities.py           # MOVE_TASKS optional, report_for flag move_tasks
│   │   └── ports.py                  # TaskBackend.move_task
│   ├── db/models/
│   │   ├── milestone.py              # NEW Milestone, MilestoneRollover, MilestoneClosure
│   │   ├── weekly.py                 # WeeklyPlanProject: 6 new columns, new unique constraint
│   │   └── __init__.py               # export the new models
│   ├── services/
│   │   ├── errors.py                 # Invalid gets an optional code
│   │   ├── focus.py                  # NEW FocusProvider, NoFocus (seam for feature 007)
│   │   ├── milestones.py             # NEW MilestoneService: ensure, done-state, settle, mark done, reopen
│   │   ├── milestone_close.py        # NEW close and return, retry, undo (uses move_task)
│   │   ├── weekly.py                 # picker, add, create milestone, add task, commit, look-back
│   │   │                             #   summary, review decisions, MILESTONE_CAP, no hard cap
│   │   ├── tasks.py                  # move_to_container (local copy after a move)
│   │   ├── sync.py                   # settle after sync_connection
│   │   ├── connections.py            # capability report carries move_tasks (via report_for)
│   │   ├── classification.py         # capabilities flag move_tasks in ConnectionView
│   │   └── project_labels.py         # helper: milestone rows by project, theme name lookup
│   ├── api/
│   │   ├── errors_map.py             # code of Invalid
│   │   └── routers/
│   │       ├── weekly.py             # schemas and routes (see contracts/api.md)
│   │       ├── milestones.py         # NEW router
│   │       ├── connections.py        # optional flags gain move_tasks
│   │       └── projects.py           # capabilities gain move_tasks
│   ├── adapters/vikunja/adapter.py   # move_task, capability MOVE_TASKS
│   └── main.py                       # wire MilestoneService, close service, NoFocus, router
└── tests/
    ├── unit/test_milestones.py, test_capabilities.py (extended), test_periods.py
    ├── integration/
    │   ├── test_weekly.py                        # changed (see the table below)
    │   ├── test_weekly_picker_eligibility.py     # changed: milestone-only picker
    │   ├── test_archive_project.py               # changed: review body
    │   ├── test_milestone_picker.py, test_milestone_create.py, test_weekly_cap.py,
    │   │   test_weekly_focus.py, test_milestone_completion.py, test_weekly_review_decisions.py,
    │   │   test_milestone_close.py, test_weekly_review_summary.py, test_weekly_legacy_plans.py,
    │   │   test_weekly_tasks_inline.py             # NEW
    │   ├── test_backend_contracts.py             # move_task contract
    │   ├── test_capability_check.py              # move_tasks flag
    │   ├── test_orphans.py                       # weekly screens with an orphaned milestone
    │   └── adapters/test_vikunja.py              # move_task with the HTTP fake
    ├── e2e/test_milestones_api.py                # NEW
    ├── e2e/test_projects_api.py                  # changed: move_tasks flag
    ├── fakes/memory.py, fakes/http/vikunja.py    # move_task, refuse switch
    ├── migrations/test_migrations.py             # 0019 with old rows
    └── live/test_vikunja_live.py                 # weekly loop and move_task

frontend/
├── lib/features/weekly/
│   ├── weekly_models.dart            # MilestoneCandidate, ThemeGroup, MilestoneInfo, ReviewSummary,
│   │                                 #   Decision, CloseInfo; plan cap fields; no maxProjects
│   ├── weekly_api.dart               # candidates, themes, milestones, add task, decisions, close
│   ├── weekly_screen.dart            # step texts, no "up to three", zero-milestone commit
│   ├── projects_step.dart            # becomes the milestone picker (grouped by theme)
│   ├── milestone_picker.dart         # NEW grouped list, focus group, unsorted group, empty states
│   ├── new_milestone_dialog.dart     # NEW replaces NewSubprojectDialog (name and done-state)
│   ├── cap_notice.dart               # NEW quiet warning over the cap
│   ├── rescope_nudge.dart            # NEW nudge card
│   ├── look_back_step.dart           # becomes the review: summary and decisions
│   ├── review_summary.dart           # NEW numbers, pace, focus share, empty note
│   ├── decision_card.dart            # NEW four choices, expected marker, mark done
│   ├── close_dialog.dart             # NEW effect, confirm, partial failure, reopen
│   ├── tasks_step.dart               # "Not this week" wording, inline add task, empty state
│   ├── finish_step.dart              # milestones wording, zero milestones allowed
│   ├── history_view.dart             # decisions under the new names, legacy rows
│   ├── weekly_card.dart              # wording
│   └── weekly_widgets.dart           # shared bits (Notice, Counter) reused
├── lib/features/projects/
│   ├── term_hint.dart                # new terms: milestone, done-state, committed, parked, rollover
│   ├── projects_models.dart          # capability moveTasks
│   └── unsorted_card.dart            # reused in the picker (no change expected)
├── lib/features/settings/connection_dialog.dart   # optional flag shown (move_tasks)
├── lib/app.dart                      # no new route expected
└── test/
    ├── features/weekly/weekly_fake.dart, weekly_screen_test.dart, picker_unsorted_test.dart,
    │   weekly_card_test.dart              # changed
    ├── features/weekly/milestone_picker_test.dart, new_milestone_dialog_test.dart,
    │   cap_notice_test.dart, review_decisions_test.dart, close_dialog_test.dart,
    │   rescope_nudge_test.dart, review_summary_test.dart, legacy_plan_test.dart,
    │   inline_task_test.dart              # NEW
    ├── screenshots/weekly_test.dart       # changed
    ├── support/fake_api.dart              # routes for the new endpoints
    └── theme/design_rules_test.dart       # must pass

docs/
├── user/weekly-planning.md               # rewritten sections, screenshots, alt text
├── user/organizing-projects.md           # milestones and done-state, picker link
├── user/troubleshooting.md               # close hidden, move failed
├── user/reviews-and-retrospectives.md    # one line: the weekly look-back has no goals
├── developer/weekly-planning.md          # data, flow, rules, 005 hand-over
├── developer/project-classification.md   # capability table gains MOVE_TASKS
├── developer/adding-an-adapter.md        # MOVE_TASKS contract
├── developer/sync.md                     # settle after a full sync
├── developer/testing.md                  # new test files
├── images/weekly-*.png                   # regenerated and new
└── openapi.json                          # regenerated
```

**Structure Decision**: Follow the existing layers and the Flutter feature-folder pattern. Pure rules sit in `domain/milestones.py` so they are unit tested without a database, and features 005 to 008 reuse them. The weekly flow is changed in place (`weekly.py`, `weekly_screen.dart`, the steps). Only the parts that have a new, separate responsibility become new files: the milestone state and completion (`services/milestones.py`), the close with its task moves (`services/milestone_close.py`), the focus seam (`services/focus.py`) and the milestone router.

## Migration `0019_weekly_milestones`

- Revision `0019`, down revision `0018`. File `backend/migrations/versions/0019_weekly_milestones.py`. Uses `batch_alter_table` for SQLite.
- Creates `milestones`, `milestone_rollovers`, `milestone_closures`. Adds `milestone_id`, `theme_project_id`, `theme_name`, `decision`, `expected_rollover`, `decided_at` to `weekly_plan_projects`, all nullable, with no default and no backfill. Adds the unique constraint (`plan_id`, `milestone_id`).
- Existing weekly rows: not changed. `carry` and `backlog` are mapped on read (research R-03). A migration test and an integration test prove it.
- Downgrade drops the three tables and the six columns.
- Numbers 0020 to 0023 stay free for features 006, 005, 007 and 008. No other revision may use `0019`.

## Existing tests that must change

| Test | File | Why | Change |
|---|---|---|---|
| `test_a_week_holds_at_most_three_projects` | `backend/tests/integration/test_weekly.py` | The hard cap of three is gone (FR-006). | Rename to a warning test: the fourth project is accepted (201), `over_cap` is true, a remove clears it. The "at most 3" 422 is removed. |
| `test_subproject_needs_room_and_support_and_creates_nothing_otherwise` | same | The "needs room" part (the cap) is gone. The route is `/milestones` with a done-state. | Keep the support and the unavailable parts on the new route; replace the full-week part with a blank done-state that is refused before any call to the task app. |
| `test_new_subproject_is_created_in_the_task_app_and_added` | same | A new sub-project is a labelled milestone with a done-state. | Post to `/milestones` with `done_state`; check the label, the done-state and the entry. |
| `test_look_back_counts_what_was_done_and_applies_the_decisions` | same | `leftover` and `finished_anyway` are replaced by `decision`, `expected` and `mark_done`. Backlog no longer clears due dates. | Use the new body. The line `assert remote["p2 task 2"].due_at is None  # backlog` is replaced by an assertion that park leaves the due date. |
| `test_review_of_unknown_or_uncommitted_week_is_refused` | same | The invalid value `leftover: "x"` is now a validation error on `decision`. | Send `decision: "x"` and expect 422. |
| `test_commit_needs_a_project_and_a_started_plan` | same | A plan with zero milestones can be committed (R-17). | Keep the 404 for a missing plan; expect 200 for an empty plan. |
| `test_candidates_list_task_projects_with_open_task_counts` | same | The picker is milestone-only with new fields. | Expect `kind`, `theme`, `state`, `in_focus` and that a labelled theme is not listed. |
| the helpers `_setup`, `_add` | same | Projects are unclassified leaf projects, so a pick labels them. | Keep the helpers; add one that labels projects through `PUT /projects/labels`. |
| `test_weekly_picker_eligibility` tests | `backend/tests/integration/test_weekly_picker_eligibility.py` | The picker no longer lists themes. | Assert that a theme is absent, a leaf unclassified project is `unsorted`, a milestone is `milestone`. |
| the weekly review call in the archive test | `backend/tests/integration/test_archive_project.py` | Body of the review. | Use `decision`. |
| the weekly checks in the orphan test | `backend/tests/integration/test_orphans.py` | Orphaned milestone in plan and look-back (SC-009). | Extend, do not weaken. |
| the weekly live test | `backend/tests/live/test_vikunja_live.py` | `/subprojects` is replaced. | Use `/milestones` and cover `move_task`. |
| capability report tests | `backend/tests/unit/test_capabilities.py`, `backend/tests/integration/test_capability_check.py`, `backend/tests/e2e/test_projects_api.py` | `optional` gains `move_tasks`. | Extend the expected dictionaries. |
| the OpenAPI snapshot | `backend/tests/unit/test_openapi_snapshot.py` with `docs/openapi.json` | New and changed routes. | Regenerate with `just backend::openapi`. |
| migration tests | `backend/tests/migrations/test_migrations.py` | New head `0019`. | Add 0019 tests; `test_single_head_revision` and `test_up_down_consistency` must pass. |
| `chooses at most three projects` | `frontend/test/features/weekly/weekly_screen_test.dart` | No hard limit in the client. | Choose four, see the warning, commit. |
| `committing needs at least one planned task` | same | Zero milestones is valid. | Commit works with no milestone. |
| `a new subproject waits for tasks and picks them up`, `a subproject can be created under a chosen parent row` | same | The dialog needs a done-state. | Use the new dialog. |
| `carried-over tasks are shown next to their project` | same | `carried_tasks` is now about recommitted milestones. | Update the fake and the text. |
| `a parked task leaves the plan and can be put back` | same | Wording "Not this week". | Update finders. |
| the look-back group (`asks about each project and shows the counters`, `saves the decisions and then shows the earlier weeks`, `the look-back can archive a project when it is saved`, `history says how realistic the plans are`) | same | `carry` and `backlog` keys are replaced by the four decisions. | Rewrite against `decision_card.dart`. |
| the unsorted and empty picker tests | `frontend/test/features/weekly/picker_unsorted_test.dart` | New picker widget. | Keep every behaviour; change the widgets they find. |
| the card text tests | `frontend/test/features/weekly/weekly_card_test.dart` | Wording "choose milestones". | Update strings. |
| the weekly fake | `frontend/test/features/weekly/weekly_fake.dart` | New JSON shape. | Extend with the milestone fields and the new routes. |
| the screenshot tests | `frontend/test/screenshots/weekly_test.dart` | New screens. | Rewrite; regenerate the images. |
| `check_docs.sh` image check | `scripts/check_docs.sh` | New images need alt text. | No code change; the check must pass. |

Tests that must **not** change (they guard behaviour that stays): `week_progress_test.dart` (the cadence, burndown and done-outside-plan card), the spread, park-as-"Not this week", archive-in-look-back and refresh tests, and every 003 classification test.

## Delivery order (milestones)

1. **M1 Domain and data**: enums, pure rules, models, migration `0019`, tests. Done when unit and migration tests pass on SQLite and Postgres, and `tach check` passes.
2. **M2 Port and adapter**: `MOVE_TASKS`, `move_task`, fakes, Vikunja adapter, contract tests, live test. Done when the contract tests and the live tests pass and no Vikunja name leaves `adapters/vikunja`.
3. **M3 Services**: milestone service and settle, focus seam, picker, create, cap, commit, review decisions, close and reopen, summary, legacy mapping. Done when the integration tests pass and the changed old tests pass.
4. **M4 API**: schemas, routes, new router, error codes, capability flags, OpenAPI snapshot. Done when the e2e tests and the snapshot test pass.
5. **M5 Client**: models, picker, new milestone dialog, cap notice, tasks step, review, decisions, close dialog, nudge, history, hints. Done when widget tests, `flutter analyze` and the design rules test pass.
6. **M6 Docs and proof**: user and developer docs, screenshots, browser walkthrough against a seeded live Vikunja, usability fixes, converge and analyze. Done when `just lint`, `just docs::check`, all tests and the walkthrough are clean.

## Hand-over to feature 005 (weekly list)

The weekly "done outside the plan" list is feature 005 and is not built. Until then:

- `WeeklyService.done_outside_plan`, `ExtraDone`, `MAX_EXTRA_DONE` and the card `week_progress_card.dart` stay as they are.
- This feature adds no limit, no maintenance rule and no category to that list (FR-022).
- 005 replaces the service function and the card, and removes `MAX_EXTRA_DONE`. `docs/developer/weekly-planning.md` has a section "Hand-over to feature 005" with this list.

## Open points for the project owner

- **O-1**: Should the park decision still clear the stale days of leftover tasks, as the old backlog choice did? The plan says no (research R-13).
- **O-2**: The Week view and the period reviews still show goals (feature 006 owns their removal). Should this feature hide them? The plan says no (research R-16).
- **O-3**: A dropped task is a task that the task app no longer lists (research R-07), because Vikunja has no "won't do" state. A task app with such a state can map it in its adapter later.

## Complexity Tracking

No violations. The three small tables are the simpler choice compared with more columns on `project_labels` or `weekly_plan_projects` (research R-01 and R-02). The focus seam is one class and one default.
