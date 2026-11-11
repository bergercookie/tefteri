# Data Model: Annual Review

Migration `0023_annual_review` (revision `0023`, down revision `0022`). The numbers are reserved: 0019 feature 004, 0020 feature 006, 0021 feature 005, 0022 feature 007, 0023 this feature. Model in `backend/src/tefteri/db/models/review_note.py` (new). Pure rules in `backend/src/tefteri/domain/annual_review.py` and `backend/src/tefteri/domain/snapshot_view.py` (new). Names of entities that other features own are copied from their design files: `goals`, `key_results`, `key_result_values`, `key_result_themes`, `plan_changes` (006); `monthly_reviews`, `monthly_review_snapshots` and the snapshot payload (007); `project_labels` (003); `task_categories` and `percentages` (005).

This feature adds **one table**. Everything else on the screen is read from the stored data of other features and computed when it is read. Nothing in this model is a copy of history.

## `review_notes` (new)

One row per user, year and scope. It holds the only thing that the review writes (FR-017).

| Column | Type | Notes |
|---|---|---|
| `id` | UUID, primary key | |
| `user_id` | UUID, FK `users.id`, cascade | Private to the user (FR-022). Index. |
| `year` | integer, not null | The planning year of the review. Check `year BETWEEN 2000 AND 2100`. |
| `goal_id` | UUID, null, FK `goals.id`, cascade | The goal of the note. Null means the note of the year. The goal must be an annual goal of the user whose `period_start` year equals `year` (checked by the service). |
| `body` | text, not null | 1 to 2000 characters after trimming (R-08). |
| `created_at`, `updated_at` | datetime with zone, not null | |

Constraints: partial unique index `uq_review_notes_year` on (`user_id`, `year`) where `goal_id IS NULL`; partial unique index `uq_review_notes_goal` on (`user_id`, `goal_id`) where `goal_id IS NOT NULL`. Both kinds of partial index work on SQLite and PostgreSQL (006 uses the same for `key_result_themes`). Check `length(body) BETWEEN 1 AND 2000`.

Rules: a delete removes the row (no soft delete). The service answers a delete with the removed note so the client can undo by writing the text again (R-08). A note never changes a snapshot, a goal, a key result or a link.

## Existing tables read (never written)

| Table | Owner | Read for |
|---|---|---|
| `monthly_reviews`, `monthly_review_snapshots` | 007 | The current version of each month of the year, through `current_snapshots` (R-01). |
| `goals`, `key_results` | 006 | Goals and key results of the year, active or retired, with start value, target, deadline, retirement date. |
| `key_result_themes` | 006 | The links with `started_at` and `ended_at` (ranges). |
| `plan_changes` | 006 | Target and deadline changes, retirements, link changes (history of the year). |
| `key_result_values` | 006 | Only the newest value and its time stamp, for the note "value moved after the last snapshot" (FR-029) and for the current value of a year with no snapshot. Never for a hit or missed result. |
| `project_labels` | 003 | The stored name, the orphan mark and reason, the current label and the connection of a theme. |
| `period_reviews`, `plans` | old | Only to find the stored period review of the year for the link (US8). Not changed. |
| `task_categories` | 005 | Not read by the review. The drill-down reads it through `GET /statistics/tasks`. |
| `tasks`, `milestones`, `weekly_plans` | 004 | Not read. A test fails when the review reads them (FR-001). |

## Derived values (not stored)

All of these are computed by the pure functions in `domain/annual_review.py` from values that the service reads. Their output types are value objects.

- **Snapshot view** (`SnapshotView`): the typed, tolerant reading of one payload (R-02). Fields that a payload does not hold are `None`.
- **Month status** (`MonthStatus`): `stored`, `missing`, `open` or `future` for each of the twelve months (R-13).
- **Year state**: `past`, `current` or `future` (006 `year_state`).
- **Key result outcome** (`KeyResultOutcome`): `hit`, `missed`, `no_value`, `retired` or `in_progress`.
  - `retired`: the key result or its goal is retired.
  - `in_progress`: the year is current (no final result).
  - `no_value`: no snapshot holds a value with a time stamp for it.
  - `hit` or `missed`: `is_met(last_value, start_value, target)` (006).
