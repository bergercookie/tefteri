# Data Model: Monthly Planning and Review

Migration `0022_monthly_cycle` (revision `0022`, down revision `0021`). The numbers are reserved: 0019 feature 004, 0020 feature 006, 0021 feature 005, 0022 this feature, 0023 feature 008. Models are in `backend/src/tefteri/db/models/monthly.py` (new). The pure rules are in `backend/src/tefteri/domain/monthly.py` (new).

## `monthly_focuses` (new)

One row per user and month. The row exists once the user has saved a plan for the month. No row means "no focus data" (the focus provider returns `None`).

| Column | Type | Notes |
|---|---|---|
| `id` | UUID, primary key | |
| `user_id` | UUID, FK `users.id`, cascade | Private to the user (FR-039). Index. |
| `month` | date, not null | First day of the month, a local date (research R-13). Check: day is 1. |
| `created_at`, `updated_at` | datetime with zone | |

Constraint: unique (`user_id`, `month`).

## `monthly_focus_entries` (new)

One row per theme in the focus of a month.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID, primary key | |
| `focus_id` | UUID, FK `monthly_focuses.id`, cascade, index | |
| `project_id` | UUID, FK `project_labels.id`, cascade | The theme project (003). The row of `project_labels` is never deleted, so an orphan keeps its entry. |
| `name` | string(255), not null | Copy of the name when the entry was made. History only. The screens show `project_labels.name`. |
| `target` | integer, null | Milestone-count target. Null means "no target". 0 is a real target. Check `target IS NULL OR target >= 0`. No hours, no time (FR-040). |
| `counts_from` | date, not null | The first day whose done milestones count towards the target (research R-05). The first day of the month for the first plan, the day of the change for a theme that was added later. |
| `left_on` | date, null | The local day the theme left the focus. Null while it is in the focus. |
| `left_reason` | string(12), null | `swapped_out` or `removed`. Null together with `left_on`. |
| `position` | integer, not null | Display order. |
| `created_at` | datetime with zone | |

Constraints: unique (`focus_id`, `project_id`), which is FR-004 (each theme at most once per month, also after it left). Check `(left_on IS NULL) = (left_reason IS NULL)`. Index on `project_id`.

## `focus_changes` (new)

The log of mid-month changes. Append only: the code never edits or deletes a row.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID, primary key | |
| `focus_id` | UUID, FK `monthly_focuses.id`, cascade, index | |
| `kind` | string(8), not null | `swap`, `add`, `remove`, `target`. |
| `changed_on` | date, not null | The local day of the change (FR-013). |
| `out_entry_id` | UUID, FK `monthly_focus_entries.id`, set null, null | The entry that left (`swap`, `remove`) or whose target changed (`target`). |
| `in_entry_id` | UUID, FK `monthly_focus_entries.id`, set null, null | The entry that came (`swap`, `add`). |
| `out_project_id`, `in_project_id` | UUID, FK `project_labels.id`, set null, null | |
| `out_name`, `in_name` | string(255), null | Copies, for the history and the review. |
| `target_before`, `target_after` | integer, null | For `target`, and `target_after` for the target of an entry that came. |
| `batch_id` | UUID, not null, index | One user action. An undo has its own batch. |
| `undoes_batch_id` | UUID, null, index | Set on the rows of an undo. |
| `source` | string(8), not null | `user` or `undo`. |
| `created_at` | datetime with zone | Orders the log. |

A change is shown as undone when a later row has its `batch_id` in `undoes_batch_id`. An undo is refused with `already_undone` for such a change, and with `not_undoable` when a later change touched the same theme (research R-02).

## `monthly_reviews` (new)

The header of the reviews of one month.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID, primary key | |
| `user_id` | UUID, FK `users.id`, cascade, index | |
| `month` | date, not null | First day of the month. |
| `current_version` | integer, not null | The version that other features read. |
| `current_changed_at` | datetime with zone, not null | |
| `created_at` | datetime with zone | |

Constraint: unique (`user_id`, `month`). This row is the only row of the review that changes after it is made, and only `current_version` and `current_changed_at` change.

## `monthly_review_snapshots` (new)

One row per stored version. Immutable: no update and no delete in the code (FR-029). A test fails when a `UPDATE` or `DELETE` of this table appears in `backend/src/`.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID, primary key | |
| `review_id` | UUID, FK `monthly_reviews.id`, cascade, index | |
| `version` | integer, not null | 1, 2, 3 ... Unique with `review_id`. |
| `schema_version` | integer, not null | 1 for this design. |
| `payload` | JSON, not null | The frozen snapshot (see below). |
| `values_written` | JSON, not null | List of `{"key_result_id": uuid, "value_id": uuid}`: the series rows that this save wrote (research R-07). Empty when none. Traceability only. |
| `created_at` | datetime with zone, not null | The time stamp of the version, shown in the history. |

## Snapshot payload (schema version 1)

Dates are ISO strings. There is no share, no percentage and no hours field (FR-027, FR-040). Every name is the stored name at review time (FR-029).

