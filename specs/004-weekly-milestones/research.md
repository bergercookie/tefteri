# Research: Weekly Planning and Review with Milestone Projects

Decisions taken before design. Each has the choice, the reason and what was rejected. File names refer to the code as it is after feature 003.

## R-01: Where milestone data lives

- **Decision**: A new table `milestones`, one row per milestone project, keyed on `project_labels.id` (unique). It holds the done-state, the state (`active`, `parked`, `closed`, `done`), the rollover count, the done date, the theme at done and the way it was done. A second table `milestone_rollovers` holds one row per rollover event. A third table `milestone_closures` holds the log of one close and return, for the undo. The row of a milestone is created the first time the weekly flow touches the project (get or create). A project with no row is a milestone in state `active` with rollover count 0 and no done-state.
- **Reason**: The label is owned by feature 003 (`db/models/project_label.py`), and a project can be labelled milestone long before it is committed. Lazy rows keep 003 data untouched and need no backfill. The row can outlive the container (`project_labels` is never deleted), so orphaned and finished milestones keep their history (FR-019, FR-032).
- **Rejected**: Columns on `project_labels`. It mixes planning data into a table that every feature reads, and it adds columns for themes, routines and ignored projects that never use them. Columns on `weekly_plan_projects`. The rollover count and the state belong to the milestone, not to one week.

## R-02: Evolve `WeeklyPlanProject` in place

- **Decision**: `weekly_plan_projects` stays the weekly commitment entry. Migration `0019_weekly_milestones` adds nullable columns: `milestone_id`, `theme_project_id`, `theme_name`, `decision`, `expected_rollover`, `decided_at`. The old columns stay and keep their meaning: `container_id`, `name`, `position`, `created_here`, `committed_task_ids`, `parked_task_ids`, `outcome`, `reviewed_committed`, `reviewed_done`, `leftover_action`. New reviews write `decision` and `outcome` and never write `leftover_action`.
- **Reason**: Decision 3 of `specs/planning-cycles/decisions.md` (evolve, do not rebuild). `outcome`, `reviewed_committed` and `reviewed_done` already feed the history page, so it works for old and new weeks without a second code path.
- **Rejected**: A new table `weekly_commitments`. It would need a copy of every old row and a second reader for the history page.

## R-03: The old choices are mapped on read, and old rows are not rewritten

- **Decision**: A pure function `decision_of(decision, leftover_action)` in `domain/milestones.py` returns the stored `decision`, or maps `carry` to `recommit` and `backlog` to `park`, or returns `None`. The API and the screens use only this function. The migration does not change a row (FR-031, user story 8, scenario 4).
- **Data migration plan for existing weekly rows**:
  1. `0019` adds the new columns as nullable and adds three new tables. It runs no `UPDATE`.
  2. A row with `leftover_action = 'carry'` shows as "Keep and recommit". A row with `leftover_action = 'backlog'` shows as "Keep but park". A row with `leftover_action IS NULL` has no decision (nothing was left over).
  3. A row with `milestone_id IS NULL` is a legacy project. The history and the look-back show its stored name, counts and `outcome`. Nothing creates a milestone for it, and nothing relabels the project.
  4. New plans fill `milestone_id` and `theme_*` when a milestone is added.
  5. Downgrade drops the new columns and tables. Old data is intact because it was never changed.
- **Check**: A migration test inserts old-style rows at revision `0018`, upgrades to `0019` and compares every old column. An integration test opens a plan with a carried project and a backlog project and checks the names (SC-008).
- **Rejected**: A backfill that rewrites `leftover_action` into `decision`. The spec forbids rewriting, and a rewrite cannot be undone.

## R-04: The cap is a warning computed on read

- **Decision**: `MAX_PROJECTS` becomes `MILESTONE_CAP = 3` in `services/weekly.py`. `add_project` and the create route never compare against it. `PlanOut` gains `milestone_count`, `milestone_cap` and `over_cap`. The client shows the warning when `over_cap` is true. Only rows with a `milestone_id` count (FR-005). Tasks and routine projects never count.
- **Reason**: FR-006 and SC-004. A computed flag cannot be out of date after a remove (scenario 2 of user story 4).
- **Rejected**: A setting for the cap. The spec says three.

## R-05: Which projects the picker offers

