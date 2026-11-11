# Research: Project Classification and Onboarding

Decisions taken before design. Each has the choice, the reason and what was rejected.

## R-01: Where a label lives

- **Decision**: A new table `project_labels`, one row per (connection, project identity), plus an append-only `project_label_history` table. Rows are keyed on `connection_id` and `remote_id`, never on the name.
- **Reason**: `SourceContainer` rows are deleted when a project leaves the task app (`SyncService._sync_containers`, `ProjectService.archive`), and about 15 queries read that table and assume it lists only live projects. A separate table can outlive the container, so orphaned projects keep their label and name without touching those queries.
- **Rejected**: Add `label` and `orphaned_*` columns to `source_containers` and stop deleting rows. It would force every reader (planner, weekly, tasks, calendar, lookups) to filter orphans and risks wrong data on screens that were not changed.

## R-02: Orphaned is a state, not a delete

- **Decision**: A sync marks a `project_labels` row orphaned with the reason `missing` when its project is no longer listed. The task app can list a project again later, and then the mark is cleared. A project that Tefteri archives is marked orphaned with the reason `archived`. The `SourceContainer` row is still removed as today, which keeps all existing screens unchanged.
- **Reason**: FR-010 to FR-012. Plans keep the stored name already (`WeeklyPlanProject.name`), so screens that show a past plan do not need the container.
- **Check**: A test removes a project that a plan and a task refer to, syncs, and loads every screen that shows projects (SC-004).

## R-03: Proposal rule

- **Decision**: A pure function in the domain layer: a project in a past weekly plan is proposed as milestone; otherwise a top-level project is proposed as theme and a deeper one as milestone. It returns the label and a reason code (`was_committed`, `top_level`, `nested`). The proposal is computed on read and never stored until the user saves.
- **Reason**: FR-004 and the "guess, then confirm" principle. A pure function is easy to test and easy to change.
- **Rejected**: Signals based on age or on the number of children. The task app does not give a reliable age, and the spec makes them optional.

## R-04: Capabilities

- **Decision**: Extend `Capability` with `RENAME_PROJECTS`, `RESTORE_PROJECTS`, `PROJECT_TREE`, `STABLE_PROJECT_IDS`, `CREATE_TASKS` and `COMPLETION_TIMES`. Add `REQUIRED_TASK_CAPABILITIES` (`SUBPROJECTS`, `ARCHIVE_PROJECTS`, `PROJECT_TREE`, `STABLE_PROJECT_IDS`, `CREATE_TASKS`, `COMPLETION_TIMES`). `ConnectionService.check` and the create path refuse a task connector that lacks one and name it. `MOVE_TASKS` is added by feature 004 when the move is built.
- **Reason**: FR-015, FR-016. Stable identity and full tree reading cannot be tested in a generic way, so each adapter declares them and a shared contract test proves the declaration by calling the operations.
- **Rejected**: Probe the live task app at connect time. It needs a second write path and leaves test data in the user's account.

## R-05: Rename and restore in the Vikunja adapter

- **Decision**: Add `rename_container(container, name)` and `restore_container(container)` to the `TaskBackend` port. Vikunja: `POST /projects/{id}` with the title (or `is_archived=false`), then read the project back and raise `NotSaved` if the value did not stick, as `archive_container` does today.
- **Reason**: FR-013 and FR-027 need a write-first rule. The read-back is the existing pattern in this adapter.

## R-06: Id used by the API and the client

- **Decision**: The public id of a project is the `project_labels.id` UUID. It exists for orphaned projects too. Operations that need the live project look up the `SourceContainer` by connection and `remote_id`.
- **Reason**: One stable id for the tree, the history and the undo. The existing `source_containers.id` is not stable (the row is removed with the project).

## R-07: Undo

- **Decision**: Every label change that the user saves gets a `batch_id` stored on its history rows. `POST /projects/labels/undo` with a batch id adds new history entries that restore the earlier labels, and never edits old rows. Undo of an archive calls `restore_container` first and clears the orphaned mark only after it works.
- **Reason**: FR-022, FR-023, FR-027. History stays append-only.

## R-08: Preview before a bulk change

- **Decision**: `PUT /projects/labels` accepts `dry_run=true` and then returns the effect (counts of changed projects by old and new label, and how many are in a committed plan) and writes nothing.
- **Reason**: FR-023. One code path computes the preview and the change, so they cannot disagree.

## R-09: Screen design for real users

- **Decision**:
  - One screen, `Projects`, reached from the navigation and from three entry points: a card after the first sync of a task connection, the empty weekly picker, and the unsorted reminder.
  - The tree starts with the proposals filled in and clearly shown as suggestions. One button, "Accept suggestions", saves them all. Changing one project is one tap on a label chip.
  - Groups: Unsorted first, then Themes, Routines, Ignored, and a collapsed "No longer in your task app" group. Each group has a one-sentence explanation. Search and collapse work for large trees.
  - Terms: the user-facing word for maintenance is "Routine" with the hint "work that repeats and never finishes". The data and the docs keep "maintenance" as the spec says, and the screen shows "Routine (maintenance)" in the first-use hint.
  - Errors say what happened and what to do. Undo is a snackbar action for 10 seconds and stays available from the history of the screen.
- **Reason**: The user asked for intuitive and usable. FR-025 to FR-027.

## R-10: Test strategy

- **Decision**: Unit tests for the proposal and eligibility functions. Integration tests with the in-memory fakes for sync reconcile, orphan, archive, restore, rename and the weekly picker. A shared adapter contract test for the new port operations (runs on the Vikunja fake HTTP and on the live Vikunja). Migration test for 0018. Frontend widget tests with `fake_api.dart`. Screenshot tests for the docs. A Playwright walkthrough of the built web app against a seeded live Vikunja for the first-time flow.
- **Reason**: Constitution V and the user's request for real-user usability.