- **Last value**: `latest_value`, month and `latest_at` of the newest snapshot of the year that holds a time stamp for the key result.
- **Deadline line** (`DeadlineState`): `reached`, `not_reached`, `open` or `no_value` (R-03).
- **Series**: twelve points, one per month: the `latest_value` of that month's snapshot, or a gap (`missing`, `open`, `future`, or `not_stored` when the snapshot has no entry for the key result).
- **Peak**: the best value of the series in the direction of the target, with its month. Shown only when it differs from the last value.
- **Moved after the last snapshot**: the newest value of the 006 series when its time stamp is after the `latest_at` of the last snapshot value and its value differs. Only for a past year (FR-029).
- **Link ranges and active months**: from `started_at` and `ended_at`, in the user time zone (R-04).
- **Theme contribution** (`ThemeContribution`): for one key result and one link: the ranges, the milestones counted by date, the milestones shipped outside the focus, the sum of the monthly targets, the movement and its fraction, and the hint (`ThemeHint`: `much_shipped_little_movement`, `movement_not_from_theme` or none). The same theme under two key results gives two contributions.
- **Year totals of milestones**: the number of distinct `milestone_id` over the snapshots of the year (counted once).
- **Year split** (`YearSplit`): the sum of `categories` of the snapshots that hold them, the sum of `hidden`, the covered months, one row per month, the percentages from `percentages` (R-06).
- **Coverage**: `stored`, `expected` (12 for a past year, the months up to and including the current month for the current year), and the list of missing months.
- **Next year summary**: `year + 1`, `from_year = year`, the number of key results and links that 006 offers, and `has_plan` (R-09).
- **Empty reason**: `no_snapshots`, `no_goals` or `future_year`.
- **Stored period review of the year**: the id of the newest `plans` row of period type year with a stored `period_reviews` row for that year, or none (US8).

## Value objects (domain, not stored)

```text
SnapshotView(month: str, version: int | None, taken_at, schema_version: int | None,
             themes: list[ThemeEntry], outside_focus: list[OutsideEntry],
             categories: CategoryCounts | None, key_results: dict[str, KeyResultEntry])
ThemeEntry(project_id, name, target: int | None, done: int | None,
           milestones: list[MilestoneRef], status)
MilestoneRef(milestone_id, name, done_on: date)
KeyResultEntry(key_result_id, start_value, base_value, latest_value, latest_at,
               target, deadline, retired)
CategoryCounts(goal_aligned, maintenance, off_plan, hidden)     # same shape as 005
LinkRange(project_id, start: date, end: date | None)
```

`CategoryCounts` is the class of 005 (`domain/work_categories.py`). The review imports it and does not define its own.

## Enums (in `domain/enums.py`, used by the schemas)

| Enum | Members |
|---|---|
| `KeyResultOutcome` | `hit`, `missed`, `no_value`, `retired`, `in_progress` |
| `DeadlineState` | `reached`, `not_reached`, `open`, `no_value` |
| `MonthStatus` | `stored`, `missing`, `open`, `future` |
| `ThemeHint` | `much_shipped_little_movement`, `movement_not_from_theme` |
| `ReviewEmptyReason` | `no_snapshots`, `no_goals`, `future_year` |

`YearState` and `OrphanReason` already exist (006, 003).

## State changes

```text
(no note)  --PUT note---------> note                (created)
note       --PUT note---------> note                (text replaced, updated_at)
note       --DELETE-----------> (no note)           (the deleted text is returned; PUT again is the undo)
```

The review itself has no state. Opening it, in any state of the year, changes no row (SC-002). A test compares the row counts and a hash of the rows of every table before and after.

## Validation rules

- `year` is an integer from 2000 to 2100 (route check, `invalid`).
- A note for a future year is refused (`future_year`).
- `goal_id` must be an annual goal of the user of that year, active or retired (`not_found` otherwise).
- `body` is trimmed and has 1 to 2000 characters (`invalid`).
- No field of this feature holds hours, duration or effort (decision of 005).

## Migration notes

- `down_revision = "0022"`. The single-head test of the migration suite fails on a fork.
- Downgrade drops `review_notes`. The notes are lost on downgrade, and the migration test says so.
- The migration changes no existing table, so no existing row is touched.
