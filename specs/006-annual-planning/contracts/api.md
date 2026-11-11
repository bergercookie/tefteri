# API Contract Delta (v1): Annual Planning

Base path `/api/v1`. The OpenAPI document (`just backend::openapi` → `docs/openapi.json`) is the authority. A snapshot test fails if it is stale. All routes in sections 1 to 3 need a signed-in user and only see that user's data. Section 4 is the inbound push, which uses its own token.

## 1. Reading the plan

### `GET /annual/{year}`

Returns the whole plan of one planning year. A year with no goals returns `goals: []`.

```json
{
  "year": 2027,
  "state": "future",
  "editable": true,
  "goals": [
    {
      "id": "uuid",
      "title": "Get better at open source",
      "status": "active",
      "legacy_done": false,
      "criteria_suggestion": "Two talks and 100 stars",
      "progress": 0.4,
      "flags": [{"code": "no_key_result", "actions": ["add_key_result"]}],
      "notes": ["duplicate_metric"],
      "updated_at": "datetime",
      "key_results": [
        {
          "id": "uuid",
          "goal_id": "uuid",
          "metric": "Stars on one repository",
          "start_value": 120,
          "target": 500,
          "deadline": "2027-12-31",
          "update_source": "manual|automatic",
          "status": "active|retired",
          "current_value": 220,
          "current_at": "datetime|null",
          "progress": 0.263,
          "met": false,
          "retired_at": null,
          "flags": [
            {"code": "no_usable_theme", "reasons": [{"project_id": "uuid|null", "name": "Open source", "state": "no_links|orphaned|ignored|relabelled|unclassified", "label": "milestone|null"}], "actions": ["link_theme", "create_theme"]},
            {"code": "overdue", "actions": ["update_value"]}
          ],
          "links": [
            {"id": "uuid", "project_id": "uuid", "name": "Open source", "active": true, "usable": true, "state": "ok|orphaned|ignored|relabelled|unclassified", "label": "theme", "started_at": "datetime", "ended_at": null}
          ]
        }
      ]
    }
  ],
  "retired_goals": [],
  "theme_usage": [{"project_id": "uuid", "name": "Open source", "key_result_ids": ["uuid"]}]
}
```

- `state` is `past`, `current` or `future`. `editable` is false in a past year (FR-033).
- `goals` holds active goals. `retired_goals` holds retired goals in the same shape, for the history part of the screen. A retired key result stays inside its goal with `status: "retired"` and no flags.
- `legacy_done` is true for a year goal that was marked complete before annual planning.
- `criteria_suggestion` is the old criteria text while the goal has no key result, else `null`.
- `links` holds the active links and, for history, the ended ones (`active: false`).
- `usable` and `state` follow the usable-link rule of feature 003 (research R-12). A link to a theme that is now milestone, maintenance or ignored has `active: true` and `usable: false`.
- `flags` are warnings only. They never change the status code of any other route (FR-014).
- `notes` holds quiet hints: `duplicate_metric`.
- `theme_usage` is the reverse view: each theme with the key results it serves (US2, scenario 3).
- This response is the read contract for features 007 and 008 (FR-030).

### `GET /annual/{year}/history`

The changes of the year in time order, oldest first. Query: `goal_id`, `key_result_id` (optional filters).

```json
{"year": 2027, "changes": [
  {"id": "uuid", "kind": "key_result_retired", "goal_id": "uuid", "key_result_id": "uuid", "field": null, "old_value": null, "new_value": null, "reason": "Too ambitious", "batch_id": "uuid", "source": "user", "at": "datetime", "undone": false}
]}
```

`undone` is true when a later `undo` row of the same `batch_id` exists. Undo stays available in the history for each batch that is not undone and whose year is not past.

### `GET /goals/history`

Read only. Replaces `GET /goals`. Returns the legacy goal rows: all `month` and `week` rows and the year rows that are retired or marked complete, with parent links and the number of tasks linked. Query: `period_type`, `period_start` (optional). No write route exists for these rows (FR-023).

