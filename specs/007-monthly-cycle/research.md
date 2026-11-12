# Research: Monthly Planning and Review

Decisions taken before design. Each has the choice, the reason and what was rejected. File names refer to the code as it is after features 003, 004 and 006 (and 005 where stated). Names from 004, 005 and 006 are taken from their design files. Task T001 re-checks every one of them against the merged code.

## R-01: Where the monthly focus lives

- **Decision**: Three new tables. `monthly_focuses` (one row per user and month), `monthly_focus_entries` (one row per theme in a focus, with the target, the date it starts to count and the date and reason it left) and `focus_changes` (append-only log of swap, add, remove and target changes). Entries point to `project_labels.id` (feature 003) and keep a copy of the name.
- **Reason**: The focus has its own life (targets, dates, history). Feature 004 reads it only through the `FocusProvider` seam, so no column on `weekly_plans` or `project_labels` is needed. A theme is a row of `project_labels`, and that row is never deleted, so an entry can outlive the project (orphans, FR-037).
- **Rejected**: One JSON column on a month row. It cannot be queried by theme, and a unique rule "one entry per theme and month" cannot be a constraint. Columns on `project_labels`. They mix month data into a table every feature reads.

## R-02: Entries are edited, changes are append-only

- **Decision**: An entry row is updated in place when a theme leaves (`left_on`, `left_reason` = `swapped_out` or `removed`) or when its target changes. Every such step also adds one `focus_changes` row with a `batch_id`. The log is never edited or deleted. An undo reverses the entry (clears `left_on`, or deletes an entry that the undone change added) and adds a new log row with `source = undo` and `undoes_batch_id`. A change counts as undone when a later row has its `batch_id` in `undoes_batch_id`.
- **Reason**: The same pattern as the label history of 003 and the plan history of 006. The review needs the current state fast and the history for the swap list (FR-013, FR-015).
- **Rejected**: Pure event sourcing (derive the entries from the log). Every reader would need a replay, and the weekly provider is on a hot path.

## R-03: "No target" and "zero" are different values

- **Decision**: `monthly_focus_entries.target` is a nullable integer with a check `target IS NULL OR target >= 0`. `domain/monthly.py::parse_target(raw)` returns `None` for `None` and for an empty or blank string, an `int` for a non-negative whole number or a string of digits, and raises `InvalidTarget` for a negative number, a decimal (also `3.0`), text and a boolean. The request schema accepts a loose type (`int | float | str | None`), so the refusal comes from this rule with the code `invalid_target` and a clear message, not from the framework default.
- **Reason**: FR-003 and scenarios 3 and 4 of user story 2. The two values must stay apart in storage, in the API (`null` against `0`), in the review ("no target" marker against `0 of 0`) and in the snapshot.
- **Rejected**: Store 0 for "none". It makes the "no target" marker impossible.

## R-04: The real `FocusProvider`

- **Decision**: `MonthlyFocusService.themes_for_month(db, user_id, month_start)` implements the protocol of 004 (`services/focus.py`, one method, returns `set[uuid.UUID] | None`). It returns `None` when the user has no `monthly_focuses` row for the month, so the weekly flow shows no highlight and no "outside focus" (004 FR-008). It returns the project ids of the entries that are still in the focus (`left_on IS NULL`) when a row exists, also an empty set (a saved empty focus is a real choice). Only `main.py` changes in the weekly code: it passes the real provider to `WeeklyService` instead of `NoFocus`. `NoFocus` stays in the code as the default of tests.
- **Reason**: FR-011 and the seam of 004 (its research R-14). A swapped-out theme is no longer the focus, so the weekly picker stops highlighting it, while its entry stays for the review.
- **Rejected**: Return `None` for a saved empty focus. It would hide the "outside focus" marker from a user who chose to focus on nothing. Return swapped-out themes too. The picker would highlight a theme that the user left.

## R-05: What counts toward a target

