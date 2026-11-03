# Research: Split Tasks-and-Calendar Planning Layout

Spec 001 decisions (R-01 to R-14) still apply. New decisions are numbered from R-01 again in
this file and are local to feature 002.

## R-01 Where the planned time lives
- **Decision**: Core logic uses one backend-neutral planned time: `due_at` plus `all_day`. The
  block is *derived*: `[due_at − 1h, due_at]`. The derivation is a pure function in
  `domain/planning_time.py`.
- **Rationale**: Constitution Principle VII and Principle IV together. One stored date; no core
  code names a Vikunja field.
- **Alternatives**: Keep `start_date`/`end_date` as well (rejected: a second source of truth,
  forbidden by Principle VII); store the block start in tefteri only (rejected: it would
  differ from what the user sees in Vikunja).

## R-02 Existing cached columns `scheduled_start` / `scheduled_end`
- **Decision**: Keep the columns, but fill them only from `due_at` at mirror time
  (`scheduled_start = due_at − 1h`, `scheduled_end = due_at`, both null when no time or
  all-day). Existing readers (daily view, reviews, planning views) keep working and now see
  the same time as the planner.
- **Rationale**: Smallest change; no breaking schema change; the values can always be
  recomputed. A later cleanup can drop the columns.
- **Alternatives**: Drop the columns now (touches 6 readers and the API schema; no user
  value now).
- **Upgrade note**: Tasks that earlier versions scheduled through Vikunja `start_date`/
  `end_date` and have no due date will show as unscheduled after the upgrade. Tefteri does not
  rewrite them in Vikunja. The release notes and the user guide say so.

## R-03 Date-only due dates in Vikunja
- **Problem**: Vikunja stores a due date as a timestamp. It has no all-day flag in the task
  fields tefteri uses.
- **Decision**: The Vikunja adapter encodes a date-only due date as **00:00:00 in the user's
  time zone** on that date, and decodes a due time of exactly 00:00:00 local as `all_day=true`
  on that date. The convention lives only in the adapter and is covered by a contract test.
  A task a user truly sets to exactly 00:00 shows as all-day; this is documented.
- **To verify before implementation**: how the Vikunja web app shows a due date at 00:00 and
  whether a different value is its own all-day convention. If it differs, only the adapter
  constants change. Record the result here.
- **Verification status (2026-11-02)**: NOT verified against a real Vikunja server. No Vikunja
  instance was reachable while implementing. The convention is implemented and tested only
  against the hand-written fake (`backend/tests/fakes/http/vikunja.py`) and recorded
  responses. It is isolated in `VikunjaTaskBackend.set_planned_time` and `_task`
  (`backend/src/tefteri/adapters/vikunja/adapter.py`). Check it on a real server before a
  release.
- **Alternatives**: 23:59:59 (collides with "end of day" deadlines, which are common); a
  Vikunja label or custom field (more setup for the user).

## R-04 Task filters and search: where they run
- **Decision**: On the server, in `GET /tasks`, against the cache. Parameters:
  `due=today|tomorrow|week|all|none|overdue`, `q`, `status=open`. A separate
  `GET /tasks/counts` returns the six counts. Day boundaries use the user's stored time zone
  and an injectable clock. "This week" is Monday to Sunday.
- **Rationale**: One implementation for every client; testable with a fixed clock; works for
  2,000 tasks with plain indexed queries.
- **Alternatives**: Filter in the client (duplicates logic on three platforms, harder to test
  time rules).
- **Search**: case-insensitive substring match on title across all open tasks; the active
  filter is ignored while `q` is set (spec FR-019). No full-text index needed at this scale.

## R-05 Random time for date-only drops
- **Decision**: The server applies it. The client sends `{date}`. If
  `users.random_time_on_date_drop` is true, `planning_time.pick_random_start(date, tz, rng)`
  chooses a block start uniformly among 15-minute marks from 08:00 to 19:45 (spec
  FR-017: the start lies within 08:00 to 20:00); the due time is start + 1h. `rng` is injected so tests are exact.
- **Rationale**: One place for the rule; the same behaviour on every client.
- **Alternatives**: Random in the client (three implementations, hard to test).

## R-06 Time grid in Flutter without a new package
- **Decision**: Build a small time-grid widget: one `DragTarget` per day column. On drop, the
  local pointer offset is converted to a minute offset and snapped to 15 minutes in
  `time_grid.dart` (pure functions, unit-testable). Blocks are positioned with `Stack`.
  Overlapping blocks share the column width. Desktop and web use `Draggable`; touch uses
  `LongPressDraggable`.
- **Rationale**: No dependency to audit or keep up to date; the layout math is small.
- **Alternatives**: A calendar package (extra dependency, limited drag-from-outside support,
  hard to restyle for task vs. event blocks).

## R-07 Routes and navigation
- **Decision**: `/` is the planner. The Today view moves to `/daily`. The old `/calendar` list
  screen stays one release as a redirect to `/` so bookmarks work, then is removed. Shortcuts:
  `p` Planner, `t` Day. `docs/user/shortcuts.md` and the in-app help come from the same
  `appViews` list.
- **Alternatives**: Keep Today at `/` and add a switch (rejected: the user asked for the split
  view as the default).

## R-08 Narrow layout
- **Decision**: Below 840 dp use two tabs (Tasks, Calendar), keep the filter, search and week
  in state so tab switches do not reset them, and offer "Schedule…" on each task (date and a
  time in 15-minute steps) instead of drag and drop. Tapping an empty calendar slot to open the dialog was left out:
  the Schedule… dialog already meets FR-014 and SC-005.
- **Rationale**: Meets FR-014 and SC-005 (task → Schedule → pick time → confirm).

## R-09 Error handling for drops
- **Decision**: The UI is not optimistic. The block appears after the server confirms. During
  the request the dragged task shows a pending state. On error, the banner names the
  connection and the reason (existing `ErrorBanner`), and the lists reload from the cache.
  Remote changes follow the existing conflict flow (409 `remote_conflict`).

## R-10 Block that would start before midnight
- **Decision**: A block is drawn clipped to the day it ends on (starts 00:00) and marked
  "continues from previous day". The stored due time is not changed.

## Baseline (before implementation, 2026-11-02)
- `just backend::test`: 179 passed (3 Postgres tests deselected).
- `just frontend::test`: 120 passed. This first run did not exclude the screenshot tests (the tag name was mistyped); the recipe itself excludes them.