```json
[{"id": "uuid", "parent_id": "uuid|null", "period_type": "month", "period_start": "2026-11-01", "title": "Run 100 km", "description": "", "criteria": "", "status": "active|done|dropped", "linked_tasks": 3}]
```

### `GET /annual/key-results/{id}/value-on`

Query `date=YYYY-MM-DD`. The last value of the series with `on_date` on or before the date (FR-034).

```json
{"key_result_id": "uuid", "date": "2027-02-01", "value": 150, "at": "datetime", "source": "manual|automatic"}
```

When no value exists on or before the date: `{"key_result_id": "uuid", "date": "2027-02-01", "value": null, "at": null, "source": null}`. The start value is not assumed. Feature 007 calls the same function in process (`KeyResultService.value_on`). This feature does not push data to other features.

### `GET /annual/key-results/{id}/values`

The full series, newest first: `[{"id": "uuid", "value": 220, "at": "datetime", "on_date": "2027-03-04", "source": "manual", "seq": 3}]`. Allowed in a past year.

## 2. Changing the plan

Every route here answers 409 `past_year` for a year in the past (value routes excepted), 404 for an id that is not the user's, and 422 for a value that breaks a rule. No flag and no limit blocks a save except the three rules in the next list. Each change adds `plan_changes` rows.

- `409 key_result_limit`: the goal already has three active key results (FR-003). The message says: "A goal can have three key results. Retire one first."
- `422 invalid`: target equals start, a value that is not a finite number, a deadline outside the planning year, an empty text (FR-005). The message names the field.
- `409 past_year`: see above.

### `POST /annual/{year}/goals/bulk`

Creates goals, each with optional key results and links, in one transaction and one batch. All or none. Used for "write several goals", for the first save of a new plan, and to accept suggestions.

```json
{
  "seeded_from": 2026,
  "goals": [
    {
      "title": "Get better at open source",
      "seeded_from_goal_id": "uuid|null",
      "key_results": [
        {"metric": "Stars on one repository", "start_value": 220, "target": 500, "deadline": "2027-12-31", "update_source": "manual", "seeded_from_key_result_id": "uuid|null", "theme_ids": ["uuid"]}
      ]
    }
  ]
}
```

Response 201: `{"batch_id": "uuid", "goals": [<goal as in GET /annual/{year}>]}`. `seeded_from` and the `seeded_from_*` fields are optional. A theme id that is not an eligible theme gives 422 `not_a_theme`. More than three key results in one goal gives 409 `key_result_limit` and nothing is stored. Nothing of year N is written (FR-017).

### `PATCH /annual/goals/{goal_id}`

Body: `{"title": "New sentence"}`. Response: the goal. Adds `goal_edited` with the old and the new title (FR-019).

### `POST /annual/goals/{goal_id}/key-results`

Body: `{"metric": "...", "start_value": 120, "target": 500, "deadline": "2027-12-31", "update_source": "manual", "theme_ids": []}`. Response 201: the key result. The series is empty and `current_value` equals `start_value` (FR-006). 409 `key_result_limit` for a fourth active key result.

### `PATCH /annual/key-results/{id}`

Body: any of `metric`, `target`, `deadline`, `update_source`. Response: the key result. Each changed field adds one `key_result_edited` row with the old and the new value (FR-018, FR-019). `start_value` is not editable here (the series keeps its meaning). A retired key result answers 409 `retired`.

### `POST /annual/goals/{goal_id}/retire` and `POST /annual/key-results/{id}/retire`

Body: `{"reason": "optional text", "dry_run": false}`.

- `dry_run=true` writes nothing and returns the effect: `{"effect": {"key_results_retired": 2, "links_ended": 3, "flags_removed": ["no_usable_theme"], "history_kept": true}}`.
- `dry_run=false` retires (a goal retires all its active key results, FR-021), ends their links with `end_reason`, and answers `{"batch_id": "uuid", "effect": {...}}`. Retiring does not change any stored period review (FR-020).
- 409 `already_retired` if it is retired already.

### `POST /annual/goals/{goal_id}/restore` and `POST /annual/key-results/{id}/restore`

