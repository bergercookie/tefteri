# Research: Work Categories and Statistics

Decisions taken before design. Each has the choice, the reason and what was rejected. Words follow the glossary of `specs/planning-cycles/decisions.md`. The names of the label and weekly entities come from the design files of features 003, 004 and 006.

## R-01: Where the category of a task lives

- **Decision**: A new table `task_categories`, one row per task (unique `task_id`). It holds the category, a reason code, the "unsorted" flag, the local completion day and a copy of the project name. Migration `0021_work_categories`.
- **Reason**: The sync overwrites `tasks` rows when the task app changes a version (`_upsert` in `services/sync.py`), so a column on `tasks` would be lost or recomputed by accident. A row in its own table is written once by the recorder and never touched by the sync. FR-007 says the category is stored and never recomputed.
- **Rejected**: Columns `category` and `completed_on` on `tasks`. The sync writes `values` into that row, so a future change to `task_values` could reset them. It also makes "never recomputed" depend on a convention instead of a table.

## R-02: When "first seen as completed" happens

- **Decision**: One function, `CategoryRecorder.record(...)`, called in two places. (1) After `SyncService._sync_tasks` for every task that is done, has a completion time and has no row, or has a row for an older completion time. (2) In `TaskService.complete` after the task app confirmed the completion, so a task finished in Tefteri is categorised at once with the project that tefteri knows. The recorder works in batches of 500 tasks and flushes after each batch.
- **Reason**: FR-007 (first sight) and the weekly page, which must show the new task without waiting for the next sync. One function means one rule.
- **Rejected**: Compute on read and cache. That is "recompute", which the owner removed on 2026-11-11.

## R-03: Which project decides when the task moved

- **Decision**: The project of the task at the last sync that saw it open, when the same sync now sees it done. If the cache never saw the task open (the task is new, or it was done before Tefteri first synced), the project the task has now. A task completed in Tefteri uses the cached project. `_sync_tasks` takes a snapshot `{task: container_id}` of the open tasks before the upserts and gives it to the recorder.
- **Reason**: The spec assumption says: if the task app cannot say where the task was at completion, use the project that Tefteri last saw before completion. The first adapter does not say. A move after a sync that saw the task done never changes the row (FR-006). A move and a completion between two syncs cannot be ordered, so the last project seen is the stable answer.
- **Rejected**: Always use the current project. A task moved right after completion would then change the number of a past week.

## R-04: The label on the completion day

- **Decision**: A pure function `label_on(history, day)` over the entries of `project_label_history` of feature 003: the entry with the latest `from_at` not after the end of the local completion day; if all entries start later, the oldest entry (FR in 003, spec 005 US5 scenario 10); no entries means unclassified. The labels of the ancestors are read the same way from their own history. The parent links are the last known ones (`project_labels.parent_remote_id`), because 003 keeps no history of moves.
- **Reason**: Reuses what 003 stores. A tree with the labels of one day is built in memory once per batch and day, so 20,000 tasks do not make 20,000 queries.
- **Rejected**: The current label (it breaks FR-007 for a backfill and for late first sight). A history of parent links (a new table for a rare case; see the open points of the plan).

## R-05: The weekly commitment

- **Decision**: A small seam `CommitmentProvider` in `services/commitments.py` with one method `committed_projects(db, user_id, week_start) -> set[uuid.UUID] | None`. The real provider returns the ids of `project_labels` for the projects of the plan of that Monday when the plan status is `committed`. It reads `weekly_plan_projects.milestone_id` (feature 004, through `milestones.project_id`) and, for an entry without a milestone, the `container_id` mapped to `project_labels` by connection and remote id. `None` means "no weekly commitment feature": the recorder records nothing and the API says `available: false` (FR-026). A draft plan commits nothing. A milestone that was parked, closed or done during the week is still in the set (spec edge case).
- **Reason**: FR-002 and FR-026. A seam lets a unit test prove that 005 never guesses without 004, in the same way 004 uses `FocusProvider`. The task ids of the commitment are not used: a task in a committed project is goal-aligned even when it was not committed (US1 scenario 5).
- **Rejected**: Read the old `WeeklyPlanProject.container_id` only. It is null for an orphaned project, and the spec wants orphaned committed milestones to stay goal-aligned.

