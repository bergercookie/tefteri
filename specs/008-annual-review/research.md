# Research: Annual Review

Decisions taken before design. Each has the choice, the reason and what was rejected. Names of things that other features own are copied from their design files (003, 004, 005, 006, 007). Where a name may still change while those features are built, task T017 says "read the code" and records the real names in the "Names" note at the end of this file.

## R-01: The review reads stored snapshots through one reader

- **Decision**: `AnnualReviewService` gets the twelve monthly snapshots from `MonthlyReviewService.current_snapshots(db, user_id, year)` of feature 007, in process, through a small protocol `SnapshotReader` in `services/annual_review.py`. The real reader is a thin adapter over the 007 service, wired in `main.py`. A fake reader serves the unit and integration tests, so the review can be tested with any snapshot shape. The reader returns the current version of each month, oldest month first, and nothing else (FR-026).
- **Reason**: FR-001, FR-014 and FR-026. 007 owns the snapshot rules and the versions. A protocol keeps the review testable without 007 internals, and it is the same pattern as `CategoryCountsReader` in 007 (R-08 there).
- **Rejected**: Call `GET /monthly/snapshots` over HTTP (007 says the route is for clients and that 008 calls the service). Read `monthly_review_snapshots` rows directly (it would repeat the "current version" rule of 007).

## R-02: A tolerant reader of the snapshot payload

- **Decision**: A pure function `read_snapshot(payload) -> SnapshotView` in `domain/snapshot_view.py` turns the JSON payload into typed values. Every field is optional. A missing field gives `None` and the screen says "not stored" (FR-016). Unknown extra keys are ignored. A `schema_version` that the function does not know is read as far as its keys allow. The month of a snapshot is the `month` field of the payload, never the time stamp `taken_at` (edge case about time zones).
- **Reason**: FR-016 and the edge cases "snapshots in an older shape" and "daylight-saving and time-zone changes". The annual review lives for years, so it must survive a later change of the payload (007 raises `schema_version` then).
- **Rejected**: Pydantic models with required fields. An old snapshot would fail to load, and the page would fail. Migrating old snapshots (snapshots are immutable, FR-014).

## R-03: The hit rule has one owner, the "reached by deadline" line reads the same series

- **Decision**: "Hit" reuses `domain/key_results.py::is_met(value, start, target)` of feature 006 (R-11 there). The review only decides which value to give it: the **last value in the year**, which is the `latest_value` of the newest snapshot of the year whose entry for the key result has a `latest_at` (a key result with no time stamp has no stored value: the start value is not a value, edge case "no snapshot value in any month"). The target is the target at the end of the year, read from the 006 plan (the target is edited in place and the change is in `plan_changes`). "Reached by deadline" gives `is_met` the **last value stored on or before the deadline**: the `latest_value` of the newest snapshot whose `latest_at` is not after the end of the deadline day in the user time zone. It is `open` when the deadline is not over at the end of the stored data (deadline after the end of the year, or in the future for the year in progress), and `no_value` when no value was stored on or before the deadline. It never changes the hit or missed result (FR-025).
- **Reason**: FR-003, FR-025, decision 8 of the cross-spec resolutions. One rule for "met" avoids two answers in two screens. The 006 series has more values than the snapshots hold, but the review reads snapshots only (FR-001), so its precision is one value per month. The docs say so (open point 1 of the plan).
- **Rejected**: Call `KeyResultService.value_on(deadline)` live. It is more precise but it is a recomputation from the live series, and a value entered after the year would change the past. Other hit rules (peak, any month): out of scope in the spec.

## R-04: Theme contribution counts milestones by date, inside the link range