- **Decision**: A pure rule `commit_kind` in `domain/milestones.py`. It returns `milestone` when the effective label is milestone and the project is weekly-eligible (003). It returns `label_then_commit` when the project is unclassified, weekly-eligible and has no subprojects (a leaf). It returns `None` for every other project: a stored or proposed theme with children, maintenance, ignored, orphaned, and a project inside a routine. Choosing a `label_then_commit` project writes the label milestone (history source `user`) in the same request, then commits it. The picker shows these in an "Unsorted" group and says so before the user picks.
- **Reason**: FR-001, FR-033. Users who have not classified anything must still plan. The act of picking is the act of calling it a milestone, and 003 stores the history, so the label can be undone on the Projects screen. It also keeps most existing tests valid, because their projects are unclassified top-level leaf projects.
- **Rejected**: Refuse unclassified projects until the user opens the Projects screen. It breaks FR-033.

## R-06: Creating a milestone

- **Decision**: `WeeklyService.create_milestone` replaces `create_subproject`. It calls `ClassificationService.create_and_label(label=milestone, parent_id=theme)` (the shared rule of 003: task app first, then the record), then `MilestoneService.ensure` with the done-state, then adds the project to the plan. The route `POST /weekly/{day}/subprojects` is replaced by `POST /weekly/{day}/milestones` with `parent_id`, `name` and `done_state`. An empty or blank done-state is refused with the code `done_state_required` and a hint with an example, before any call to the task app.
- **Reason**: FR-009 to FR-011. One shared write rule.
- **Rejected**: Keep `/subprojects` next to the new route. Two routes with different meaning invite misuse. The Flutter client is the only caller and changes in the same feature.

## R-07: When a milestone is done (completion rule)

- **Decision**: Pure function `completion(tasks)` in `domain/milestones.py`. Input: one `TaskFacts(done, dropped, completed_on)` per task. A closed task is a task with `status = done`. A dropped task is a task that the task app no longer lists in the project (`sync_state = deleted_remotely`). The milestone is done when no task is open (not done and not dropped) and at least one task is closed. The done date is the latest `completed_on` of the closed tasks. A note says "remaining tasks were dropped" when any task is dropped.
- **When it runs**: `MilestoneService.settle` runs after a full connection sync (`SyncService.sync_connection`, where a deleted-remotely mark is final) and after `WeeklyService.refresh` and when a weekly state is read. In the last two cases a project that has a deleted-remotely task is skipped: a task that moved to another project looks deleted until the next full sync (see `SyncService.sync_projects`), and it must not make the milestone done by mistake.
- **Reason**: FR-017 and decision 1 of the cross-spec resolutions. Vikunja has no "won't do" state, so a task that is deleted is the only dropped signal that the task app gives.
- **Rejected**: Count a deleted task as closed. The rule needs one real completion.

## R-08: Done date and theme at done

- **Decision**: When a milestone becomes done, `settle` and `mark_done` store `done_on` (a local date in the time zone of the user) and the theme at that moment: `done_theme_id` (the `project_labels.id`) and `done_theme_name`. The date is the day of the last closed task for an automatic completion, and the day the user pressed the button for a manual one. The theme comes from `parent_theme` (003). `done_theme_name` is a copy, so the value stays right when the theme is renamed or removed. A later theme change never writes these fields.
- **Reason**: Cross-spec resolution 1. Features 007 and 008 read `done_on` and the theme at done.

## R-09: Rollover events and the nudge

- **Decision**: A rollover is created only when the review saves a `recommit` decision. The service adds one row to `milestone_rollovers` (with `expected` from the user), raises `milestones.rollover_count` by one, and adds the milestone to the plan of the next week. The nudge is computed on read by `needs_rescope(events)`: true when the two latest events are both unmarked. Nothing stores the nudge. Park, decide later and a commit without a decision never add an event.
- **Next plan already committed**: The review adds the milestone to the next week's plan even when that plan is committed, and the plan goes back to draft with a notice, so the user can pick tasks. The alternative of failing would trap the user in the review (FR-028).
- **Reason**: FR-019, FR-024, FR-029, FR-030 and the edge case about two weeks in a row without a review.

## R-10: Decide later

- **Decision**: A review answer without a decision, and an explicit `decide_later`, both store `decision = decide_later` and change nothing else on the milestone (FR-036). The picker computes the reminder: a milestone has an open decision when its newest weekly entry with a decision has `decision = decide_later`. A later real decision clears it. The review never rejects a missing answer, so a user can always finish (SC-013).
- **Reason**: One rule on the server, so the client "decide later for all of these" action is only a shortcut.

## R-11: Close and return tasks (the move capability)

