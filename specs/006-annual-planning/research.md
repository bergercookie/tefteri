# Research: Annual Planning, Goals and Key Results

Decisions taken before design. Each has the choice, the reason and what was rejected. No `NEEDS CLARIFICATION` is left. The assumptions that the owner may still change are marked **Confirm**.

## R-01: Where a goal lives

- **Decision**: Keep the table `goals` and the model `Goal` in `backend/src/tefteri/db/models/goal.py`. Year rows are the annual goals. Month and week rows stay as they are and are read only through `GET /goals/history`. Add the columns `updated_at`, `retired_at`, `retired_reason` and `position`. The state of an annual goal is `active` or `retired`. A legacy status `done` on a year goal is left as it is and the plan treats it as active.
- **Reason**: `tasks.goal_id` has a foreign key to `goals.id`, stored period reviews hold goal ids, and `compute_review` reads `goals`. A new table would need a copy of every id and would break those links (FR-025, FR-027, SC-004). Keeping the `done` status means that a refresh of an old review gives the same result as before. `compute_review` must skip `retired` goals the way it skips `dropped` ones.
- **Rejected**: A new `annual_goals` table with a copy of the data. It doubles the ids that a task can point to and needs a second link column on `tasks`. Also rejected: turning `done` into `active` in the migration. It loses the old completion mark and changes a refreshed review.

## R-02: The current value is derived

- **Decision**: A key result does not store its current value. The current value is the value of the series with the latest date (the latest `seq` on equal dates), or the start value when the series is empty. A new key result has an empty series.
- **Reason**: FR-006 says the current value starts at the start value, and the edge case "no value before a requested date" says the start value is not assumed for a date query. Two sources of truth would drift. An empty series satisfies both rules: `current_value` falls back to the start, and `value_on` answers none.
- **Rejected**: A stored `current_value` column updated on every write. A race between a push and a manual entry could leave it out of step with the series. Also rejected: writing the start value as the first series row. It would make `value_on` answer a value that nobody entered.

## R-03: At most three active key results, also under concurrency

- **Decision**: `key_results.slot` is a small integer from 1 to 3 for an active key result and null for a retired one. A unique constraint on (`goal_id`, `slot`) and a check `(status = 'active') = (slot IS NOT NULL)` hold the rule in the database. The service picks the lowest free slot. A clash raises an integrity error that the service turns into the message "A goal can have three key results. Retire one first." Restore needs a free slot too.
- **Reason**: SC-008 demands the limit "including concurrent saves". `NULL` values are distinct in a unique constraint on both SQLite and PostgreSQL, so retired rows do not use slots. No lock and no `SELECT FOR UPDATE` is needed, and the same code works on both databases.
- **Rejected**: Count the active rows and then insert. It has a race on PostgreSQL. Also rejected: a row lock on the goal. It does not exist on SQLite and hides the rule in code.

## R-04: Links keep their dates

- **Decision**: One row in `key_result_themes` per link period: `started_at`, `ended_at` (null while active), `end_reason` (`removed`, `relinked`, `key_result_retired`, `goal_retired`) and `year`. A partial unique index on (`key_result_id`, `project_id`) where `ended_at IS NULL` allows one active link. `project_id` points to `project_labels.id` (feature 003), which exists for orphaned projects too.
- **Reason**: FR-013 says removing or replacing a link must end it with a date and never delete it. A theme that is relabelled or orphaned keeps its link row. The flag and the screen read the current label (`project_labels.label`) and the orphan mark, so the link shows as inactive without any write. Feature 008 can read the dates.
- **Rejected**: A many-to-many table with no dates and a separate history table. It needs two writes for every change and the two can disagree. Also rejected: use `source_containers.id`. It is removed with the project (feature 003, R-06).

## R-05: One history table with batches and undo

- **Decision**: `plan_changes` is append only. One row per changed thing: `year`, optional `goal_id`, `key_result_id` and `link_id`, `kind`, `field`, `old_value`, `new_value`, `reason`, `batch_id`, `source` (`user`, `undo`, `seed`, `migration`) and `at`. One user action has one `batch_id`. Undo adds rows of kind `*_restored` or the reverse link change with `source = undo` and the same `batch_id`, and a second undo of the same batch answers 409 `already_undone`.
- **Reason**: FR-019, FR-021 and FR-032. It is the pattern of feature 003 (`project_label_history`, R-07). The retire effect and the retire itself use the same code, so the preview cannot disagree with the result (R-06).
- **Rejected**: Soft-delete flags only. They show the state but not the old and new values that FR-019 asks for. Also rejected: an event-sourced model. It is more than this feature needs.

## R-06: Preview before a destructive choice