- **Decision**: A link of 006 (`key_result_themes`: `project_id`, `started_at`, `ended_at`) gives a date range in the user time zone. For each key result and each of its links, the review counts the milestones that the snapshots list for that theme (`themes[].milestones`, plus `outside_focus` entries whose `theme_project_id` is the theme, shown as "shipped outside the focus") with a `done_on` inside the range. A link that was ended and replaced gives two ranges and two entries. The year total of milestones shipped is the number of distinct `milestone_id` over all snapshots of the year, so a theme linked to two key results is counted once (FR-006, scenario 2 of user story 2). A month with no snapshot adds nothing and is shown as missing.
- **Reason**: FR-005, FR-006 and user story 5, scenario 3. A date range is exact for a partial month, and it does not need a rule for "part of a month". The snapshot lists the milestones with their done dates (007 data model), so no task is read.
- **Rejected**: Count whole months in which a link was active. It is simple but it counts a milestone that was done before the link started. Read the milestones table of 004 live: forbidden (FR-001).

## R-05: "Differ strongly" and the movement of a key result

- **Decision**: The movement of a key result for a link is `last_value - first_base`, where `last_value` is the `latest_value` of the last snapshot month inside the link range and `first_base` is the `base_value` (value at the start of the month) of the first snapshot month inside the range. The fraction is `movement / (target - start_value)` with the sign of the direction, so a move away from the target is negative. The hint `much_shipped_little_movement` is shown when the milestones counted by the snapshots for the theme in the range (`themes[].done`, the focus window of 007) are **at or above the sum of the theme targets of the covered months**, the sum is at least 1, at least one milestone shipped, and the fraction is **below 0.25** (FR-007). The hint `movement_not_from_theme` is shown when the theme shipped no milestone and the fraction is **0.25 or more** (scenario 4 of user story 2). No hint when the span is zero, when no covered month has a theme target, or when a covered month has no key result value. The wording of both hints states two numbers and no cause.
- **Reason**: FR-007 and decision 8 give the first rule. The second rule is a mirror of the first with the same threshold, so one number (25%) explains both. The target sum needs a month by month sum because the target is per month in 007.
- **Rejected**: A separate threshold for "moved a lot". It would be a second magic number without a decision. A hint when the target is 0 and nothing shipped (0 of 0 would say "much shipped"): excluded by the rule "at least one milestone shipped".
- **Needs confirmation**: the sum of monthly targets, the "at least 1" guard and the symmetric 25% (see the summary of this feature).

## R-06: Year split sums stored counts

- **Decision**: The year split is the sum of `categories` of the snapshots that hold them, with the `hidden` count as its own part. A month row holds its own counts. Percentages come from `percentages(counts)` of `domain/work_categories.py` (005, largest remainder method, always 100 or all zero). Nothing is stored. A snapshot with no `categories` key counts as a month with "not stored" counts and is not part of the covered months of the split (the split can cover fewer months than the review). Every total says how many months it covers (FR-008, FR-010).
- **Reason**: FR-008, decision 5 of the cross-spec resolutions (month totals are sums of days, year totals sums of months). Reusing `percentages` keeps the bar equal in the week, month and year.
- **Rejected**: Read `GET /statistics?period=year` for the bar. It reads the live rows, so it would be a recomputation and it would change when a task changes (SC-008).

## R-07: The drill-down reuses the statistics route of feature 005

- **Decision**: The review adds no route for the drill-down. The client calls `GET /statistics/tasks?period=year&day=<year>-01-01&category=<category>` of feature 005 (paged by cursor) and labels the sheet "Live list, may differ from the bar". The response of the review carries a `drill_down` object with the fixed query so the client does not build it. The numbers of the bar never change when the drill-down loads (SC-008).
- **Reason**: FR-009. 005 owns the list and its paging. One more route would repeat it.
- **Rejected**: A review specific task list. It would repeat the paging and the category rules.

## R-08: Notes are the one stored thing: a table with one note per scope, undo by writing the text again

