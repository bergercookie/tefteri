# Data Model: Annual Planning, Goals and Key Results

Migration `0020_annual_planning`. Models in `backend/src/tefteri/db/models/goal.py` (changed), `key_result.py` and `push_token.py` (new). The revision id is `0020`. Its `down_revision` is the newest revision that exists when the migration is written: `0019` once feature 004 has merged, `0018` before that. The single-head test catches a fork. Feature 005, 007 and 008 use `0021` to `0023`.

## `goals` (changed)

One row per goal. A row with `period_type = 'year'` is an annual goal. A row with `month` or `week` is read-only history.

| Column | Type | Notes |
|---|---|---|
| `id`, `user_id`, `parent_id`, `period_type`, `period_start`, `title`, `description`, `criteria` | unchanged | `title` is the loose sentence (FR-001). `criteria` is the old criteria text, offered as a key result metric suggestion while the goal has no key result (FR-024). `parent_id` links a legacy month or week goal to its parent. An annual goal has no parent. |
| `status` | string(8) | Annual goal: `active` or `retired`. A legacy year goal can still be `done` (treated as active). Month and week rows keep `active`, `done` or `dropped`. |
| `updated_at` | datetime, not null | New. The date of the last change (FR-001). Set to the migration time for existing rows. |
| `retired_at` | datetime, null | New. Set when `status` becomes `retired`. |
| `retired_reason` | text, null | New. Optional reason typed by the user. |
| `position` | integer, default 0 | New. Order of the goals inside one year. |

Index: `ix_goals_user_period` on (`user_id`, `period_type`, `period_start`). The foreign key from `tasks.goal_id` and the self-reference `parent_id` are unchanged. No route deletes a goal.

## `key_results`

| Column | Type | Notes |
|---|---|---|
| `id` | UUID, primary key | |
| `user_id` | UUID, FK `users.id`, cascade | Private to the user (FR-029). |
| `goal_id` | UUID, FK `goals.id`, cascade, indexed | The goal must be an annual goal of the user. |
| `year` | integer | The planning year of the goal. Copied at creation, checked equal to `goals.period_start.year`. Used for the year queries and the past-year rule. |
| `metric` | string(500) | Text, for example "stars on one repository". |
| `start_value` | float | Finite number. |
| `target` | float | Finite number. A check constraint `target <> start_value` (FR-005). |
| `deadline` | date | Inside `year` (FR-005). |
| `update_source` | string(9) | `manual` or `automatic` (FR-004). |
| `status` | string(8) | `active` or `retired`. |
| `slot` | smallint, null | 1 to 3 while active, null when retired (R-03). Unique with `goal_id`. Check `slot BETWEEN 1 AND 3` and `(status = 'active') = (slot IS NOT NULL)`. |
| `position` | integer | Display order inside the goal. |
| `retired_at`, `retired_reason` | datetime null, text null | |
| `seeded_from_id` | UUID, null, FK `key_results.id`, set null | The key result of year N that this one was copied from. For the history and for 008. |
| `created_at`, `updated_at` | datetime | |

There is no `current_value` column (R-02).

## `key_result_values`

The dated series. Rows are only added.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID, primary key | |
| `user_id` | UUID, FK, cascade | |
| `key_result_id` | UUID, FK `key_results.id`, cascade | |
| `value` | float | Finite number. |
| `at` | datetime with zone | The time stamp of the value (given by the user or by the push). |
| `on_date` | date | The day of `at` in the user time zone when written (R-08). |
| `source` | string(9) | `manual` or `automatic`. |
| `seq` | integer | 1, 2, 3 ... per key result. Unique with `key_result_id`. A higher `seq` was entered later. |
| `entered_at` | datetime | Server time when the row was written. |

Index: (`key_result_id`, `on_date`, `seq`). The current value is the row with the highest (`on_date`, `seq`). `value_on(day)` is the row with the highest (`on_date`, `seq`) where `on_date <= day`, or none.

## `key_result_themes`