- **Decision**: Every destructive route (retire a key result, retire a goal, change links) accepts `dry_run=true`. It computes the effect with the real code path inside the transaction, rolls back, and returns the effect: how many key results retire, how many links end, which flags disappear. The client always calls it first and shows the dialog. The real call returns the `batch_id`, and the client shows an Undo snackbar for 10 seconds. The history view keeps Undo for each batch.
- **Reason**: FR-021, FR-032 and the shared rule 9 of the decisions file. One code path means that the preview and the change cannot disagree.
- **Rejected**: A separate preview function. It would copy the rules.

## R-07: The inbound push

- **Decision**: One token per user. Table `value_push_tokens` with a unique `user_id`. The token is `tfv_` plus 32 random bytes in URL-safe base64. Only its SHA-256 is stored, plus the last four characters as a hint. The user creates or rotates it with `POST /annual/push-token`, and the plain token is shown once. A push is `POST /api/v1/key-results/{id}/push` with `Authorization: Bearer <token>` and the JSON body `{"value": 123, "at": "2026-11-11T09:30:00Z"}`. The route is separate from the session routes, ignores cookies, needs no `X-Tefteri-Client` header, and accepts only a push token. A session token is not a push token, and a push token cannot call any other route. The full contract is in [contracts/api.md](contracts/api.md).
- **Rules**: reject a value that is not a JSON number (a string like `"12"`, a boolean, `NaN` and infinity too) with 422. Reject a time stamp without a zone or more than 5 minutes in the future with 422. Reject a key result that is unknown or belongs to another user with 404 (the same answer, so a source cannot probe ids). Reject a retired key result with 409 `retired`. Reject a key result that is not automatic with 409 `not_automatic`. An identical push (same key result, same `at`, same value, source automatic) is accepted once and answers 200 with `stored: false`, so a source can retry safely. A push to a key result of a past year is accepted, because value entry is allowed there (FR-033). A failed push stores nothing.
- **Rate limit**: 60 pushes a minute for each token, in memory, with the same pattern as `auth/throttle.py`. Over the limit answers 429 with `Retry-After`.
- **Reason**: FR-010 and SC-007. A hashed token follows `AuthSession`. A separate table and route keep the token from reaching the rest of the API.
- **Rejected**: Reuse the session token. It expires, it can do everything, and one leak would give full access. Also rejected: one token per key result. The spec says one token per user. Also rejected: a webhook that Tefteri calls (pull). The spec says Tefteri never pulls.

## R-08: Value date and order

- **Decision**: Each value has `at` (a time stamp with zone) and `on_date`, the calendar day of `at` in the time zone of the user at the moment of writing. The current value and `value_on` use `on_date` and, on equal days, `seq` (a counter per key result, higher is later). A manual entry takes a date and no time: the time is the current time when the date is today, and 12:00 local time for a past day. A manual date in the future is refused (422 `future_date`). **Confirm**: the spec does not say whether a future date is valid. Refusing it keeps "the value on or before a date" meaningful.
- **Reason**: FR-007 and FR-034 speak of dates, not of instants. Storing `on_date` fixes the day even if the user later changes the time zone.
- **Rejected**: Order by `at` only. Two pushes on one day would order by clock skew of the source, but FR-007 says that on equal dates the value entered last wins.

## R-09: Past year, current year, future year

- **Decision**: The year state is worked out by a pure function from the year and "today" in the time zone of the user: `past` when the year is before the current year, `current`, `future`. A past year allows value entry (manual and push) and refuses every structure change with 409 `past_year`: add, edit, retire, restore, change links, seed into it. The check sits in one place, `AnnualPlanService._require_open(year)`. Undo of a change made in the current year, after the year has ended, is refused for the same reason.
- **Reason**: FR-033 and the edge cases.
- **Rejected**: Check in each route. It would be missed in one.

## R-10: Seeding from year N

- **Decision**: Seeding is read only until accepted. `GET /annual/{year}/suggestions?from_year=N` computes suggestions: the active goals of year N; for each, its active key results that are **unmet** (the last value did not reach the target; the start value counts when there is no value), and for each such key result its active links to themes that are still usable now (stored label theme, not orphaned, not ignored, no ignored ancestor). A met key result is not offered, its goal is. A retired goal or key result is not offered. The accepted key result has the old metric and target, a start value equal to the last value of year N (editable), and a deadline moved into the new year (the same month and day; 29 February becomes 28 February). Accepting posts the edited drafts to `POST /annual/{year}/goals/bulk` with `seeded_from`, which creates everything in one batch with `source = seed`. The data of year N is never written. `from_year` must be earlier than the year; a year with no plan answers an empty suggestion list with `has_plan: false`.
- **Reason**: FR-016, FR-017 and SC-006. The "unmet" rule has one owner, `domain/key_results.py::is_met`.
- **Rejected**: Store the suggestions. They would need cleanup and could go stale. Also rejected: carry the old start value. A key result that was half done would restart at zero progress on a number that moved.