## R-06: The order of the rules

- **Decision**: The first rule that fits wins.
  1. No label rows at all for the project, or no project: off-plan, `unsorted`, reason `no_project`.
  2. The project or any ancestor has the label `ignored` on the day: hidden (reasons `ignored`, `ignored_ancestor`).
  3. The project or any ancestor has the label `maintenance`: maintenance (reasons `maintenance_label`, `inside_routine`). This is decision 10 of the planning decisions and FR-029.
  4. The label is `milestone` and the project is in the weekly commitment of the completion week: goal-aligned (reason `committed_milestone`).
  5. The label is `milestone` (not committed): off-plan, reason `milestone_not_committed`.
  6. The label is `theme`: off-plan, reason `theme`.
  7. No label (unclassified): off-plan, `unsorted`, reason `unclassified`.
- **Reason**: FR-001 to FR-008 and FR-029. Ignored is first because the user chose to hide that work; FR-029 says "whatever the label of its own project is", and an explicit "ignored" on the project or an ancestor is the stronger statement. This needs a yes from the owner (open point 2 in the plan).
- **Rejected**: Maintenance before ignored. A project that the user hides would then show in the statistics.

## R-07: Day counts are derived, not kept in a second table

- **Decision**: The count per category and per day (FR-025) is the result of one grouped query over `task_categories` joined with `tasks` (status done, the same completion time, not deleted remotely), on the index (`user_id`, `completed_on`, `category`). Month and year numbers are the sum of the day numbers, built in Python from the same query, so they cannot disagree (FR-009).
- **Reason**: A table of daily counts is a second copy that can drift from the rows (a deleted task, a reopened task). With 20,000 rows one grouped query takes a few milliseconds on SQLite. Feature 007 calls the service method `daily_counts(start, end)` and stores the numbers in its snapshot.
- **Rejected**: A table `daily_category_counts` updated by the recorder. It needs a repair path for reopen and delete. Listed as an open point for the owner, because FR-025 can be read as "a stored row per day".

## R-08: Reopened tasks

- **Decision**: One row per task. A row counts only when the task is done and `task_categories.completed_at` equals `tasks.completed_at`. When a reopened task is completed again, the recorder sees a different completion time and replaces the row in place (new category, new day, new `decided_at`). While the task is open, its row stays but does not count.
- **Reason**: Spec edge case: only the latest completion counts, once. The unique `task_id` makes "counted twice" impossible.
- **Rejected**: Keep a row per completion. It is the history of reopens, which nobody asked for, and it makes every count need a "latest" filter.

## R-09: Periods and time zones

- **Decision**: `completed_on` is the local date of the completion time in the time zone of the user at the moment of first sight, and it is stored. Week is Monday to Sunday and is the sum of 7 days. A month is the sum of the days with that month. A year is the sum of its 12 months. A change of the time zone later does not move a task (consistent with "never recomputed"). Period ranges use `domain/periods.py`.
- **Reason**: FR-009, FR-010 and the edge case at the week boundary. A stored day makes the sum rule exact.
- **Rejected**: Convert `completed_at` to the current time zone at read time. A user who moves to another time zone would change old weeks.

## R-10: Paging

- **Decision**: Keyset paging with an opaque cursor (base64 of the sort key and the task id). Two orders: `newest` (completion time, then id, descending) for the week list and `project` (project name case-folded, then completion time descending, then id) for the drill-down. Page size 1 to 200, default 50. There is no cap on the number of pages. The count of the filter (`total`) comes from a separate `COUNT`.
- **Reason**: FR-012 and SC-004: no task lost or repeated even when a task is completed while the user pages. Offset paging would shift.
- **Rejected**: Offset and limit. A new completion between two pages shifts every later row.

## R-11: Percentages and the bar

