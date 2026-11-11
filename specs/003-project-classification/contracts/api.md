# API Contract Delta (v1): Project Classification

Base path `/api/v1`. The OpenAPI document (`just backend::openapi` → `docs/openapi.json`) is the authority. A snapshot test fails if it is stale. All routes need a signed-in user and only see that user's data.

## `GET /projects/classification`

Query: `connection_id` (optional; default all task connections).

Response:

```json
{
  "connections": [
    {
      "connection_id": "uuid",
      "name": "My Vikunja",
      "status": "ok|needs_attention|error",
      "last_sync_outcome": "ok|auth_expired|unreachable|error|null",
      "capabilities": {"rename": true, "restore": true},
      "projects": [
        {
          "id": "uuid",
          "name": "Open source",
          "parent_id": "uuid|null",
          "label": "theme|milestone|maintenance|ignored|null",
          "proposal": {"label": "theme", "reason": "top_level|nested|was_committed"},
          "effective_label": "theme",
          "parent_theme_id": "uuid|null",
          "unsorted": true,
          "orphaned": null,
          "eligible": true,
          "open_tasks": 4,
          "subprojects": 2,
          "in_committed_plan": false
        }
      ]
    }
  ],
  "unsorted_count": 12
}
```

Every project also carries `connection_id` (uuid). `orphaned` is `null` or `{"reason": "missing|archived", "at": "datetime"}`. An orphaned project stays in the list with its stored name. `proposal` is present for every project and is only a suggestion while `label` is null. Projects are in tree order with `parent_id`.

## `PUT /projects/labels`

Body: `{"changes": [{"id": "uuid", "label": "theme|milestone|maintenance|ignored|null"}], "dry_run": false, "source": "user|suggestion"}`.

- `dry_run=true`: writes nothing and returns the effect.
- `dry_run=false`: writes, adds history entries with one `batch_id`, returns the effect and the `batch_id`.

Response: `{"batch_id": "uuid|null", "effect": {"changed": 5, "by_change": [{"from": "none", "to": "theme", "count": 3}], "in_committed_plan": 1}}`.

Errors: 404 for an id that is not the user's, 422 for an unknown label.

## `POST /projects/labels/undo`

Body: `{"batch_id": "uuid"}`. Adds new history entries that restore the earlier labels. Response: `{"restored": 5}`. 404 if the batch is not the user's, 409 if the batch was already undone.

## `PATCH /projects/{id}`

Body: `{"name": "New name"}`. Writes to the task app first and updates the record only after it works.

- 200 with the updated project (same shape as an entry of `projects` above).
- 409 `not_supported` if the connector cannot rename (the client hides the control).
- 502 if the task app fails. Nothing changes. The code is the existing one of the API: `backend_unavailable`, `auth_expired` or `not_saved` (not `task_app_refused`).
- 404 for an orphaned project (it cannot be renamed).
- 422 for an empty name.

## `POST /projects`

Body: `{"connection_id": "uuid", "name": "Open source", "parent_id": "uuid|null", "label": "theme|milestone|maintenance|ignored"}`. The shared "create project and label it" rule (FR-024): create in the task app first, then record the label. Response: 201 with the project (same shape as above). 404 for a connection or parent that is not the user's, 422 for an empty name or a parent that is orphaned or in another connection, 409 `not_supported` / 502 (codes as for rename) when the task app fails; nothing is recorded then. On failure after creation, the next sync finds the project and proposes a label.

## `POST /projects/{id}/archive` and `POST /projects/{id}/restore`

- `archive`: the existing archive route in `connections` stays for compatibility (204) and calls the same service. The new route answers 200 with the project, now orphaned with the reason `archived` and still in the list. Its subprojects are archived and marked too. 422 if the project is already orphaned; the existing refusal (422, project waits for its look-back) still applies.
- `restore`: restores the project (and the archived subprojects) in the task app first and clears the orphaned mark only if that works. Answers 200 with the project. 409 `not_supported` or 502 on failure, with the project unchanged. 422 if the project was not archived from Tefteri (`missing` cannot be restored).

## `POST /connections` and `POST /connections/{id}/check` — changed

The response gains `capabilities`: `{"missing_required": ["subprojects"], "optional": {"rename": false, "restore": true}}`. Connecting a task app with a missing required capability returns 422 `missing_capability` with the capability name in `detail` (FR-015); nothing is stored then. On `check`, such an app gives `status: "error"`, `reason: "missing_capability"` and the names in `message`. Connections that are not task apps return `{"missing_required": [], "optional": {}}`. A missing optional capability only sets the flag to false.

## `GET /weekly/{day}/candidates` — changed

Lists only weekly-eligible projects (FR-008). The response stays a JSON list. Deviation: it cannot gain a top-level `unsorted_count`, so each item gains `unsorted` (boolean, true when the project has no label yet). The client counts them for the quiet reminder. The total of all live unlabelled projects is `unsorted_count` of `GET /projects/classification`.

## Errors

Same shape as the rest of the API: `{"detail": "message", "code": "..."}` (`detail` is a string, `code` is at the top level). Messages say what happened and what the user can do. Codes used here: `not_found` (404), `invalid` (422), `already_undone` (409), `not_supported` (409), `missing_capability` (422), `backend_unavailable`, `auth_expired` and `not_saved` (502). A 502 body also has `connection` (the name of the connection). An unknown label value is the standard FastAPI 422 validation error.
