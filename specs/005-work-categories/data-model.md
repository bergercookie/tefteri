# Data Model: Work Categories and Statistics

Migration `0021_work_categories` (revision `0021`, down revision `0020`). The numbers are reserved: 0019 feature 004, 0020 feature 006, 0021 this feature, 0022 feature 007, 0023 feature 008. Models in `backend/src/tefteri/db/models/task_category.py` (new). Pure rules in `backend/src/tefteri/domain/work_categories.py` (new). Names of entities that other features own are copied from their design files: `project_labels` and `project_label_history` (003), `weekly_plans`, `weekly_plan_projects`, `milestones` (004).

## `task_categories` (new)

One row per task that was seen as completed. It is written by the recorder when the task is first seen as completed (R-02), replaced in place when a reopened task is completed again (R-08), and never edited otherwise.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID, primary key | |
| `user_id` | UUID, FK `users.id`, cascade | Private to the user. |
| `task_id` | UUID, FK `tasks.id`, cascade | The task. Unique. |
| `completed_at` | datetime with zone | The completion time that this row was decided for. Compared with `tasks.completed_at`: a row counts only when they are equal. |
| `completed_on` | date | The local day of `completed_at` in the time zone of the user at the moment of the decision. Stored, never recomputed (R-09). |
| `category` | string(12), not null | `goal_aligned`, `maintenance`, `off_plan` or `hidden`. `hidden` is not a work category: it is the ignored count (FR-008). |
| `reason` | string(24), not null | Why. One of the reason codes below. |
| `unsorted` | boolean, not null | True for an unclassified project and for no project (FR-005). |
| `project_id` | UUID, FK `project_labels.id`, set null, null | The project the task was in when it was completed. Null for no project. |
| `project_name` | string(255), null | Copy of the name at the decision. Shown when the project is orphaned or renamed. |
| `project_label` | string(16), null | The label the project had on the completion day (read from the history). Null means unclassified or no project. |
| `plan_id` | UUID, FK `weekly_plans.id`, set null, null | The committed plan that made the task goal-aligned. Null for every other result. |
| `decided_via` | string(8), not null | `sync` or `app` (completed in tefteri). |
| `decided_at` | datetime, not null | When tefteri saw the completion. |

Constraints: unique (`task_id`). Check `category IN ('goal_aligned','maintenance','off_plan','hidden')`. Indexes: (`user_id`, `completed_on`, `category`) for the counts; (`user_id`, `category`, `completed_at`) for the lists; (`project_id`).

Reason codes (`CategoryReason`):

| Code | Category | Meaning |
|---|---|---|
| `committed_milestone` | goal_aligned | Milestone project in the committed plan of the completion week. |
| `maintenance_label` | maintenance | The project is labelled maintenance on the completion day. |
| `inside_routine` | maintenance | An ancestor is labelled maintenance (decision 10, FR-029). |
| `milestone_not_committed` | off_plan | Milestone project, not in the commitment of that week. |
| `theme` | off_plan | Theme project (never committed). |
| `unclassified` | off_plan | The project has no label. `unsorted` is true. |
| `no_project` | off_plan | The task has no project. `unsorted` is true. |
| `ignored` | hidden | The project is labelled ignored. |
| `ignored_ancestor` | hidden | An ancestor is labelled ignored. |

## Existing tables (unchanged)

- `tasks`: unchanged. `completed_at`, `status`, `container_id`, `sync_state` are read. A task with `sync_state = deleted_remotely` does not count; its category row stays (R-07).
- `project_labels`, `project_label_history` (003): read only. The recorder reads the history for the label on a day and the `parent_remote_id` links.
- `weekly_plans`, `weekly_plan_projects`, `milestones` (004): read only through `CommitmentProvider`.
- `sync_runs`: read for "last synced".
- `users.timezone`: read when the row is decided.
- `goals`: not read (FR-023).

## Value objects (domain, not stored)

```text
CategoryCounts(goal_aligned: int, maintenance: int, off_plan: int, hidden: int)
    total      = goal_aligned + maintenance + off_plan        (hidden is not in the total)
    __add__    = field by field sum                           (month = sum of days)
LabelEntry(label: ProjectLabel | None, from_at: datetime)
ProjectContext(label_on_day, ancestor_labels_on_day: list[ProjectLabel | None], has_project: bool)
Decision(category: WorkCategory, reason: CategoryReason, unsorted: bool)
```

## Derived values (not stored)

- **Label on a day**: `label_on(entries, day_end)`. The entry with the latest `from_at` not after `day_end`. If every entry starts later, the oldest entry. No entries: unclassified.
- **Decision**: `categorize(context, committed)`, the rule order of research R-06.
- **Counts of a day, week, month, year**: grouped query by `completed_on` and `category` over rows that count (task done, `task_categories.completed_at = tasks.completed_at`, not deleted remotely). Week = sum of 7 days. Month = sum of its days. Year = sum of its 12 months.
- **Percentages**: `percentages(counts)` by the largest remainder method over the three categories. All zero when the total is zero. Never stored.
- **Empty reason**: `no_tasks` (no counted task and no hidden task) or `no_labels` (also no project has a label).
- **Unsorted count** of a period: counted rows with `unsorted = true`.
- **Week progress** (`domain/week_progress.py`): committed, done, done before, undated, after, done by day, cadence, needed per day, on track, remaining and ideal per day, scope. Ported from `week_progress.dart` (R-12).
- **Last synced**: the newest finished `sync_runs` row of the task connections of the user, and its outcome.

## State changes

```text
(no row) --task first seen done, completion time known--> row (category decided, never edited)
row      --task reopened-------------------------------> row stays, does not count (task is open)
row      --task completed again (new completion time)--> row replaced in place (new decision)
row      --task deleted in the task app, next sync------> row stays, does not count
row      --label changed, plan edited, project moved, project orphaned, re-sync--> no change
```

## Validation rules

- `category` and `reason` are members of the enums. The pair must be allowed by the table above (a unit test checks every pair that `categorize` can return).
- `unsorted` is true only with the reasons `unclassified` and `no_project`.
- `plan_id` is set only with `committed_milestone`.
- `completed_on` is the local day of `completed_at` in the time zone that was set when the row was written.
- A done task with no completion time gets no row and is counted nowhere (the week of it is not known). This is the behaviour of the list today, and the docs say it (research open point 6 of the plan).

## Capabilities (port level, not stored)

None new. `COMPLETION_TIMES` is already a required capability of 003. This feature adds no operation to `TaskBackend`.