- **Decision**: A pure function `percentages(counts)` in the domain: the largest remainder method, ties broken in the fixed order goal-aligned, maintenance, off-plan, so the three numbers add up to 100; all zero for a total of zero. The server returns them with the counts for display only and stores nothing. The client draws segments with a minimum width of 6 logical pixels for any count above zero, so 1 task in 100 stays visible (US3 scenario 2). The count is always printed next to the percentage.
- **Reason**: FR-018 and US3. One implementation avoids rounding differences between clients.

## R-12: Cadence and burndown move to the server

- **Decision**: The arithmetic of `frontend/lib/features/weekly/week_progress.dart` (done per day, cadence, needed per day, remaining by day, ideal line) is ported to `backend/src/tefteri/domain/week_progress.py` and returned as the `progress` block of the week statistics. The Dart class keeps only drawing and a `fromJson`. The old Dart cases become Python unit tests.
- **Reason**: The assumptions of the spec say the client-only cadence and category calculations move to the server and the client shows the server's numbers. The chart stays.
- **Rejected**: Leave the cadence in Dart and move only the categories. FR-011 only names categories, so this is an open point (plan, point 4).

## R-13: Visual language

- **Decision**: Three styles built from existing tokens, never by colour alone. Goal-aligned: filled with `colorScheme.primary`, check icon, label in the main text style. Maintenance: filled with `context.tefteri.rule` and a diagonal hatch, repeat icon, muted text. Off-plan: transparent fill, 2 px outline in `context.tefteri.task`, compass icon. Each segment of the bar and each count tile uses the same style, the name and the number as text, so a greyscale screenshot still tells them apart (SC-007). One widget `CategoryStyle` owns the mapping.
- **Reason**: FR-015 and the design rules of `AGENTS.md` (tokens, no hard-coded colour).
- **Rejected**: New palette entries. The existing tokens already have the needed contrast pairs in light and dark.

## R-14: What replaces `done_outside_plan`

- **Decision**: Remove `done_outside_plan`, `ExtraDoneOut`, `ExtraDone`, `MAX_EXTRA_DONE` and `WeeklyService.done_outside_plan`. The week page reads `GET /statistics/week` (counts, days, progress) and `GET /statistics/tasks` (paged list). The month and year screens get a new card on top and keep their existing sections: the `PeriodView` of `/views/month` and `/views/year` (goals and tasks due in the period) is not touched, because feature 006 owns the goal parts and the due list is planned work, not completed work.
- **Reason**: FR-011, FR-012 and the hand-over written in the plan of feature 004.
- **Rejected**: Keep the old field next to the new one. Two sources would show two numbers.

## R-15: First run after the upgrade (backfill)

- **Decision**: No data is written by the migration. The first sync after the upgrade finds every completed task without a row and records it in batches, with the label history and the commitment rows that exist then. After that no row changes. The result is the same as if Tefteri had seen each task when it was completed, except for commitments edited before the upgrade.
- **Reason**: A migration must stay fast and must not read labels or commitments. It also needs no special code path.
- **Rejected**: A data migration with SQL. It would copy the rules into SQL.

## R-16: Hidden tasks

- **Decision**: The hidden count is returned with every summary and shown as one quiet line ("N tasks in ignored projects are not counted"). The line opens the same drill-down list with `category=hidden`.
- **Reason**: FR-008: no work disappears without a trace.

## R-17: Errors and schema safety

- **Decision**: The response models use the enum classes `WorkCategory` and `CategoryReason` as field types, not a hand-written `Literal`. A unit test builds one response for every member of both enums and validates it. The smoke test of the real server reads every endpoint with a task of every category and every reason.
- **Reason**: A response `Literal` that missed a new value crashed the real API once (feature 003) and the unit tests had not caught it.

## R-18: Test strategy

- **Decision**: Unit tests for the pure rules (categorise, label on a day, percentages, week progress). Integration tests with the in-memory fakes for recording, the hooks, sums, paging, time zones and orphans. E2E tests over the ASGI client for the routes and privacy. A performance test (1,000 tasks in a week, 20,000 in a year). A migration test for 0021 with old rows. Widget tests with `fake_api.dart`. Screenshot tests for the docs. A smoke test of the real server over HTTP against a live task app. A Playwright walkthrough of the built web client against a seeded live task app.
- **Reason**: Constitution V and the lesson of R-17.