## R-11: The meaning of "met" and "overdue"

- **Decision**: A key result is **met** when the current value reached the target in the direction of the plan: `current >= target` when `target > start`, `current <= target` when `target < start`. **Progress** is `(current - start) / (target - start)`. It is negative when the value moves away and above 1 when it goes beyond the target. The stored value is never capped. The screen caps the bar and writes the number. The flag **overdue** is shown for an active key result when the deadline is before today (in the user time zone) and it is not met. A deadline of today is not overdue until tomorrow. The progress of a goal for display is the mean of the progress of its active key results, each limited to 0 to 1, and none when there is no key result.
- **Reason**: FR-008, the edge cases (lower target, beyond the target) and the decisions file (008 reuses "hit").
- **Rejected**: Compare with the target only (`current >= target`). It fails for a lower target.

## R-12: Flags are computed on read

- **Decision**: The three flags are never stored. `domain/key_results.py` has pure functions: `goal_flags(active_key_results)` and `key_result_flags(key_result, links, today)`. A link is **usable** when it is active, its project has the stored label `theme`, the project is not orphaned, and no ancestor is ignored (feature 003 `is_eligible`). The flag `no_usable_theme` carries a reason for each link that is not usable: the project name and its state (`orphaned`, `ignored`, `relabelled` with the new label, or `unclassified`), or the reason `no_links` when there is no link. Each flag carries the inline actions that the client shows (`add_key_result`, `link_theme`, `create_theme`, `update_value`). The flag never changes a response status.
- **Reason**: FR-014 and SC-002. A computed flag cannot go stale when a project is relabelled in feature 003.
- **Rejected**: Store a flag column. It would need a write on every relabel and orphan event of feature 003.

## R-13: Create a theme from the planning screen

- **Decision**: `POST /annual/themes` calls `ClassificationService.create_and_label(connection_id, name, parent_id=None, label=theme)`. It does not restate the rule. Before the call it looks for a live theme with the same name (case-insensitive) in the same connection and answers 409 `theme_exists` with the id of the existing one, so the client can ask "link the existing theme instead?" (US4, scenario 3). The request needs `connection_id`; when the user has one task connection the client sends it. When the task app refuses, nothing is stored (feature 003 guarantees it) and the answer carries the code of feature 003.
- **Reason**: FR-015, feature 003 FR-024.
- **Rejected**: A second create path with its own label write.

## R-14: Goals leave the week and month flow

- **Decision**: Remove the write routes for goals (create, bulk, patch, delete, breakdown). Remove `goals` from the month and week views. Keep `GET /goals/history` for the legacy rows (month and week rows, and the criteria text of year rows). A task can link to a goal only when the goal is an active annual goal of the current year, or when the link is cleared, or when the value does not change. A task that points to a month or week goal keeps the link and the views show the goal title as history through `goal_titles` in the period view. The weekly planning flow and the look-back have no goal code today (checked by grep). A test proves that no endpoint or screen of those flows returns or offers a goal (SC-005).
- **Reason**: FR-022 to FR-026.
- **Rejected**: Keep the routes and hide the buttons. A hidden route can still write a month goal, and the spec says goals MUST NOT be created.

## R-15: Public ids and the shape of the screen

- **Decision**: Ids are UUIDs as everywhere. The planning screen is `/annual` with a year switch (the arrows and the "from year N" field live in the seed panel). It shows one card per goal, up to three key result rows in each card, and the flags inline. Terms (key result, theme project, retire, planning year, automatic, unmet) get a one-time hint at first use, remembered per device, with the same widget pattern as `term_hint.dart` of feature 003. The old Goals entry in the navigation becomes `Annual plan` and keeps the key `g`. The route `/goals` redirects to `/annual`.
- **Reason**: FR-035 and the usability rules of the decisions file (inline actions for empty pickers, every term once, every destructive choice shows its effect and can be undone).

## R-16: Test strategy

- **Decision**: Unit tests for the pure rules (progress both ways, met, overdue, current value, value on a date, validation, the limit, year state, seeding, deadline shift, flags). Integration tests with the in-memory fakes and the fake classification data for goals, key results, links, flags, create theme, retire, undo, history, seeding, series, push, legacy and past year. A concurrency test with two simultaneous adds (SC-008) on SQLite and on PostgreSQL. A migration test with counts before and after. Shared e2e tests for the routes and the OpenAPI snapshot. Widget tests with `fake_api.dart`. Screenshot tests for the docs. A Playwright walkthrough against a seeded live Vikunja.
- **Reason**: Constitution V and the request for real-user usability.
