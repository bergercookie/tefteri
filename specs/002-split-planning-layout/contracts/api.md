# API Contract Delta (v1): Split Planning Layout

Delta on spec 001 `contracts/api.md`. Base path `/api/v1`. The OpenAPI document
(`just backend::openapi` → `docs/openapi.json`) is the authority; a test fails if it is stale.

## Tasks

### `GET /tasks` — new parameters
| Parameter | Values | Meaning |
|-----------|--------|---------|
| `due` | `today`, `tomorrow`, `week`, `all`, `none`, `overdue` (default `all`) | Filter open tasks by planned time in the user's time zone. |
| `q` | text | Case-insensitive title match over all open tasks. When set, `due` is ignored. |

`status` defaults to `open` when `due` or `q` is used. `context`, `goal_id`, `from`, `to`
keep their meaning. `unscheduled=true` stays and means `due_at` is null. Task objects keep
`scheduled_start` and `scheduled_end`; they are derived from `due_at` (data model).

### `GET /tasks/counts`
Query: `context`. Response: `{"today": n, "tomorrow": n, "week": n, "all": n, "none": n,
"overdue": n}` — open tasks, same rules as the `due` filter, for the filter badges (FR-018).

### `PUT /tasks/{id}/schedule` — changed
Exactly one of these bodies:

| Body | Effect |
|------|--------|
| `{"start": "<datetime>"}` | Block starts at `start`; stores `due_at = start + 1h`. `start` is rounded to the 15-minute mark. |
| `{"date": "YYYY-MM-DD"}` | Date-only drop. Default: stores an all-day due date. If the user's `random_time_on_date_drop` is true: stores a timed due (random start 08:00–19:45 local, 15-minute mark, due = start + 1h). |

The old `end` field is removed. Sending both or neither of `start` and `date` gives 422.
Response `200` (unchanged shape): `{"task": TaskOut, "overlaps": [EntryOut]}`; `overlaps` lists
calendar entries that intersect the derived block (empty for all-day).
Errors: `404`; `409 remote_conflict` (conflict recorded); `502 backend_unavailable` and
`401/403 auth_expired` with `connection` name and reason, as in spec 001 FR-019. On any error
the cached task is unchanged.

### `DELETE /tasks/{id}/schedule` — unchanged URL
Clears `due_at` in the task app. Response: `TaskOut`.

## Calendar

### `GET /calendar` — changed
Tasks come from `due_at`. Each task item has `type: "task"`, and either
`start`/`end` (timed block, with `clipped_start` when it continues from the previous day) or
`all_day: true` with `start` set to the date at 00:00 in the user's time zone. Calendar entries
are unchanged.

## Settings

### `GET /me/settings`, `PATCH /me/settings`
Body and response: `{"random_time_on_date_drop": false}`. Per user; no admin rights needed.
Unknown fields give 422.
