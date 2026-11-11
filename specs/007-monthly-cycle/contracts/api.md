# API Contract Delta (v1): Monthly Planning and Review

Base path `/api/v1`. The OpenAPI document (`just backend::openapi` → `docs/openapi.json`) is the authority. A snapshot test fails if it is stale. All routes need a signed-in user and only see that user's data (FR-039): an id of another user answers 404. Errors have the shape of the rest of the API: `{"detail": "message", "code": "..."}`.

`{month}` is `YYYY-MM`. A malformed month answers 422 `invalid`. The month starts and ends in the user time zone (research R-13).

## Error codes used here

| Code | Status | When |
|---|---|---|
| `not_found` | 404 | An id or a project that is not the user's. |
| `invalid` | 422 | Generic refusal (existing). |
| `invalid_target` | 422 | A target that is negative, a decimal, text or a boolean. `detail` says "A target is a whole number of milestones, 0 or more. Leave it empty for no target." |
| `not_a_theme` | 422 | A project that is not a live theme per 003 was named (milestone, maintenance, ignored, unclassified, orphaned), also as a replacement. |
| `duplicate_theme` | 422 | The same theme twice in one request. |
| `already_in_focus` | 409 | A change adds a theme that is in the focus. |
| `left_this_month` | 409 | A change adds a theme that left this month. `detail` says to undo that change. |
| `not_in_focus` | 422 | A change swaps, removes or retargets a theme that is not in the focus. |
| `use_changes` | 409 | A plan save of a month in progress changes the members of an existing focus. |
| `past_month` | 409 | A plan save for a past month. |
| `not_current_month` | 409 | A mid-month change in a month that is not the current one. |
| `future_month` | 409 | A review of a future month. |
| `confirm_required` | 422 | Saving a new version of a stored review without `confirm_new_version: true`. |
| `no_such_version` | 404 | A version that does not exist. |
| `not_undoable` | 409 | The undo would clash with a later change of the same theme. |
| `already_undone` | 409 | The batch was undone already. |
| `retired` | 409 | A value for a retired key result (error of 006, passed through). |

## 1. Planning

### `GET /monthly/{month}`

The whole planning screen of one month.

```json
{
  "month": "2030-03",
  "start": "2030-03-01",
  "end": "2030-04-01",
  "state": "past|current|future",
  "planning_year": 2030,
  "focus_known": true,
  "count_note": "below|above|empty|null",
  "entries": [
    {
      "id": "uuid",
      "project_id": "uuid",
      "connection_id": "uuid",
      "name": "Open source",
      "target": 3,
      "counts_from": "2030-03-01",
      "left_on": null,
      "status": "in_focus|swapped_out|removed",
      "done": 2,
      "earlier_not_counted": 0,
      "marker": "met|missed|beaten|no_target|null",
      "orphaned": null,
      "label_changed": null,
      "linked_key_results": 2,
      "last_month_done": 3
    }
  ],
  "key_results": [
    {
      "id": "uuid",
      "goal_id": "uuid",
      "goal_title": "Get better at open source",
      "metric": "Stars on one repository",
      "start_value": 120,
      "current_value": 220,
      "current_at": "datetime|null",
      "target": 500,
      "deadline": "2030-12-31",
      "update_source": "manual|automatic",
      "past_deadline": false,
      "theme_ids": ["uuid"],
      "flags": [
        {"code": "no_theme_in_focus", "actions": ["open_picker"]},
        {"code": "no_usable_theme", "reasons": [{"project_id": "uuid|null", "name": "Open source", "state": "no_links|orphaned|ignored|relabelled|unclassified"}], "actions": ["open_annual_plan"]}
      ]
    }
  ],
  "themes_without_key_result": ["uuid"],
  "review": {"stored": false, "current_version": null, "versions": 0},
  "earlier_format": false
}
```

- `focus_known` is false when the month has no saved plan. `entries` is then empty and `suggestions` come from `GET /monthly/{month}/suggestions`.
- `entries` holds the entries in the focus first, then the swapped-out and removed ones. `done`, `earlier_not_counted` and `marker` follow research R-05. `marker` is null for a future month.
- `orphaned` is `null` or `{"reason": "missing|archived", "at": "datetime"}`. `label_changed` is `null` or the new label (`milestone|maintenance|ignored|null`).
- `key_results` holds the key results of the planning year that are linked to an entry (with `theme_ids`) and the ones that carry a flag. The `no_usable_theme` flag has the codes, reasons and wording of 006 and points to the annual plan (FR-008). The monthly screen offers no link control. `no_theme_in_focus` is quiet (FR-007).
- `themes_without_key_result` lists the entries marked "not linked to a key result" (scenario 5 of user story 3).
- `review.stored` is true when a current snapshot exists.
- `earlier_format` is true when the month has old month goal rows (read them with `GET /goals/history?period_type=month&period_start=YYYY-MM-01`, feature 006).

### `GET /monthly/{month}/themes`

The theme picker. Query: `q` (search text, optional), `connection_id` (optional).

