# API Contract Delta (v1): Weekly Milestones

Base path `/api/v1`. The OpenAPI document (`just backend::openapi` → `docs/openapi.json`) is the authority. A snapshot test fails if it is stale. All routes need a signed-in user and only see that user's data. Errors have the shape of the rest of the API: `{"detail": "message", "code": "..."}`; a 502 body also has `connection`.

## Error codes used here

| Code | Status | When |
|---|---|---|
| `not_found` | 404 | An id that is not the user's. |
| `invalid` | 422 | Generic refusal (existing). |
| `done_state_required` | 422 | A new milestone has an empty or blank done-state. `detail` holds the hint and the example "ship the login flow". |
| `not_a_milestone` | 422 | A project that is a theme, or has subprojects and no label, was added to a week. |
| `not_eligible` | 422 | A project that is maintenance, ignored, orphaned or inside a routine or an ignored project was added to a week. |
| `no_theme` | 422 | Close needs a parent theme and the milestone has none, or the theme is ignored or orphaned. |
| `confirm_required` | 422 | A close without `confirm: true`, or a review answer `decision: "close"` for a milestone that is not closed yet. |
| `not_unfinished` | 422 | A done-by-hand or a close on a milestone that is done or closed, or a review answer other than `close` for a milestone that is closed. (A review answer for a milestone that is *done* is ignored, not refused.) |
| `not_supported` | 409 | The task app cannot move tasks (existing code, new capability `move_tasks`). |
| `backend_unavailable`, `auth_expired`, `not_saved` | 502 | The task app failed (existing codes). `remote_conflict` (409) can also come from a close when a task changed in the task app since the last sync. |

`Invalid` gains an optional code. Before this feature every 422 from a service had the code `invalid`.

## `GET /weekly/{day}` (changed)

`plan.max_projects` is removed. `plan` gains the cap fields. Each entry of `plan.projects` gains the milestone fields. `look_back` gains the decision fields and a summary. `done_outside_plan` is unchanged (feature 005 takes it over later).

```json
{
  "week_start": "2030-03-04",
  "week_end": "2030-03-11",
  "plan": {
    "id": "uuid",
    "status": "draft|committed",
    "committed_at": "datetime|null",
    "retro_skipped": false,
    "milestone_count": 4,
    "milestone_cap": 3,
    "over_cap": true,
    "month": "2030-03-01",
    "focus_known": true,
    "projects": [
      {
        "id": "uuid",
        "container_id": "uuid|null",
        "milestone_id": "uuid|null",
        "name": "Ship the login flow",
        "done_state": "Users can sign in with a passkey",
        "milestone_state": "active|parked|closed|done|null",
        "theme": {"id": "uuid", "name": "Open source"},
        "outside_focus": false,
        "rollover_count": 1,
        "needs_rescope": false,
        "orphaned": false,
        "notice": "relabelled|null",
        "...": "all existing fields (open_tasks, tasks, committed_tasks, color, url ...)"
      }
    ]
  },
  "look_back": {"...": "see below"},
  "done_outside_plan": []
}
```

`theme.id` is the id of the label row of the theme, the same id that `GET /projects/classification` uses. `theme` is the theme **at the time of the commitment** (stored on the entry and stored again at the commit); it is `null` for "no theme" and for a legacy entry. `outside_focus` is computed on read and is false when `focus_known` is false. `milestone_id` and `milestone_state` are `null` for a legacy entry. `notice` is `relabelled` when the project got another label after it was committed, `null` otherwise. The old `parked` field on tasks keeps its name; the client shows it as "Not this week".

## `GET /weekly/{day}/candidates` (changed)

Still a JSON list. It lists the projects that the user may commit (`commit_kind` is not none), without the ones already chosen being hidden: they carry `selected: true`.