- **Decision**: A table `review_notes` with one row per (user, year, scope). The scope is the year (`goal_id` null) or one goal (`goal_id` set). `PUT /annual-review/{year}/notes` creates or replaces the note (upsert). `DELETE` removes the row and answers with the deleted note, so the client can show what is lost and offer undo for 8 seconds by calling `PUT` with the same text (FR-017, FR-027). Two partial unique indexes keep one year note and one note per goal. The text is 1 to 2000 characters after trimming. Notes can be written for a past or the current year, not for a future year (`future_year`). A note is private to the user (FR-022). The goal must be an annual goal of the user and of that year.
- **Reason**: The spec asks for "a short written note" for the year and for a goal, shown again on the next visit, with delete and undo. One note per scope is the smallest model and needs no list UI. Undo by re-writing needs no soft delete, no cleanup job and no new column.
- **Rejected**: Many notes for each goal (a list UI, ordering and paging for no requirement). Soft delete with a `deleted_at` column (more states, a purge). Store notes in the snapshot (snapshots are immutable).
- **Needs confirmation**: one note per scope instead of a list.

## R-09: The count of unmet key results comes from feature 006, not from the snapshots

- **Decision**: The review calls `AnnualPlanService.suggestions(year + 1, from_year=year)` of feature 006 in process and reports the number of key results it offers as unmet, the number of links it offers, and `has_plan`. The review does not apply the rule "unmet = last value did not reach the target" itself (FR-020, FR-018). The screen says "Annual planning offers N key results again", so the number is the one of planning.
- **Reason**: SC-006 says the two numbers match in all tests. One owner and one call makes that true by construction. 006 reads the live series, and the review reads snapshots, so a value entered after the last snapshot can make "missed" in the review and "met" in planning. The review shows the note of FR-029 for that case.
- **Rejected**: Compute the count in the review from snapshots (it would differ from planning in that case, and it restates the rule). Count from the live series with our own call (a second copy of the rule).
- **Needs confirmation**: the count is the planning count, so it can differ from the number of "missed" rows (see the summary).

## R-10: The Year view becomes the review, old routes and old reviews stay

- **Decision**: The route `/year` (key `y`) shows the annual review for the current year, and `/year/:year` for another year. The nav label changes from "Year" to "Year review". `YearScreen`, `yearViewProvider` and `PlanningApi.yearView` leave the client. The server route `GET /views/year/{year}` stays as it is (005 and 006 list it as unchanged apart from the removed `goals` field), so no API client breaks. The year checklist (`PlanningChecklist`, kind year) stays on the screen, as on the old Year view. The stored period reviews (table `period_reviews`, route `/review` and `PlanHistoryScreen`) are untouched. The review links to them: "Earlier reviews of this year" opens `/review?period=year&year=N` and the screen shows only the entries of that year. Month and week goal rows are not read by the review (FR-021).
- **Reason**: FR-021 and user story 8. Folding the screen but keeping the stored data means no migration of old reviews.
- **Rejected**: Remove `GET /views/year/{year}` now (no requirement, and tests for it exist). Convert old period reviews into annual reviews (spec: they stay unchanged).
- **Needs confirmation**: keep the server route for now.

## R-11: Route names

- **Decision**: `GET /annual-review/{year}`, `PUT /annual-review/{year}/notes`, `DELETE /annual-review/{year}/notes`. The prefix `annual-review` does not collide with `annual` of 006 or with `plans/{id}/review` of the old reviews. "Start next year" opens the client route of annual planning with `year = N + 1` and `from_year = N` (the "from year N" input of 006, task T077 there). The review sends no request for it.
- **Reason**: FR-018, FR-019. A client link creates nothing, so SC-006 holds without a test of a negative.

## R-12: Connections

- **Decision**: Goals, key results, links and snapshots are per user in 004 to 007 (no `connection_id`). The review is private to the user (FR-022). A theme entry carries the `connection_id` and the connection name of its project row, so the screen can show the name when the user has two task connections. The review does not filter by the active connection, because the stored goals and snapshots have no connection.
- **Reason**: The edge case "two connections: show only the data of the user and the connection that is active" cannot be done for data that has no connection. Filtering themes only would hide stored links silently.
- **Rejected**: Add a connection filter to themes only. It would make the year totals differ from the sum of what the screen lists.
- **Needs confirmation**: this reading of the edge case.