- **Decision**: A milestone counts when its state is `done` (004) and its `done_on` (a local date, stored by 004) lies in the month. It counts under its `done_theme_id` (the theme at done, stored by 004). For a focus entry the window is `counts_from` to `left_on` (both included), or to the end of the month for an entry that is still in the focus. A milestone done in the month under a focus theme before `counts_from` is listed as "earlier this month" and is not counted (FR-014). A milestone done in the month under a theme with no entry, or after the entry left, goes to the outside-focus list, with the entry "no theme" when `done_theme_id` is null (FR-018). Closed, parked, active milestones never count (FR-017). The first save of a month, also in a month in progress, sets `counts_from` to the first day of the month. A theme that is added by a change sets `counts_from` to the day of the change.
- **Reason**: One rule, in a pure function, so SC-003 can be proved on the demo set. The done rule and the two stored fields belong to 004 and are only read (cross-spec resolution 1).
- **Rejected**: Count by the month of the review (FR-017 forbids it). Count all milestones of a swapped-out theme for the whole month. It would count work done after the user had left the theme and would make "outside focus" depend on the swap.

## R-06: Snapshot storage and versions

- **Decision**: Two tables. `monthly_reviews` (one row per user and month, with `current_version`) and `monthly_review_snapshots` (one row per version: `review_id`, `version`, `payload` as JSON, `schema_version`, `created_at`, `values_written`). A snapshot row is never updated or deleted. Saving a reviewed month again adds version n + 1 and sets `current_version`. "Make an earlier version current" changes only `current_version` (and `current_changed_at`) on the header row. The payload is built by one pure function from already loaded facts and then frozen (shape in data-model.md). It holds names, targets, results, swaps, outside-focus milestones, category counts, the hidden count, key result values and the decisions. It holds no share and no percentage (FR-027).
- **Reason**: FR-029 to FR-032. JSON keeps the snapshot readable by 008 without joins to live tables, and no live table change can reach it. A header with a pointer keeps the snapshot rows immutable.
- **Rejected**: A relational copy of every figure (many tables, no gain, and a rename would still have to be avoided by copies of names). A flag `is_current` on the snapshot row. It makes the snapshot rows mutable.

## R-07: Key results in the review (read 006, write one thing)

