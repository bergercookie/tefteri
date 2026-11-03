# Data Model: Split Planning Layout

Delta on spec 001 `data-model.md`. Only changes are listed.

## Task (cached mirror) — semantics change, no new column
- `due_at` (UTC timestamp, nullable) is the **planned time**. With `all_day=true` it means "this
  date only"; the time part is ignored and the date is taken in the user's time zone.
- `all_day` (existing column) is now also set for date-only tasks of backends that use a
  convention for it (Vikunja: due at 00:00 local, research R-03).
- `scheduled_start` / `scheduled_end` become **derived cache columns**:
  `scheduled_end = due_at`, `scheduled_start = due_at − 1h` when `due_at` is set and
  `all_day=false`; both null otherwise. They are rewritten on every mirror update and are never
  sent to a backend.
- Rules: a task is *scheduled* when `due_at` is set. *Unscheduled* means `due_at` is null.
  *Overdue* means open, timed, and `due_at < now`, or open, all-day, and date < today.

## User — one new field
- `random_time_on_date_drop` (bool, default `false`): when true, a drop on the all-day area or
  a day cell without time slots gets a random block start between 08:00 and 19:45 local time
  (15-minute marks), and due = start + 1h.
- Migration `0006` adds the column with a server default of false.

## TaskBlock (derived, not stored)
- `start = due_at − 1h`, `end = due_at`, `clipped_start` (bool, true when the start
  falls on the previous local day and is clipped to 00:00).
- Built by `domain/planning_time.block_for(due_at, tz)`.

## TaskFilter (request-level value, not stored)
- `due`: `today | tomorrow | week | all | none | overdue`; `q`: text; both applied to **open**
  tasks. When `q` is non-empty, `due` is ignored.
- Day and week boundaries come from the user's time zone; the week is Monday to Sunday.
