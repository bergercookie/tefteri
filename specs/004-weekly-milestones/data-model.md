# Data Model: Weekly Planning and Review with Milestone Projects

Migration `0019_weekly_milestones` (revision `0019`, down revision `0018`). The numbers 0020 to 0023 are reserved for features 006, 005, 007 and 008. Models are in `backend/src/tefteri/db/models/milestone.py` (new) and `backend/src/tefteri/db/models/weekly.py` (changed).

## `milestones` (new)

One row per milestone project. Created lazily the first time the weekly flow touches a project. No row means: state `active`, rollover count 0, no done-state.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID, primary key | Public id of the milestone in the API. |
| `user_id` | UUID, FK `users.id`, cascade | Private to the user. Index. |
| `project_id` | UUID, FK `project_labels.id`, cascade | The milestone project (003). Unique. The row exists for an orphaned project too. |
| `done_state` | string(255), null | One sentence: "ship the login flow". Required when the milestone is created in the weekly flow (FR-009). Null for a project that was labelled outside this flow. |
| `state` | string(8), not null | `active`, `parked`, `closed`, `done`. Default `active`. |
| `state_changed_at` | datetime, not null | |
| `rollover_count` | integer, not null | Default 0. Raised only by a recommit decision. Never reset. |
| `done_on` | date, null | Local date it became done (FR-035). Set with `state = done`, cleared on reopen. |
| `done_by` | string(4), null | `auto` or `user`. |
| `done_theme_id` | UUID, FK `project_labels.id`, set null, null | Theme at the moment it became done. |
| `done_theme_name` | string(255), null | Copy of the theme name at that moment, so a rename or removal changes nothing. Null with no theme ("no theme"). |
| `created_at` | datetime | |

Constraint: unique (`project_id`). Index on (`user_id`, `state`).

Rules: `done_on`, `done_by` and `done_theme_*` are all set or all null together with `state = done`. A theme change never writes `done_theme_*` (FR-035). `rollover_count` equals the number of rows in `milestone_rollovers` of the milestone (a test keeps them equal).

## `milestone_rollovers` (new)

One row per recommit. Append only: the code never edits or deletes a row.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID, primary key | |
| `milestone_id` | UUID, FK `milestones.id`, cascade | Index. |
| `plan_project_id` | UUID, FK `weekly_plan_projects.id`, set null, null | The reviewed entry that made the decision. |
| `from_week` | date | Monday of the reviewed week. |
| `to_week` | date | Monday of the week it was recommitted to. |
| `expected` | boolean, not null | The marker of this one event: "this was bigger than a week" (FR-019, FR-029). Default false. |
| `created_at` | datetime, not null | Orders the events. |

## `milestone_closures` (new)

The log of one close and return. It makes the retry safe and the undo possible.

| Column | Type | Notes |
|---|---|---|
| `id` | UUID, primary key | |
| `milestone_id` | UUID, FK `milestones.id`, cascade | Index. |
| `plan_project_id` | UUID, FK `weekly_plan_projects.id`, set null, null | |
| `theme_project_id` | UUID, FK `project_labels.id`, set null, null | The project that got the tasks. |
| `theme_name` | string(255) | Copy, for the message. |
| `status` | string(8), not null | `moving`, `closed`, `reopened`. |
| `moved` | JSON, not null | List of `{"task_id": uuid, "remote_id": str, "from_remote_project": str, "version": str}`. One entry is appended after each successful move. `version` is the task version after the move. |
| `started_at` | datetime, not null | |
| `finished_at` | datetime, null | Set with `status = closed`. |
| `reopened_at` | datetime, null | |

## `weekly_plan_projects` (changed: the weekly commitment entry)

Old columns stay as they are (see `db/models/weekly.py`). New nullable columns:

