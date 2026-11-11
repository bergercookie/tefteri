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

`orphaned` is `null` or `{"reason": "missing|archived", "at": "datetime"}`. `proposal` is present for every project and is only a suggestion while `label` is null. Projects are in tree order with `parent_id`.

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

- 200 with the updated project.
- 409 `not_supported` if the connector cannot rename (the client hides the control).
- 502 `task_app_refused` with a message if the task app fails. Nothing changes.
- 404 for an orphaned project (it cannot be renamed).

## `POST /projects`

Body: `{"connection_id": "uuid", "name": "Open source", "parent_id": "uuid|null", "label": "theme|milestone|maintenance|ignored"}`. The shared "create project and label it" rule (FR-024): create in the task app first, then record the label. Response: the project. On failure after creation, the next sync finds the project and proposes a label.

## `POST /projects/{id}/archive` and `POST /projects/{id}/restore`

- `archive`: the existing archive route in `connections` stays for compatibility and calls the same service. The new service marks the project orphaned with the reason `archived` and keeps it in the list.
- `restore`: restores the project in the task app first and clears the orphaned mark only if that works. 409 `not_supported` or 502 on failure, with the project unchanged.

## `POST /connections` and `POST /connections/{id}/check` — changed

The response gains `capabilities`: `{"missing_required": ["subprojects"], "optional": {"rename": false, "restore": true}}`. Connecting a task app with a missing required capability returns 422 `missing_capability` with the capability name in the message (FR-015). A missing optional capability only sets the flag to false.

## `GET /weekly/{day}/candidates` — changed

Lists only weekly-eligible projects (FR-008). The response keeps its shape and gains `unsorted_count` so the client can show the quiet reminder.

## Errors

Same shape as the rest of the API: `{"detail": {"code": "...", "message": "..."}}`. Messages say what happened and what the user can do.
