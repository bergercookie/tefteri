# Data Model: Project Classification and Onboarding

Migration `0018_project_labels`. Models in `backend/src/tefteri/db/models/project_label.py`.

## `project_labels`

One row per project that Tefteri has ever seen in a task connection.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID, primary key | The public id of the project in the API. |
| `user_id` | UUID, FK `users.id`, cascade | Labels are private to the user (FR-019). |
| `connection_id` | UUID, FK `connections.id`, cascade | Per connection. |
| `remote_id` | string(255) | The project identity in the task app. Unique with `connection_id`. |
| `name` | string(255) | Last known title. Shown when the project is orphaned. |
| `parent_remote_id` | string(255), null | Last known parent. Used for ancestor rules. |
| `label` | string(16), null | `theme`, `milestone`, `maintenance`, `ignored`. Null means unclassified. This is a cache of the newest history entry. |
| `label_changed_at` | datetime, null | When the label last changed. |
| `orphaned_reason` | string(16), null | `missing` or `archived`. Null means the project is live. |
| `orphaned_at` | datetime, null | |
| `created_at` | datetime | |

Constraint: unique (`connection_id`, `remote_id`). Index on (`user_id`, `connection_id`).

## `project_label_history`

Append only. No update or delete in the code.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID, primary key | |
| `project_id` | UUID, FK `project_labels.id`, cascade | |
| `label` | string(16), null | The label from this moment. Null means "back to unclassified". |
| `from_at` | datetime | When it began. |
| `batch_id` | UUID, null | Groups the rows of one save, for undo. |
| `source` | string(16) | `user`, `suggestion` (accepted proposal), `undo`. |

The label on a given day is the entry with the latest `from_at` not after that day. Features 005 to 008 read this (FR-022).

## Existing tables (unchanged)

- `source_containers`: unchanged. Still the list of live, syncable projects. The sync writes `project_labels` next to it.
- `weekly_plan_projects`: unchanged. Its `name` already keeps the name of a removed project.

## Derived values (not stored)

- **Proposal**: `(label, reason)` per unclassified project. Pure function of depth and of whether the project was in a past weekly plan.
- **Parent theme** (FR-021): the nearest ancestor with label theme (using the effective label, which is the stored label or the proposal). None means "no theme".
- **Effective label**: the stored label, or the proposal when unclassified.
- **Eligible** (FR-007): live, effective label is not ignored, and no ancestor has effective label ignored.
- **Weekly-eligible** (FR-008): eligible and effective label is not maintenance.
- **Counts for the effect preview**: open tasks, subprojects, and whether the project is in a committed plan with no look-back.

## State changes

```text
unclassified --save/accept--> theme | milestone | maintenance | ignored
any label    --save--------> any other label        (adds a history entry)
live         --not listed--> orphaned(missing)       (sync)
live         --archive-----> orphaned(archived)      (user, with effect preview)
orphaned     --listed again-> live                   (sync)
orphaned(archived) --restore--> live                 (user; task app first)
```

## Capabilities (port level, not stored)

| Capability | Needed for | Required? | Vikunja |
|---|---|---|---|
| `SUBPROJECTS` | Milestones under themes | Required (at least two levels) | Yes |
| `PROJECT_TREE` | Read the whole tree and see what moved or was deleted | Required | Yes (`GET /projects`) |
| `STABLE_PROJECT_IDS` | Labels keyed on identity | Required | Yes (numeric project id) |
| `ARCHIVE_PROJECTS` | Close a milestone, archive | Required | Yes |
| `CREATE_TASKS` | Weekly planning | Required | Yes |
| `COMPLETION_TIMES` | Cadence and statistics | Required | Yes (`done_at`) |
| `RENAME_PROJECTS` | Rename from Tefteri | Optional | Added in this feature |
| `RESTORE_PROJECTS` | Undo of archive | Optional | Added in this feature |
| `MOVE_TASKS` | Close and return tasks (feature 004) | Optional | Added by feature 004 |