```json
{
  "schema_version": 1,
  "month": "2030-03-01",
  "month_end": "2030-04-01",
  "taken_at": "2030-04-02T08:00:00Z",
  "themes": [
    {
      "project_id": "uuid",
      "name": "Open source",
      "target": 3,
      "counts_from": "2030-03-01",
      "left_on": null,
      "status": "in_focus|swapped_out|removed",
      "orphaned": null,
      "label_changed": null,
      "done": 2,
      "marker": "met|missed|beaten|no_target",
      "milestones": [{"milestone_id": "uuid", "name": "Ship the login flow", "done_on": "2030-03-08"}],
      "earlier_not_counted": [{"milestone_id": "uuid", "name": "Fix the CI", "done_on": "2030-03-02"}],
      "key_result_ids": ["uuid"]
    }
  ],
  "changes": [
    {"kind": "swap|add|remove|target", "on": "2030-03-14", "out_project_id": "uuid|null", "out_name": "Admin", "in_project_id": "uuid|null", "in_name": "Open source", "target_before": null, "target_after": 2, "undone": false}
  ],
  "outside_focus": [
    {"milestone_id": "uuid", "name": "Pay the tax", "done_on": "2030-03-20", "theme_project_id": "uuid|null", "theme_name": "Home|null"}
  ],
  "categories": {"goal_aligned": 14, "maintenance": 6, "off_plan": 3, "hidden": 1},
  "key_results": [
    {
      "key_result_id": "uuid",
      "goal_id": "uuid",
      "goal_title": "Get better at open source",
      "metric": "Stars on one repository",
      "update_source": "manual|automatic",
      "start_value": 120,
      "base_value": 150,
      "latest_value": 220,
      "latest_at": "2030-03-28T10:00:00Z|null",
      "change": 70,
      "status": "updated|not_updated",
      "entered_in_review": false,
      "after_month_end": false,
      "target": 500,
      "deadline": "2030-12-31",
      "past_deadline": false,
      "retired": false,
      "theme_ids": ["uuid"],
      "shared": false,
      "flags": ["no_theme_in_focus", "no_usable_theme"]
    }
  ],
  "decisions": [
    {"project_id": "uuid", "name": "Open source", "decision": "carry|drop|replace|later", "replacement_project_id": "uuid|null", "replacement_name": "Talks|null"}
  ]
}
```

Rules:

- `themes` has one item per entry of the focus of the month, whether it is in the focus, swapped out or removed. An entry whose add was undone does not exist, so it is not here.
- `done` counts the milestones of the window of the entry (research R-05). `milestones` lists them. `earlier_not_counted` lists the ones done earlier in the month under the same theme, before `counts_from`.
- `marker` is `no_target` when `target` is null. With a target it is `missed` when `done < target`, `met` when equal and `beaten` when higher. A target of 0 is compared with 0, so 0 of 0 is `met`.
- `orphaned` is `null` or `{"reason": "missing|archived"}`. `label_changed` is `null` or the new label.
- `outside_focus` has `theme_project_id` and `theme_name` as null for the entry "no theme".
- `categories` holds the counts of feature 005 for the month, as read. No shares.
- `key_results` follows research R-07. `flags` uses `no_theme_in_focus` (this feature), `no_usable_theme` (006 rule and wording) and `past_deadline`. `shared` is true when more than one linked theme is in the focus of the month. `after_month_end` is true when the latest time stamp is after the last day of the month (a review done in a later month).
- `decisions` has one item per theme of `themes` that is not undone. A theme with no decision has `later`.

## Existing tables (unchanged)

- `goals`, `plans`, `period_reviews`: unchanged. The old month goal rows stay as read-only history. The old stored period review is not read or written by the new flow (FR-028, FR-035).
- `milestones` (004): read only (`state`, `done_on`, `done_theme_id`, `done_theme_name`, `project_id`).
- `weekly_plans`, `weekly_plan_projects`: read only, and only for the effect text of a change ("N weekly commitments under this theme stay as they are"). Never changed by a swap (FR-013).
- `key_results`, `key_result_values`, `key_result_themes`, `plan_changes` (006): read. The only write is one row in `key_result_values` per manual value typed in a review, through the 006 service (SC-008).
- Category storage of 005: read through the reader only.
- `project_labels`, `project_label_history` (003): read only.
- `checklists` for the month: unchanged (FR-034).

## Derived values (not stored)

- **State of a month**: `past`, `current` or `future` from the month and today in the user time zone.
- **Count note**: `below` (fewer than three themes, at least one), `empty` (none), `above` (more than five), or none. Guidance only (FR-002).
- **Result marker** of a theme: from `target` and `done` (above).
- **Outside focus** and **no theme**: from the done milestones and the entries (research R-05). Never stored on the milestone.
- **Key result flags** `no_theme_in_focus`: none of the usable linked themes (the links valid in the month, from the link history of 006) is in the focus. In the planning screen "in the focus" means entries still in the focus. In the review it means every entry of the month, so a swapped-out theme counts as in focus.
- **Update status** and **change** of a key result: research R-07.
- **Off-plan share** and **trend**: research R-09. Shares are never stored.
- **Suggestions** for a month: research R-10.
- **Last-month hint** of a theme: the number of milestones with `done_on` in the previous month and `done_theme_id` equal to the theme (FR-009).
- **Focus known** for weekly planning: a `monthly_focuses` row exists for the month.

## State changes

```text
(no row)   --save plan-------------------> focus saved       (entries, counts_from = month start)
entry      --swap / remove---------------> left              (left_on, left_reason; log row)
(none)     --swap in / add---------------> entry             (counts_from = day of change; log row)
entry      --target change---------------> entry             (log row with before and after)
change     --undo------------------------> reversed          (new log row, source undo)
month      --finish review---------------> snapshot v1       (series rows written for typed values)
snapshot   --reopen and finish-----------> snapshot v(n+1)   (current_version = n + 1)
snapshot   --make earlier current--------> same snapshots    (only current_version changes)
```

## Validation rules

- Target: whole number 0 or more, or none (R-03). Any other value gives `invalid_target`.
- A theme is in a focus at most once, also after it left (`left_this_month`, `duplicate_theme`).
- A theme in a focus must be a live theme per 003 when it is added (`not_a_theme`). It may become orphaned or relabelled later.
- A replacement theme of a decision is a live theme per 003 and not the theme itself (`not_a_theme`).
- A key result value: a finite number, for a key result that is not retired (006 rules).
- No field of this feature holds hours, duration or effort.