Restores the item. A goal restore restores the key results that its retirement batch retired. A key result restore needs a free slot (409 `key_result_limit` otherwise). Links that ended in the same batch start again as new rows, but only for themes that are still eligible; the response lists the skipped ones: `{"restored": 1, "links_restored": 2, "links_skipped": [{"project_id": "uuid", "name": "Old", "state": "orphaned"}]}`.

### `PUT /annual/key-results/{id}/themes`

Sets the active links of a key result to the given list. The server adds the missing ones and ends the ones that are not in the list, in one batch (a re-link is a removal and an addition in the same batch).

Body: `{"theme_ids": ["uuid", "uuid"], "dry_run": false}`.

- `dry_run=true` returns `{"effect": {"added": [{"project_id": "uuid", "name": "A"}], "ended": [{"project_id": "uuid", "name": "B"}], "flags_removed": [], "flags_added": []}}`.
- `dry_run=false` writes and returns `{"batch_id": "uuid", "key_result": <key result>}`.
- 422 `not_a_theme` for a project that is not a live theme of the user (not labelled theme, orphaned, or ignored, or an unclassified project). 404 for an id that is not the user's. A retired key result answers 409 `retired`.

### `POST /annual/undo`

Body: `{"batch_id": "uuid"}`. Reverts one batch: a retire, a re-link, a link removal, or a goal retire (key results included). It adds new history rows with `source = undo`. Response: `{"restored": 3}`. 404 for a batch that is not the user's, 409 `already_undone`, 409 `past_year`, and 409 `key_result_limit` when a restore finds no free slot (nothing is changed then).

## 3. Themes, values and the push token

### `GET /annual/themes`

The theme picker (FR-012). It lists the projects that are eligible per feature 003 and have the stored label `theme`.

```json
{
  "themes": [{"project_id": "uuid", "connection_id": "uuid", "connection_name": "My Vikunja", "name": "Open source", "key_result_ids": ["uuid"]}],
  "unsorted_count": 5,
  "task_connections": [{"id": "uuid", "name": "My Vikunja", "can_create": true}]
}
```

Milestone, maintenance, ignored, unclassified and orphaned projects are not listed. `unsorted_count` drives the quiet note "Unsorted projects can be classified first". For the inline action "Label a project as theme" the client uses `GET /projects/classification` and `PUT /projects/labels` of feature 003. This feature adds no label route.

### `POST /annual/themes`

Body: `{"connection_id": "uuid", "name": "Open source"}`. Creates a top-level project labelled theme with the shared rule of feature 003 (task app first, then the label). Response 201: one entry of `themes`.

- 409 `theme_exists` with `{"existing": {"project_id": "uuid", "name": "Open source"}}` when a live theme with that name exists in the connection. The client asks whether to link it instead (US4, scenario 3).
- 422 for an empty name. 404 for a connection that is not the user's. 409 `not_supported` and 502 `backend_unavailable`, `auth_expired`, `not_saved` as in feature 003. Nothing is stored on failure (FR-015).
- Allowed in a past year because it does not change the plan.

### `POST /annual/key-results/{id}/values`

Manual entry (FR-009), always allowed, also for an automatic key result and in a past year (FR-033).

Body: `{"value": 220, "date": "2027-03-04"}`. `date` is optional and defaults to today. Response 201: `{"id": "uuid", "value": 220, "at": "datetime", "on_date": "2027-03-04", "source": "manual", "key_result": <key result>}`.

- 422 `invalid` for a value that is not a finite number.
- 422 `future_date` for a date after today.
- 409 `retired` for a retired key result (a retired key result accepts no new value).

### `GET /annual/push-token`, `POST /annual/push-token`, `DELETE /annual/push-token`

- `GET` returns `{"exists": true, "hint": "a1b2", "created_at": "datetime", "last_used_at": "datetime|null"}` or `{"exists": false}`. It never returns the token.
- `POST` creates or rotates the token (one per user) and returns `{"token": "tfv_...", "hint": "a1b2"}` once. The old token stops working at once.
- `DELETE` removes the token. 204.

## 4. The inbound push (FR-010)