```json
[
  {
    "container_id": "uuid",
    "connection_id": "uuid",
    "connection_name": "My Vikunja",
    "name": "Ship the login flow",
    "path": "Open source › Ship the login flow",
    "kind": "milestone|unsorted",
    "milestone_id": "uuid|null",
    "done_state": "string|null",
    "state": "active|parked",
    "theme": {"id": "uuid", "name": "Open source"},
    "in_focus": true,
    "rollover_count": 2,
    "needs_rescope": false,
    "decision_open": true,
    "open_tasks": 5,
    "carried_tasks": 2,
    "selected": false,
    "unsorted": false
  }
]
```

`kind = unsorted` means that the project has no label and no live subproject (a leaf, top-level or nested): choosing it labels it milestone. `unsorted` is the same fact as a boolean (`kind == "unsorted"`). The list is sorted: focus themes first when focus data exists, then recommitted ones, then by path. `in_focus` is `null` when no focus data exists. `theme` is `null` for the group "No theme". `decision_open` is true when the last review left the milestone with "decide later" (FR-036). `carried_tasks` is now the number of open committed tasks of a milestone that was recommitted by the last review (it was for `carry`).

## `GET /weekly/{day}/themes` (new)

The themes for the picker headers and its empty states.

```json
{
  "focus_known": true,
  "themes": [
    {"id": "uuid", "container_id": "uuid", "connection_id": "uuid", "name": "Open source",
     "in_focus": true, "milestones": 3, "open_milestones": 2}
  ],
  "unsorted_count": 4
}
```

Only themes that are weekly-eligible per 003 are listed (live, not ignored, not maintenance, not inside a routine). A project with the stored label `theme` is listed; a project with **no** label is listed only when it has a live subproject (so it acts as a theme). Focus themes come first when `focus_known`. `container_id` is the parent for `POST /weekly/{day}/milestones`. `milestones` counts the live milestones whose nearest theme is this one, `open_milestones` those that are active or parked. `unsorted_count` is the number of live projects that have no label at all (the 003 meaning), not only the leaf ones.

## `POST /weekly/{day}/projects` (changed)