| Column | Type | Notes |
|---|---|---|
| `milestone_id` | UUID, FK `milestones.id`, set null, null, index | Null for a legacy entry (a project that was not a milestone). |
| `theme_project_id` | UUID, FK `project_labels.id`, set null, null | The parent theme at the time of the commitment (FR-004). |
| `theme_name` | string(255), null | Copy of its name. Null means "no theme" or a legacy entry. |
| `decision` | string(12), null | `recommit`, `park`, `close`, `decide_later`. Null before the review and for legacy entries. |
| `expected_rollover` | boolean, null | The marker given with a `recommit` decision. Copied to the rollover event. |
| `decided_at` | datetime, null | |

New constraint: unique (`plan_id`, `milestone_id`) next to the old unique (`plan_id`, `container_id`). A milestone is in a week at most once (FR-014).

Old columns that new code stops writing: `leftover_action`. Old columns that new code still writes: `outcome` (`done` when the milestone is done, else `not_done`), `reviewed_committed`, `reviewed_done`, `committed_task_ids`, `parked_task_ids` (shown as "Not this week").

## Other existing tables

- `weekly_plans`: unchanged. `retro_skipped`, `reviewed_at` and `reflection` keep their meaning. The look-back still happens once per plan.
- `project_labels`, `project_label_history`: unchanged (003). The weekly flow writes labels only through `write_labels` (a pick of an unsorted leaf project writes the label milestone with source `user`).
- `tasks`: unchanged. A move writes `container_id` and `remote_version`.
- `goals` and the period review tables: unchanged and not read by the weekly flow.

## Derived values (not stored)

- **Decision of an entry**: `decision_of(decision, leftover_action)`. `recommit`, `park`, `close`, `decide_later` as stored; otherwise `carry` gives `recommit`, `backlog` gives `park`, nothing gives none.
- **Milestone count and over cap**: rows of the plan with a `milestone_id`; over cap when more than 3.
- **Nudge**: `needs_rescope(events)` is true when the two newest `milestone_rollovers` rows have `expected = false`.
- **Decision open**: the newest entry of the milestone that has a decision has `decision = decide_later`.
- **Outside focus**: the theme of the entry is not in `FocusProvider.themes_for_month(month_of_week(week_start))`. Always false when the provider returns `None`.
- **Focus share**: completed committed tasks under a focus theme divided by completed committed tasks. `None` when there is no focus data or no completed task.
- **Pace**: completions of committed tasks per local day of the week.
- **Close availability**: `close_options(has_theme, theme_usable, can_move)`.
- **Commit kind** of a project: `milestone`, `label_then_commit` or none (research R-05).
- **Parent theme**: from `domain.classification.parent_theme` (003).

## State changes

```text
(no row) --first weekly use--------> active
active   --review: park------------> parked          (rollover_count unchanged)
parked   --committed again---------> parked          (state changes only by a decision or by done)
active   --review: recommit--------> active          (rollover_count + 1, one rollover event)
active   --review: decide later----> active          (nothing changes)
active   --close and return--------> closed          (after every move worked)
closed   --reopen-------------------> active         (tasks moved back where unchanged)
active | parked --all tasks closed or dropped, one closed--> done   (auto; done_on, theme at done)
active | parked --user marks done--> done            (done_on = today; open tasks stay)
done     --reopen------------------> active          (done fields cleared)
```

A committed milestone that is parked stays parked until a review decision or a done event changes it. The picker offers `active` and `parked` milestones. It never offers `closed` or `done` ones.

## Capabilities (port level, not stored)

| Capability | Needed for | Required? | Vikunja |
|---|---|---|---|
| `MOVE_TASKS` | Close and return tasks, and its undo | Optional | Added by this feature. The adapter changes `project_id` of the task and reads it back. |

All other capabilities are from 003. The close option is hidden when `MOVE_TASKS` is missing.

## Legacy rows

| Stored | Shown as |
|---|---|
| `leftover_action = 'carry'`, `decision` null | Keep and recommit |
| `leftover_action = 'backlog'`, `decision` null | Keep but park |
| `leftover_action` null, `decision` null | No decision |
| `milestone_id` null | Legacy project: name, counts and outcome only |