One row per link period.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID, primary key | |
| `user_id` | UUID, FK, cascade | |
| `key_result_id` | UUID, FK `key_results.id`, cascade, indexed | |
| `project_id` | UUID, FK `project_labels.id`, cascade, indexed | The theme project (feature 003). |
| `year` | integer | The planning year of the key result (FR-011). |
| `started_at` | datetime | |
| `ended_at` | datetime, null | Null while the link is active. |
| `end_reason` | string(20), null | `removed`, `relinked`, `key_result_retired`, `goal_retired`. |
| `batch_id` | UUID, null, indexed | The action that started or ended the link. |

Partial unique index `uq_key_result_themes_active` on (`key_result_id`, `project_id`) where `ended_at IS NULL` (SQLite and PostgreSQL both support it).

## `plan_changes`

Append only. No update and no delete in the code (FR-019).

| Column | Type | Notes |
|---|---|---|
| `id` | UUID, primary key | |
| `user_id` | UUID, FK, cascade | |
| `year` | integer, indexed | The history is shown per year. |
| `goal_id` | UUID, null, FK `goals.id`, cascade | |
| `key_result_id` | UUID, null, FK `key_results.id`, cascade | |
| `link_id` | UUID, null, FK `key_result_themes.id`, set null | |
| `kind` | string(24) | See the list below. |
| `field` | string(16), null | For an edit: `title`, `metric`, `target`, `deadline`, `update_source`, `start_value`. |
| `old_value`, `new_value` | text, null | Strings. For a link: the project name. |
| `reason` | text, null | Optional reason of a retirement. |
| `batch_id` | UUID, null, indexed | One user action. |
| `source` | string(9) | `user`, `undo`, `seed`, `migration`. |
| `at` | datetime | |

Kinds: `goal_created`, `goal_edited`, `goal_retired`, `goal_restored`, `key_result_created`, `key_result_edited`, `key_result_retired`, `key_result_restored`, `link_added`, `link_removed`, `migrated`.

## `value_push_tokens`

| Column | Type | Notes |
|---|---|---|
| `id` | UUID, primary key | |
| `user_id` | UUID, FK, cascade, **unique** | One token per user. |
| `token_hash` | string(64), unique | SHA-256 of the token. The token is never stored. |
| `hint` | string(4) | The last four characters, shown in the settings. |
| `created_at` | datetime | |
| `last_used_at` | datetime, null | Set by an accepted push. |

## Existing tables (unchanged)

- `tasks`: `goal_id` stays. Its meaning stays: a task links to at most one goal. The goal picker offers annual goals of the current year only (FR-026).
- `plans`, `period_reviews`: unchanged. A stored review loads as it is (FR-027). Feature 007 owns the snapshot rules.
- `project_labels`, `project_label_history` (feature 003): read only for this feature, except through `create_and_label`.

## Derived values (not stored)

- **Current value**: the value of the highest (`on_date`, `seq`), else `start_value`.
- **Progress** (per key result): `(current - start) / (target - start)`. Negative when it moves away. Not capped.
- **Met**: `current >= target` when `target > start`, else `current <= target`.
- **Overdue**: active, `deadline < today` in the user time zone, and not met.
- **Goal progress** (display only): the mean of the progress of its active key results, each limited to 0 to 1. None without key results.
- **Usable link**: active, project label `theme`, project not orphaned, no ignored ancestor.
- **Flags**: `no_key_result` (goal), `no_usable_theme` and `overdue` (key result). Never stored.
- **Year state**: `past`, `current` or `future`, from the year and today in the user time zone.
- **Suggestions** for a new year: see research R-10.

## State changes

```text
goal        active --retire--> retired        (retires its active key results; links end)
goal        retired --restore--> active       (restores the key results of the same batch; links start again)
key result  active --retire--> retired        (frees the slot; links end; series stays)
key result  retired --restore--> active       (needs a free slot; links of the same batch start again)
link        (none) --add--> active --remove / re-link / retire--> ended
value       (none) --enter or push--> stored  (never edited, never deleted)
```

## Validation rules

- Goal title: 1 to 500 characters after trimming.
- Key result: metric 1 to 500 characters; start, target and value finite numbers; `target <> start_value`; `deadline` inside the planning year of its goal; at most three active key results for each goal.
- Links: a project that is a live theme (feature 003). A second active link to the same project is refused.
- Value: finite number; manual date not after today; push time stamp with a zone and not more than 5 minutes in the future.
- Past year: only values may be written.