Body: `{"container_id": "uuid"}`. Adds a milestone to the week. Adding the same one twice changes nothing (201). A project with `kind = unsorted` is labelled milestone in the same request (history source `user`). **No cap check.** Errors: 404 (not the user's), 422 `not_a_milestone` (a theme, or a project with no label that has subprojects), 422 `not_eligible` (maintenance, ignored, orphaned, inside a routine or an ignored project, or a milestone that is closed or done), 422 `invalid` (the plan is committed). Response: the state, as `GET /weekly/{day}`.

## `POST /weekly/{day}/milestones` (new, replaces `POST /weekly/{day}/subprojects`)

Body: `{"parent_id": "uuid", "name": "Ship the login flow", "done_state": "Users can sign in with a passkey"}`. `parent_id` is the container id of the theme. The shared rule of 003: create the sub-project in the task app first, then record the label milestone, the done-state and the commitment. Response 201: the state. Errors: 404 for a parent that is not the user's; 422 `done_state_required` (checked before the task app is called); 422 `invalid` for an empty name or a parent that is not a theme; 409 `not_supported` (no `SUBPROJECTS`) and 502 when the task app fails, with nothing recorded.

## `POST /weekly/{day}/projects/{plan_project_id}/tasks` (new)

Body: `{"title": "Draw the screens"}`. Creates a task under the milestone of the entry in the task app (capability `create_tasks`) and returns the state (status 201). The task is not committed until it gets a day. 404 for an entry that is not in the plan; 422 for a blank title; 502 and 409 as above; 422 `invalid` when the plan is committed.

## `POST /weekly/{day}/commit` (changed)

A plan with zero milestones can be committed. The old 422 "Choose at least one project" is removed.

## `GET /weekly/{day}` look-back block (changed)

```json
{
  "plan_id": "uuid",
  "week_start": "2030-02-25",
  "reviewed": false,
  "reflection": "",
  "summary": {
    "committed_tasks": 8,
    "done_tasks": 5,
    "milestones_committed": 3,
    "milestones_done": 1,
    "pace": [{"day": "2030-02-25", "done": 1}, {"day": "2030-02-26", "done": 2}, "...one entry for each of the 7 local days of the week, also with 0"],
    "focus_share": 0.6,
    "note": "string|null"
  },
  "projects": [
    {
      "id": "uuid",
      "milestone_id": "uuid|null",
      "name": "Ship the login flow",
      "done_state": "string|null",
      "theme": {"id": "uuid", "name": "Open source"},
      "milestone_state": "active|parked|closed|done|null",
      "committed": 4,
      "done": 2,
      "completed": false,
      "outcome": "done|not_done|null",
      "decision": "recommit|park|close|decide_later|null",
      "expected_rollover": false,
      "legacy": false,
      "rollover_count": 1,
      "needs_rescope": false,
      "outside_focus": false,
      "close": {"available": true, "reason": null, "open_tasks": 2, "theme_name": "Open source"},
      "leftover": []
    }
  ]
}
```

`summary.focus_share` is `null` when no focus data exists or no committed task was completed. When no task was committed, `committed_tasks` is 0, `focus_share` is `null` and `note` holds the short text; the client shows the note and no ratio (FR-020). `decision` is the result of `decision_of`, so an old `carry` row shows `recommit` and an old `backlog` row shows `park`; `legacy` is true for such a row and for an entry without a milestone. `close.reason` is `null`, `no_theme`, `theme_unusable`, `not_supported` or `orphaned` (the project itself is gone from the task app). `close` is `null` for an entry with no milestone (legacy). For a milestone that is done or closed, `close.available` is false and `reason` is `null`. `summary.note` is "No task was committed that week, so there are no numbers to show." when no task was committed. `leftover_action` is removed from the response.

## `POST /weekly/reviews/{plan_id}` (changed)

```json
{
  "projects": [
    {"plan_project_id": "uuid", "decision": "recommit", "expected": true, "mark_done": false, "archive": false}
  ],
  "reflection": "string"
}
```

- `decision`: `recommit`, `park`, `close` or `decide_later`. Missing means `decide_later`. Any other value is a validation error (422). A finished (done) milestone needs none; a decision for it is ignored. Each item rejects unknown fields (422).
- `expected`: the marker of the rollover event, used with `recommit` only (default false).
- `mark_done`: marks the milestone done by hand (day = today of the user) and then no decision is needed. Replaces `finished_anyway`.
- `archive`: as before, after the counts are stored.
- `close` requires that the milestone is already closed (by `POST /milestones/{id}/close`). Otherwise 422 `confirm_required`. A closed milestone with an answer other than `close` is 422 `not_unfinished`; with no answer it is stored as `close`. Nothing is saved when any answer is refused.
- `leftover` and `finished_anyway` are removed. A request that has them is a validation error (422).

Effects: `recommit` adds a rollover event (with `expected`), raises the count by one and adds the milestone to the plan of the next week (the plan goes back to draft if it was committed; the response says so in `notices`). `park` sets the state `parked`. `decide_later` changes nothing. The look-back is stored once, as before (422 `invalid` on the second call). The response is the history, as before, plus `"notices": ["string"]` and, for each recommit, `"nudges": [{"milestone_id": "uuid", "name": "string"}]` for a milestone that now needs re-scoping.

## `GET /weekly/history` (changed)

Entries keep their fields. `committed_projects` and `done_projects` now count milestones for new weeks and legacy projects for old weeks. `projects` entries gain `decision` (through `decision_of`), `legacy` (true for an old entry), `milestone_id`, `theme_name`, `done_on` and `rollover_count`, so an old week shows "Keep and recommit" or "Keep but park". `decision` is `null` for a milestone that was done (it needed none).

## `GET /milestones/{id}` (new)

```json
{
  "id": "uuid",
  "project_id": "uuid",
  "name": "Ship the login flow",
  "done_state": "string|null",
  "state": "active|parked|closed|done",
  "theme": {"id": "uuid", "name": "Open source"},
  "rollover_count": 2,
  "needs_rescope": true,
  "done_on": "2030-03-08|null",
  "done_theme_name": "Open source|null",
  "done_by": "auto|user|null",
  "orphaned": "missing|archived|null",
  "rollovers": [{"from_week": "2030-02-18", "to_week": "2030-02-25", "expected": false}],
  "open_tasks": 2,
  "can_close": {"available": true, "reason": "null|no_theme|theme_unusable|not_supported|orphaned"},
  "last_closure": {"id": "uuid", "status": "closed|reopened|moving", "moved": 3}
}
```

404 for an id that is not the user's.

## `PATCH /milestones/{id}` (new)

Body: `{"done_state": "string"}`. Sets or changes the done-state (needed for a milestone that was labelled outside the weekly flow). 422 `done_state_required` when blank. Response: the milestone.

## `POST /milestones/{id}/done` (new)

Body: `{"dry_run": false}`. Marks the milestone done by hand. `dry_run=true` writes nothing and returns the effect: `{"open_tasks": 2, "message": "2 open tasks stay in the project. Nothing is moved or deleted.", "milestone": null}`. Without `dry_run` it sets `state = done`, `done_on` = today of the user, `done_by = user` and the theme at that moment. Response: `{"open_tasks", "message", "milestone": {...}}`. 422 `not_unfinished` if it is done or closed already.

## `POST /milestones/{id}/close` (new)

Body: `{"dry_run": false, "confirm": false}`.

- `dry_run=true`: writes and moves nothing. Response 200: `{"open_tasks": 4, "theme": {"id": "uuid", "name": "Open source"}, "message": "4 open tasks will move to Open source."}`.
- `confirm=true`: moves the open tasks to the parent theme project, then closes. Response 200: `{"milestone": {...}, "moved": 4, "closure_id": "uuid"}`.
- Neither: 422 `confirm_required`.

Errors: 422 `no_theme` (no theme, or an ignored or orphaned theme), 422 `not_unfinished`, 422 `invalid` (the project of the milestone is gone from the task app), 409 `not_supported` (the task app has no `move_tasks`). 502 when a move fails; the milestone stays unclosed and the body is `{"detail", "code", "connection", "moved": [{"task_id": "uuid", "title": "string"}], "remaining": 2}`. `code` is the code of the task app problem (`backend_unavailable`, `auth_expired`, `not_saved`; a task that changed gives 409 `remote_conflict`). `moved` lists **all** tasks that the close has moved so far, also those of an earlier attempt. When some tasks moved, `detail` says how many and that the milestone is not closed. The moves that worked are kept even though the call fails. Calling again continues with the tasks that are not yet in the theme.

## `POST /milestones/{id}/reopen` (new)

Body: none. Sets the state to `active`. For a closed milestone it moves the tasks of its newest closure back where they were and unchanged. Response 200: `{"milestone": {...}, "moved_back": 3, "not_moved_back": [{"task_id": "uuid", "title": "string", "reason": "changed|moved|missing|failed"}]}` (`failed`: the task app refused, or could not be reached, for that task). A task that could not be moved back never makes the call fail (FR-037). For a milestone that is done by hand or by the rule, it clears the done fields. 422 `invalid` when the state is already `active` or `parked`.

## Capability flags (changed)

- `POST /connections` and `POST /connections/{id}/check`: `capabilities.optional` gains `"move_tasks": true|false`.
- `GET /projects/classification`: each connection's `capabilities` gains `"move_tasks": true|false`.

A connector without it only loses the close option (FR-027). It is never refused (the capability is optional).

## Removed

- `POST /weekly/{day}/subprojects` (replaced by `/milestones`).
- `plan.max_projects`, `leftover_action` in the look-back, `leftover` and `finished_anyway` in the review body.