- **Decision**: Add the optional capability `Capability.MOVE_TASKS` and the port operation `TaskBackend.move_task(remote_id, container, expected_version) -> RemoteTask`. The Vikunja adapter updates the task with the new `project_id`, reads it back and raises `NotSaved` when the task is not in the new project. The in-memory fake supports it behind the capability set. `report_for` and the capability responses gain the flag `move_tasks`.
- **Order of a close** (`services/milestone_close.py`): refuse when the milestone is not unfinished, has no usable parent theme, or the connection lacks `MOVE_TASKS`. With `dry_run` return the count and the theme name and stop. Otherwise create a `milestone_closures` row, move the open tasks one by one, and append each success (task, old project, version after the move) to the log. When every move worked, set the milestone state `closed` and stamp the closure. When a move fails, the milestone stays as it was, the answer lists the tasks that moved, and a second call skips the tasks that are already in the theme, so a retry is safe (FR-026).
- **When the move runs**: At the confirm button of the close dialog, through `POST /milestones/{id}/close`. The review then only records `decision = close` and checks that the milestone is closed. A failure never blocks the saving of the other decisions.
- **Hidden close**: A pure function `close_options(has_theme, theme_usable, can_move)` returns the reason code (`no_theme`, `theme_unusable`, `not_supported`) that the screen turns into one line (FR-027). A theme is usable when it is live and its effective label is theme and neither it nor an ancestor is ignored.
- **The project in the task app**: A close does not archive the project in the task app. It only empties it of open tasks. The old archive switch of the look-back stays as a separate, explicit action (`archive` in the answer), because archiving removes the project from tefteri lists and cannot be undone by the reopen.
- **Rejected**: Move all tasks in one call. Vikunja has no bulk move, and one-by-one gives the partial-failure report that FR-026 needs.

## R-12: Undo of a close (reopen)

- **Decision**: `POST /milestones/{id}/reopen` sets the state back to `active`. For a milestone that was closed by close and return, it moves each task of the newest closure back to the project it came from, but only when the task is still in the theme and its version equals the version that tefteri stored after the move (`expected_version` of `move_task`). A task that changed, moved again or was removed is listed as "could not be moved back" and never blocks the reopen (FR-037). The same route reopens a milestone that the user marked done by hand: state `active`, `done_on` and the theme at done are cleared, and nothing else is touched.
- **Reason**: The version check is the existing conflict mechanism of the adapters (`RemoteConflict`). A task that the user edited is "changed since".

## R-13: Park, and the word "parked"

- **Decision**: The park decision sets the milestone state `parked` and nothing else. It does not clear the old days of the leftover tasks. The old backlog choice did clear them (`TaskService.unschedule`), so the existing test that expects a cleared due date changes. The word "parked" now means only the milestone state (glossary). The existing task-level action "Park for later" (`parked_task_ids`) is shown to the user as "Not this week", and the section "Parked" becomes "Not this week". The column and the API field keep their names.
- **Reason**: FR-025 and the glossary rule that tasks that were not picked are "not committed this week". Writing to due dates on a park would be a write the user did not see (FR-041).
- **Open question for the project owner**: Should a park still clear the stale days of leftover tasks, as the backlog did? The plan assumes no.

## R-14: Monthly focus is a seam, not a feature

- **Decision**: `services/focus.py` defines `FocusProvider` (one method `themes_for_month(db, user_id, month_start) -> set[uuid.UUID] | None`) and `NoFocus`, which returns `None`. `WeeklyService` takes the provider as a constructor argument (dependency injection). `None` means that no focus data exists: no highlight, no "outside focus", no focus share (FR-008, SC-010). Feature 007 supplies a real provider and changes only `main.py`. "Outside focus" is computed in the API layer from the provider, never stored (FR-007). The month of a week is `month_of_week(week_start)`, the first day of the month of the Monday (FR-038).
- **Reason**: Constitution IV spirit (no dependency on a feature that does not exist) and decision 3 of the analysis.

## R-15: Review summary and the hand-over to feature 005

- **Decision**: `LookBack` gains a summary computed from the stored week: committed tasks and done tasks, milestones committed and finished, pace (completions of committed tasks per local day) and focus share (`None` without focus data or without completed tasks). When nothing was committed the ratios are `None` and the screen shows a short note (FR-020). `done_outside_plan` stays exactly as it is, including `MAX_EXTRA_DONE`. Feature 005 later replaces it with the weekly list. 005 must change `WeeklyService.done_outside_plan`, `ExtraDoneOut` and the card in `week_progress_card.dart`, and must remove `MAX_EXTRA_DONE` from this feature. This is written in `docs/developer/weekly-planning.md` as a hand-over note.
- **Reason**: The 005 list does not exist yet (decision: it is not built). Spec FR-022 forbids defining its limit here.