```json
{
  "themes": [
    {"project_id": "uuid", "connection_id": "uuid", "connection_name": "My Vikunja", "name": "Open source",
     "in_focus": false, "left_this_month": false, "last_month_done": 3, "key_result_ids": ["uuid"]}
  ],
  "unsorted_count": 5,
  "task_connections": [{"id": "uuid", "name": "My Vikunja", "can_create": true}]
}
```

Only projects that are eligible as themes per 003 are listed (live, label theme, not ignored, no ignored ancestor). Milestone, maintenance, ignored, orphaned and unclassified projects are never listed (scenario 1 of user story 1). The list is sorted by name and grouped by connection by the client. For "Label a project as theme" the client uses `GET /projects/classification` and `PUT /projects/labels` (003). For "Create a theme" it uses `POST /annual/themes` (006). This feature adds no label route and no create route (research R-14).

### `GET /monthly/{month}/suggestions`

```json
{
  "from_month": "2030-02",
  "suggestions": [
    {"project_id": "uuid", "name": "Open source", "target": 3, "reason": "carry|replace", "replaces": {"project_id": "uuid", "name": "Admin"}}
  ],
  "skipped": [{"project_id": "uuid", "name": "Old theme", "reason": "orphaned|relabelled|ignored"}]
}
```

Built from the newest current snapshot of an earlier month (research R-10). `from_month` is `null` and both lists are empty when there is none. `replaces` is `null` for `carry`. A suggestion is never saved (FR-010).

### `PUT /monthly/{month}/focus`

Saves the plan of the month.

Body:

```json
{"entries": [{"project_id": "uuid", "target": 3}, {"project_id": "uuid", "target": 0}, {"project_id": "uuid", "target": null}], "dry_run": false}
```

`target` is a whole number, 0 or more, or `null` for no target. The schema accepts any JSON type so that the refusal has the code `invalid_target`.

- `dry_run=true` writes nothing and returns the effect: `{"effect": {"added": [...], "removed": [...], "targets_changed": [...], "message": "..."}, "count_note": "below|above|empty|null"}`.
- `dry_run=false` writes, creates the focus row when it is missing, and returns `{"focus": <as in GET /monthly/{month}>, "count_note": "..."}`.
- An empty list saves an empty focus (scenario 4 of user story 1). The note is `empty`. It does not block.
- Six or more entries save and the note is `above` (scenario 3). One or two give `below`.
- For a month in progress with a saved focus, only the targets of entries that are in the focus may change. A change of the members answers 409 `use_changes`.
- The first save of a month in progress sets `counts_from` to the first day of the month (research R-05).
- Errors: 404 for a project that is not the user's, 422 `not_a_theme`, 422 `duplicate_theme`, 422 `invalid_target`, 409 `past_month`.
- Nothing is created or changed in the task app (FR-005, SC-008).

## 2. Changing the focus during the month

### `POST /monthly/{month}/changes`

Body:

```json
{"kind": "swap|add|remove|target", "out_project_id": "uuid|null", "in_project_id": "uuid|null", "target": 2, "dry_run": true}
```

- `swap` needs `out_project_id` and `in_project_id`. `add` needs `in_project_id`. `remove` needs `out_project_id`. `target` needs `out_project_id` (the theme) and `target`.
- `target` is the target of the theme that comes (`swap`, `add`) or the new target (`target`). Rule R-03 applies.
- `dry_run=true` writes nothing and returns the effect:

```json
{
  "effect": {
    "counts_from": "2030-03-14",
    "finished_earlier_in_month": 1,
    "finished_earlier": [{"milestone_id": "uuid", "name": "Fix the CI", "done_on": "2030-03-02"}],
    "weekly_commitments_unchanged": 2,
    "out_keeps_results": true,
    "message": "The target of Open source counts from 14 March. 1 milestone that it finished earlier is shown in the review and does not count. 2 weekly commitments under Admin stay as they are."
  }
}
```

- `dry_run=false` applies the change and answers `{"batch_id": "uuid", "effect": {...}, "focus": <as in GET /monthly/{month}>}`. It writes the log row and updates the entries. It never changes a weekly commitment, a milestone or a stored snapshot (FR-013).
- Errors: 404, 422 `not_a_theme`, 422 `not_in_focus`, 422 `invalid_target`, 409 `already_in_focus`, 409 `left_this_month`, 409 `not_current_month`.

### `POST /monthly/{month}/changes/undo`

Body: `{"batch_id": "uuid"}`. Reverses one change (research R-02) and returns `{"undone": "swap|add|remove|target", "focus": <as in GET /monthly/{month}>}`. 404 for a batch that is not the user's, 409 `already_undone`, 409 `not_undoable`.

### `GET /monthly/{month}/history`

```json
{"month": "2030-03", "changes": [
  {"batch_id": "uuid", "kind": "swap", "on": "2030-03-14", "out_name": "Admin", "in_name": "Open source",
   "target_before": null, "target_after": 2, "source": "user|undo", "undone": false, "can_undo": true}
]}
```

Oldest first. `can_undo` is false for an undone change, for an undo row and for a change that a later change makes impossible to undo.

## 3. Review

### `GET /monthly/{month}/review`

Query: `version` (optional integer).