- **Decision**: The review reads key results through the services of 006 in process: `AnnualPlanService.plan` reads the planning year of the month; `KeyResultService.all_links` provides active and ended link rows so links valid during the reviewed month can be selected; `KeyResultService.value_on` reads the series as of a date; and `KeyResultService.enter_value` is the same write path used by `POST /annual/key-results/{id}/values` for a manual value typed in the review. (`AnnualPlanService.plan` exposes currently active links only, so it is not sufficient by itself for a past month's link state.) Nothing calls a key result source. The values for the review are:
  - **start of month** = `value_on(first day of the month)`, else the start value of the key result (FR-021).
  - **latest** = the newest value of the series with its time stamp, or the start value with no time stamp when the series is empty.
  - **update status** = `updated` when the latest time stamp is on or after the first day of the month (in the user time zone), else `not_updated`.
  - **change** = latest minus start of month.
  A value typed by the user is written in the finish step, in the same transaction as the snapshot, with the date of today. A retired key result gets no prompt. A key result of a past planning year takes a value (006 rule). The write is skipped when the latest series value is already equal to the typed value and has the date of today (a retry does not add a row).
- **Reason**: FR-019 to FR-022, decision 6 of the cross-spec resolutions. The series is a dated fact, so a reopened review never removes a value (edge case of the spec).
- **Rejected**: Store the typed value only in the snapshot. 006 and 008 would not see it. Pull values from automatic sources. The spec forbids it and SC-010 needs the review to be fast.

## R-08: Category counts come from 005 through a small reader

- **Decision**: `services/monthly_review.py` defines `CategoryCountsReader` (one method `month_counts(db, user_id, month_start) -> CategoryCounts | None`) and the feature 007 pure value `CategoryCounts(goal_aligned, maintenance, off_plan, hidden)` in `domain/monthly.py`. The real reader is a thin adapter over feature 005's `StatisticsService.summary`, called for `PeriodType.MONTH` at `month_start`; it returns `Summary.counts` when statistics are available and the summary is non-empty, and `None` otherwise. This reuses the existing `tefteri.domain.work_categories.CategoryCounts` values without recalculating task categories. `main.py` wires the adapter. A fake reader serves the unit and integration tests. When no counts exist the reader returns `None` and the screen shows the empty state of the section. The review never reads tasks to count categories (FR-023, SC-005).
- **Reason**: 005 owns the numbers and their daily storage. A reader keeps 007 testable on its own and keeps the layer rule (services call services).
- **Rejected**: Count categories again in 007. It is forbidden and it would differ from the week and the year.

## R-09: The off-plan trend

- **Decision**: The share is `off_plan / (goal_aligned + maintenance + off_plan)` of one month and is computed on display and in the API, never stored. Hidden tasks are not in the base. The trend is `rising` when the share of the month is strictly higher than the share of each of the two calendar months before it, `not_rising` when it is not, and `not_enough_history` when one of the two months has no completed task or no 005 data (FR-024). A steady or high maintenance share gets no marker. The API returns the previous months with their shares so the screen can draw the comparison.
- **Reason**: FR-023, FR-024, assumption "may be tuned in the plan". Two plain calendar months are easy to explain and to test.
- **Rejected**: A moving average over more months. More to explain, and no data to tune it.

## R-10: Decisions and next month's suggestions

- **Decision**: A decision (`carry`, `drop`, `replace` with a named theme, `later`) is part of the draft and of the snapshot payload. The effect text comes from the pure function `decision_effect` so the screen and the API say the same thing (FR-025, FR-044). Suggestions for a month are computed on read from the newest current snapshot of an earlier month: `carry` gives the theme with its target (editable), `replace` gives the named theme with no target, `drop` and `later` give nothing. A suggested theme that is no longer eligible per 003 (orphaned, relabelled, ignored) is left out and listed under `skipped` with the reason (edge cases of the spec). The response says which month the suggestions come from (a skipped month, FR-010). Nothing is saved until the user saves the plan.
- **Reason**: FR-010, FR-025, FR-026, user story 8. A change of a decision after the review is stored is a new version (R-06), so the next plan always reads one fixed current version.
- **Rejected**: A separate mutable decisions table. It would let the decision drift from the snapshot that the annual review reads.

## R-11: The draft of the review is kept on the device, not stored

- **Decision**: The draft (typed key result values, decisions) is held in a Riverpod provider keyed by month, so leaving the screen inside the app does not lose it (edge case "user closes the review halfway"). The server stores nothing until the user finishes (FR-031). The server computes the draft figures on demand: `GET /monthly/{month}/review` for the live view, and `POST /monthly/{month}/review` with `dry_run` for the figures with the typed values and the effect of the decisions.
- **Reason**: The spec says nothing is stored until the user finishes. The dry run uses the same function as the real save, so the draft never shows a number that the snapshot would not hold.
- **Rejected**: A server-side draft table. It adds a record the spec does not allow and a cleanup job.

## R-12: The Month view is replaced, the data stays

- **Decision**: `MonthScreen` is rewritten (same file and route `/month`, same `period-label`, `today-button`, `next-period` keys, and the monthly checklist banner `PlanningChecklist` stays). It no longer calls `GET /views/month/{day}` and no longer uses `PeriodPage`. The backend route `/views/month/{day}` stays (006 removes only its `goals` field), because it is public API and other clients may call it. A month that has only old goal rows opens an "earlier format" read-only view that reads `GET /goals/history?period_type=month&period_start=` of 006. No snapshot is made from it (FR-035, FR-036). No migration touches `goals`.
- **Reason**: FR-033 to FR-036 and decision 1 of the decisions file.
- **Rejected**: Delete the `/views/month` route. It is an API break outside the scope of this feature.

## R-13: Month, time zone and state of a month

- **Decision**: The month in the API is `YYYY-MM`. The server turns it into the first day and the exclusive end with `domain/periods.py` (`period_start`, `period_end`). "Today" is the date of the user in the user time zone (the helpers of `domain/timeutil.py`). A month is `past`, `current` or `future` by comparing it with today. The first day and the end are local dates, so a milestone done at 00:30 on the first day counts in that month because 004 stores `done_on` as the local date. The planning year of a month is the year of its first day (so a December and the next January use two planning years, FR edge case).
- **Reason**: FR-038 and the time-zone edge case.
- **Rejected**: Month boundaries in UTC.

## R-14: Inline actions reuse existing routes

- **Decision**: "Label a project as theme" uses `GET /projects/classification` and `PUT /projects/labels` of 003. "Create a theme" uses `POST /annual/themes` of 006 (task app first, then the label, the shared rule of 003, FR-043). This feature adds no label route and no create route. The picker list itself is `GET /monthly/{month}/themes` (it needs the focus state, the last-month hint and the key results).
- **Reason**: One rule, one owner (003). 006 already allows the call in every planning year.
- **Rejected**: A second create route under `/monthly`. Two routes with one meaning invite drift.

## R-15: Orphaned, relabelled and ignored themes

- **Decision**: An entry keeps its place when its theme is orphaned or relabelled. The read marks it (`orphaned` with the reason, `label_changed` with the new label). Names come from `project_labels.name` (the last known title, which is the stored name for an orphan). The snapshot copies the name at review time. Such a theme is not offered in suggestions and not in the picker (003 eligibility). Counting reads the stored `done_theme_id` of milestones, so an orphan never breaks it (FR-037, SC-007).
- **Reason**: Edge cases of the spec and FR-037.

## R-16: Pure rules in `domain/monthly.py`

- **Decision**: All rules that tests must prove sit in one pure module with no database, adapter or task-app import: `parse_target`, `count_note`, `result_marker`, `month_state`, `classify_done` (counted, earlier, outside, no theme), `key_result_flags`, `key_result_status`, `off_plan_share`, `trend`, `decision_effect`, `build_suggestions`, `build_payload` and the frozen dataclasses of the payload. `tach` keeps `domain` free of imports from other layers.
- **Reason**: The same approach as `domain/classification.py` (003) and `domain/milestones.py` (004). Features 008 reuses the payload types.

## R-17: Performance and no source calls

- **Decision**: The review makes: one query for the done milestones of the month, one read of the plan of the planning year (006) with links, one series read per linked key result (at most nine per theme set in practice), one call of the 005 reader, and the focus rows. It never calls an adapter. A test with 500 completed tasks and a failing fake source checks SC-010.
- **Reason**: SC-010.

## R-18: The read contract for feature 008

- **Decision**: `MonthlyReviewService.current_snapshots(db, user_id, year)` returns, for every month of the year that has a review, the payload of the current version with `month`, `version` and `taken_at`. The route `GET /monthly/snapshots?year=YYYY` returns the same list. Neither recalculates anything (FR-032). Feature 008 calls the service in process.
- **Reason**: Cross-spec resolution 8 (008 reads snapshots only for totals).

## R-19: Which months can change

- **Decision**: Plan save (`PUT /monthly/{month}/focus`) works for a current or future month and is refused with `past_month` for a past month. Mid-month changes (`POST /monthly/{month}/changes`) work for the current month only (`not_current_month`). For a current month that already has a focus, a plan save may change targets only. A change of the members must go through a change so it is recorded (`use_changes`). Review and snapshot work for any month that is not in the future. A future month has no review and shows an empty result (edge case "plans a future month").
- **Reason**: Keeps the history honest (FR-013) without blocking the user: every refusal names the right action.

## R-20: Terms and hints

- **Decision**: New terms in `frontend/lib/features/projects/term_hint.dart` (first use only, dismissible, remembered per device): monthly focus, key result, work categories, outside focus, review snapshot. "Theme project" and "milestone project" already exist from 003 and 004. The hint "replace is a month-end decision, swap is a change during the month" is a fixed line next to the decision choices and next to the swap action (FR-025, scenario 6 of user story 8).
- **Reason**: FR-042 and the usability rules of the decisions file.