The one defined way for an outside source to send a value to an automatic key result. How the source gets the value is out of scope.

### `POST /key-results/{key_result_id}/push`

Header: `Authorization: Bearer tfv_...` (the push token of the user). No cookie, no `X-Tefteri-Client` header.

Body:

```json
{"value": 1342, "at": "2027-03-04T09:30:00Z"}
```

| Field | Rule |
|---|---|
| `key_result_id` (path) | The id of a key result of the token owner. |
| `value` | A JSON number, finite. A string, a boolean, `null`, `NaN` and infinity are refused. |
| `at` | ISO 8601 with a zone, for example `Z` or `+02:00`. Not more than 5 minutes in the future. |

Answers:

| Status | Code | When |
|---|---|---|
| 201 | none | The value is stored with `source = automatic`. Body: `{"stored": true, "key_result_id": "uuid", "value": 1342, "at": "datetime", "current_value": 1342}` |
| 200 | none | Same key result, same `at` and same value as a stored automatic value. Nothing new is stored. Body has `"stored": false`. A source can retry safely. |
| 401 | `invalid_push_token` | Missing, wrong, revoked or rotated token. A session token is not accepted. |
| 404 | `not_found` | The key result does not exist or belongs to another user. The answer is the same for both. |
| 409 | `retired` | The key result is retired. |
| 409 | `not_automatic` | The key result is not marked automatic (research R-07). |
| 422 | `invalid` | The value is not a finite JSON number, or the time stamp is missing, has no zone, or is in the future. |
| 429 | `rate_limited` | More than 60 pushes a minute for one token. `Retry-After` gives the seconds. |

A rejected push stores nothing (SC-007). An accepted push may belong to a key result of a past year. The stored value follows the same current-value rule as a manual one (FR-007). A manual entry is still possible for the same key result at any time.

Example (the token is fake):

```bash
curl -X POST "https://tefteri.example/api/v1/key-results/3f2c.../push" \
  -H "Authorization: Bearer tfv_FAKE_TOKEN_FOR_DOCS" \
  -H "Content-Type: application/json" \
  -d '{"value": 1342, "at": "2027-03-04T09:30:00Z"}'
```

## 5. Changed existing routes

### Removed

`POST /goals`, `POST /goals/bulk`, `PATCH /goals/{id}`, `DELETE /goals/{id}`, `POST /goals/{id}/breakdown`, `GET /goals`. The new routes above replace them. A call to a removed route answers 404 or 405 as any unknown route.

### `GET /views/week/{day}`, `GET /views/month/{day}`, `GET /views/year/{year}`

The field `goals` is removed from the response (FR-022, SC-005). The field `goal_titles` is added: `{"goal_titles": {"<goal id>": {"title": "Run 25 km", "annual": false}}}`. It holds only the goals that tasks of the view point to, so the client can show "Goal: Run 25 km" or "Goal (history): Run 25 km" (FR-025). The year view has no goals; the client reads `GET /annual/{year}` for the summary.

### `GET /plans`, `GET /plans/{id}`, `POST /plans`

`PlanOut.goals` is removed. Stored reviews are unchanged (`GET /plans/{id}/review` and the history). A refresh of a review skips retired goals as it skips dropped ones.

### `PATCH /tasks/{id}`

`goal_id` must be: null (clears the link), the value the task has already, or the id of an active annual goal of the current year. Else 422 `goal_not_linkable` with the message "Only goals of this year's annual plan can be linked." (FR-026). `GET /tasks?goal_id=` is unchanged.

## Errors

Same shape as the rest of the API: `{"detail": "message", "code": "..."}`. Messages say what happened and what the user can do. Codes used here: `not_found` (404), `invalid` (422), `not_a_theme` (422), `future_date` (422), `goal_not_linkable` (422), `key_result_limit` (409), `past_year` (409), `retired` (409), `already_retired` (409), `already_undone` (409), `not_automatic` (409), `theme_exists` (409), `not_supported` (409), `invalid_push_token` (401), `rate_limited` (429), `backend_unavailable`, `auth_expired` and `not_saved` (502).