## R-16: Goals and the weekly flow

- **Decision**: The weekly flow in `backend/src/tefteri/services/weekly.py` and `frontend/lib/features/weekly/` has no goal step or goal field today. FR-015 is met by a guard test: the weekly state, the look-back and the history carry no goal field, and the planning screen shows no goal text. The goals shown in the Week view (`frontend/lib/features/week/week_screen.dart`) and the goal-based period reviews (`frontend/lib/features/review/`, `services/reviews.py`) are removed or hidden by feature 006, which owns "goal removal from week and month flows" (decision 9). This feature does not touch them. Stored goal rows stay as they are.
- **Risk**: If the project owner wants the Week view goals hidden in this feature, a task of M5 grows by one file. The plan lists it as the open point O-2.

## R-17: A plan with zero milestones is valid

- **Decision**: `WeeklyService.commit` no longer raises "Choose at least one project". The commit stores empty task lists. The existing test and the client rule that blocks a commit without a planned task change (FR user story 1, scenario 7; edge case "A plan with zero milestones").

## R-18: API shape and errors

- **Decision**: Keep every existing weekly route except `/subprojects` (replaced). Add `GET /weekly/{day}/themes`, `POST /weekly/{day}/projects/{plan_project_id}/tasks` (add a task under a committed milestone) and a new router `milestones` (`GET`, `PATCH`, `POST done`, `POST close`, `POST reopen`). `Invalid` gets an optional `code` (default `invalid`) so that the API can answer 422 with `done_state_required`, `not_a_milestone`, `not_eligible`, `no_theme` and `confirm_required` without a new exception class. The OpenAPI snapshot is regenerated.
- **Reason**: Smallest change that gives the client stable codes (003 used the same error model).

## R-19: Adding a task inline

- **Decision**: The weekly service gets `add_task(plan_project_id, title)`, which uses the existing `TaskService.create` for the container of the plan row (capability `CREATE_TASKS` is already required by 003). The new task is not committed until the user gives it a day, as today.
- **Reason**: FR-012 asks for new tasks under the milestone from the menu. Today the user must open the task app.

## R-20: Screens for real users

- **Decision**:
  - The existing four-step session stays: Look back, Choose milestones, Give tasks a day, Check and commit. Step 1 becomes the review with decisions. Step 2 becomes the picker.
  - The picker lists themes as headers, each with its milestones, a highlighted focus group on top when focus data exists, a "No theme" group and an "Unsorted" group. A theme without milestones shows "Create a milestone" inline. An empty picker explains theme and milestone in two sentences and offers "Label a project as theme" (opens `/projects`) and "Create a theme" (existing `createTheme`).
  - The cap warning is a quiet notice under the chosen list, in words ("You chose 4 milestones. Three is usually what fits in a week. You can still commit."), never a dialog.
  - The review shows, for each unfinished milestone, its done-state, its numbers and four choice tiles with one sentence each. A finished milestone shows as done with its date. The footer names milestones without a choice and offers "Decide later for all of these".
  - The close dialog shows "N open tasks will move to <theme>", says that the move can be undone, and has a confirm button. A hidden close shows one line with the reason.
  - Terms are explained once at first use with the existing `TermHint` (`frontend/lib/features/projects/term_hint.dart`): theme, milestone, done-state, committed, parked, rollover, outside focus.
  - Theme tokens only (`context.tefteri`, `Space`, `Corner`), `EmptyState`, `Loading`. No Material defaults.
- **Reason**: The 003 walkthrough showed that a first-time user needs the next step in the screen, not in the guide.

## R-21: Test strategy

- **Decision**: Unit tests for every pure rule. Integration tests with the in-memory fakes for the picker, create, cap, completion, decisions, close and reopen, summary and legacy plans. A shared adapter contract test for `move_task` (runs on the in-memory fake, the Vikunja HTTP fake and the live Vikunja). A migration test for `0019` with old rows. API end-to-end tests. Frontend widget tests with the weekly fake. Screenshot tests for the docs. A Playwright walkthrough against a seeded live Vikunja for the whole weekly loop, two weeks in a row.
- **Existing tests that must change** are listed in [plan.md](plan.md#existing-tests-that-must-change).