## R-13: Months and the year state

- **Decision**: The twelve months of a year are `YYYY-01` to `YYYY-12`. A month is `stored` when a snapshot exists, `missing` when it is in the past with no snapshot, `open` when it is the current month with no snapshot, and `future` otherwise. The year state is `past`, `current` or `future` from `domain/annual_plan.py::year_state` (006), with today in the user time zone. A past year gives final results. The current year gives `in_progress` and no hit or missed. A future year gives the empty state `future_year` and no data.
- **Reason**: FR-010, FR-012 and the edge case "a review opened for a future year".

## R-14: Performance

- **Decision**: One read of the snapshots (one query, current versions of one year), one read of the plan of the year with links and history (006), one read of project labels for the themes that appear, one read of the notes. No query per key result or per month. The pure functions work on in-memory values. A test seeds 20 themes, 10 key results and 12 snapshots, asserts the number of queries and a time under 500 ms on SQLite (SC-007 allows 2 s on a phone, mostly render time). The client builds the month rows lazily and collapses themes in groups of more than 20 (edge case).
- **Reason**: SC-007.

## R-15: Test data for snapshots

- **Decision**: Tests and the demo seed write snapshot rows through a helper `store_snapshot(db, user_id, month, payload, version=1)` (in `backend/tests/integration/conftest.py` and in `scripts/seed_annual_review.py`) that creates the `monthly_reviews` header and the `monthly_review_snapshots` row directly. It is the only place outside 007 that writes these tables, and only in tests and in the seed script. The seed script has its own recipe `just backend::seed-annual-review`.
- **Reason**: 007 refuses a plan for a past month (`past_month`), so the real flow cannot create a snapshot of last year. The review itself never writes snapshots (SC-002). A test in 007 already fails when `UPDATE` or `DELETE` of the table appears in `backend/src/`; the review adds a test that no insert appears in its code either.
- **Rejected**: A test clock that moves into the past. It would hide the "past month" rule of 007.

## R-16: Mid-year changes

- **Decision**: Retired goals come from `retired_goals` of the 006 plan read and are shown with `retired_at`. A retired key result of an active goal is shown with its own date. The outcome of a retired item is `retired` and never `missed` (FR-013). The target changes and deadline changes come from `GET /annual/{year}/history` of 006 (kinds `key_result_edited`, fields `target` and `deadline`). The review reads them in process and lists them under the key result. The result uses the target at the end of the year, which is the stored target of the key result.
- **Reason**: FR-013 and user story 5. History is owned by 006 and is append only.

## R-17: Hidden contract drift

- **Decision**: Every enum that appears in a response model of the router is the domain enum class, never a hand-written `Literal` (the rule of 005, R-17 there). A unit test builds the response model once for every member of every enum, and the live smoke test in M3 calls the real server for a year that shows each value.
- **Reason**: A response schema `Literal` that missed a new value once crashed the real API. The unit tests had not caught it. The smoke test over HTTP is the guard.

## Names (filled by task T017)

The built code keeps the design names with these differences:

- The snapshot reader is `MonthlyReviewService.current_snapshots(db, user_id, year)`. It returns `month`, `version`, `taken_at` and `snapshot`.
- The plan reader is `AnnualPlanService.plan(db, user_id, year, tz=...)` and `AnnualPlanService.history(db, user_id, year)`. `history` also takes optional `goal_id` and `key_result_id`.
- The seed counter wraps `AnnualPlanService.suggestions(db, user_id, year, from_year=...)`.
- The client route for a missing month is `/month/review?date=YYYY-MM-01`.
- The route of the old year view stays `GET /views/year/{year}`.