With a stored review and no `version`, it returns the current stored snapshot. With `version`, that version. Without a stored review it returns the live draft. Nothing is stored by this call.

```json
{
  "month": "2030-03",
  "stored": true,
  "draft": false,
  "version": 2,
  "current_version": 2,
  "taken_at": "datetime|null",
  "versions": [{"version": 1, "taken_at": "datetime", "current": false}, {"version": 2, "taken_at": "datetime", "current": true}],
  "snapshot": {"...": "the payload of data-model.md"},
  "trend": {
    "state": "rising|not_rising|not_enough_history",
    "previous": [{"month": "2030-02", "share": 0.12}, {"month": "2030-01", "share": 0.1}],
    "share": 0.2,
    "note": "string|null"
  },
  "categories_note": "no_data|null"
}
```

- For a stored snapshot every figure comes from the payload. `trend.share` and `previous[].share` are computed on read from stored counts (the snapshot) and from the 005 reader for the earlier months. They are never stored.
- For a draft (`stored: false`), `snapshot` is built live from the data as described in research R-05, R-07 and R-08, with `decisions` all `later`. `taken_at` is null. The screen labels it a draft (FR-031).
- A future month answers 409 `future_month`.
- The shares are in 0 to 1. `null` when the month has no completed task (the section shows its empty state, scenario 4 of user story 7).

### `POST /monthly/{month}/review`

Finish the review (or reopen and save a new version).

Body:

```json
{
  "key_result_values": [{"key_result_id": "uuid", "value": 220}],
  "decisions": [
    {"project_id": "uuid", "decision": "carry|drop|replace|later", "replacement_project_id": "uuid|null"}
  ],
  "confirm_new_version": false,
  "dry_run": false
}
```

- `key_result_values` is optional. A key result with a manual source may be skipped (scenario 3 of user story 6). A value for a key result of any planning year is accepted. An automatic key result takes a value too (006 allows it). A retired one answers 409 `retired`.
- `decisions` may omit a theme. A theme with no decision is stored as `later` (scenario 4 of user story 8). `replace` needs `replacement_project_id`, a live theme (`not_a_theme`) that is not the theme itself.
- `dry_run=true` writes nothing and returns `{"snapshot": <payload as it would be stored>, "effects": [{"project_id": "uuid", "decision": "carry", "message": "Open source will be offered next month with the target 3."}], "will_create_version": 2}`. The figures include the typed values.
- `dry_run=false` writes the typed values into the series of 006 (source `manual`, date of today, skipped when equal to the latest value of today), builds the payload with the same function as the dry run, adds snapshot version n + 1 and sets `current_version`, all in one transaction. Answer 201: `{"version": 2, "snapshot": {...}, "values_written": [{"key_result_id": "uuid", "value_id": "uuid"}]}`.
- When a snapshot exists and `confirm_new_version` is not true: 422 `confirm_required`, with `detail` "Saving creates a new version. The old version stays in the history." (scenario 3 of user story 9, FR-030).
- Nothing is changed in the task app. The only write outside this feature's tables is the series row of a typed value (SC-008).
- Errors: 404, 409 `future_month`, 409 `retired`, 422 `invalid` (a value that is not a finite number), 422 `not_a_theme`, 422 `confirm_required`.

### `POST /monthly/{month}/review/current`

Body: `{"version": 1, "dry_run": false}`. Makes an earlier version current again (FR-030). `dry_run=true` returns `{"message": "Version 1 becomes the current version. Version 2 stays in the history."}`. Otherwise it sets `current_version` and returns the review as `GET /monthly/{month}/review`. 404 `no_such_version`. This is also the undo of a saved version (FR-044).

### `GET /monthly/snapshots`

Read contract for feature 008. Query: `year` (integer, required).

```json
{"year": 2030, "snapshots": [{"month": "2030-03", "version": 2, "taken_at": "datetime", "snapshot": {"...": "the payload"}}]}
```

One item per month of the year that has a stored review: the current version, oldest month first. Stored values only. Nothing is calculated (FR-032). Feature 008 calls `MonthlyReviewService.current_snapshots` in process and does not use this route.

## 4. Existing routes that this feature reads or leaves alone

- `GET /views/month/{day}` stays. The client of this feature does not call it. 006 removes its `goals` field. Old month goal rows are read with `GET /goals/history` (006). No route creates, edits or deletes a month goal (FR-035).
- `GET /checklists/month/{day}` and its write routes are unchanged (FR-034).
- `GET /weekly/{day}` and `GET /weekly/{day}/candidates` and `/themes` (004) change in their data only: `focus_known`, `in_focus` and `outside_focus` now carry values from the saved focus. Their shape is unchanged.
- `POST /annual/key-results/{id}/values`, `GET /annual/{year}` and `POST /annual/themes` (006), and `GET /projects/classification` and `PUT /projects/labels` (003) are used as they are.

## Capability flags

None. This feature adds no port operation and no capability, and no adapter changes.

## Removed

Nothing is removed from the API. The client stops calling `GET /views/month/{day}` (`monthView` leaves `frontend/lib/core/planning_api.dart`).
