# API Contract Delta (v1): Annual Review

Base path `/api/v1`. The OpenAPI document (`just backend::openapi` → `docs/openapi.json`) is the authority. A snapshot test fails if it is stale. All routes need a signed-in user and only see that user's data (FR-022): an id of another user answers 404. Errors have the shape of the rest of the API: `{"detail": "message", "code": "..."}`.

Every enum in a response (`outcome`, `state`, `status`, `hint`, `reason`) uses the enum classes of `domain/enums.py` in the response models, never a hand-written `Literal` (research R-17). The review routes never write to the task app and never write a snapshot, a goal, a key result or a link (SC-002). The only write is a note.

## Error codes used here

| Code | Status | When |
|---|---|---|
| `invalid` | 422 | A year outside 2000 to 2100, a note that is empty after trimming or longer than 2000 characters. |
| `not_found` | 404 | A goal id that is not the user's, not an annual goal, or not a goal of that year. |
| `future_year` | 409 | A note for a future year. |

The read route has no 409 and no 502: it opens for every year and every state of the data (FR-027). A year with no data answers 200 with `empty` set.

## `GET /annual-review/{year}`

The whole review of one planning year. Reads stored snapshots and the plan of 006. Nothing is stored or recomputed from tasks.

```json
{
  "year": 2025,
  "state": "past|current|future",
  "in_progress": false,
  "rules": {"hit": "last_value_reaches_target", "differ_threshold": 0.25},
  "months": [
    {"month": "2025-01", "status": "stored|missing|open|future", "version": 2, "taken_at": "datetime|null", "schema_version": 1, "action": null},
    {"month": "2025-03", "status": "missing", "version": null, "taken_at": null, "schema_version": null, "action": "open_monthly_review"}
  ],
  "coverage": {"stored": 8, "expected": 12, "missing": ["2025-03", "2025-04", "2025-09", "2025-10"]},
  "empty": null,
  "goals": [
    {
      "id": "uuid",
      "title": "Get better at open source",
      "status": "active|retired",
      "retired_at": "datetime|null",
      "retired_reason": "string|null",
      "counts": {"hit": 1, "missed": 1, "no_value": 0, "retired": 0, "in_progress": 0},
      "flags": [{"code": "no_key_result", "actions": ["open_annual_plan"]}],
      "note": {"id": "uuid", "body": "Talks went well.", "updated_at": "datetime"},
      "key_results": [
        {
          "id": "uuid",
          "metric": "Stars on one repository",
          "start_value": 120,
          "target": 500,
          "direction": "up|down",
          "deadline": "2025-12-31",
          "update_source": "manual|automatic",
          "status": "active|retired",
          "retired_at": "datetime|null",
          "outcome": "hit|missed|no_value|retired|in_progress",
          "last_value": 480,
          "last_month": "2025-11",
          "last_at": "datetime|null",
          "deadline_line": {"state": "reached|not_reached|open|no_value", "value": 505, "month": "2025-09"},
          "series": [
            {"month": "2025-01", "status": "stored|missing|open|future", "value": 150, "not_stored": false}
          ],
          "peak": {"value": 505, "month": "2025-09"},
          "moved_after_snapshot": {"value": 530, "at": "datetime"},
          "current_value": 530,
          "changes": [
            {"kind": "key_result_edited", "field": "target", "old_value": "450", "new_value": "500", "at": "datetime"}
          ],
          "flags": [
            {"code": "no_usable_theme", "reasons": [{"project_id": "uuid|null", "name": "Open source", "state": "no_links|orphaned|ignored|relabelled|unclassified"}], "actions": ["open_annual_plan"]}
          ],
          "themes": [
            {
              "project_id": "uuid",
              "connection_id": "uuid",
              "connection_name": "My task app",
              "name": "Open source",
              "label": "theme|milestone|maintenance|ignored|null",
              "orphaned": null,
              "ranges": [{"from": "2025-01-01", "to": "2025-07-31", "months": ["2025-01", "2025-02"]}],
              "shipped": 4,
              "shipped_outside_focus": 1,
              "target_sum": 3,
              "months_with_target": 3,
              "movement": {"from": 150, "to": 175, "fraction": 0.07, "months": 3},
              "hint": "much_shipped_little_movement|movement_not_from_theme|null",
              "milestones": [{"milestone_id": "uuid", "name": "Ship the login flow", "done_on": "2025-03-08", "month": "2025-03", "in_focus": true}]
            }
          ]
        }
      ]
    }
  ],
  "milestones_shipped": {"count": 24, "months_covered": 8},
  "split": {
    "months_covered": 8,
    "counts": {"goal_aligned": 120, "maintenance": 40, "off_plan": 30},
    "total": 190,
    "hidden": 12,
    "percentages": {"goal_aligned": 63, "maintenance": 21, "off_plan": 16},
    "months": [
      {"month": "2025-01", "status": "stored", "counts": {"goal_aligned": 14, "maintenance": 6, "off_plan": 3}, "hidden": 1, "percentages": {"goal_aligned": 61, "maintenance": 26, "off_plan": 13}, "not_stored": false}
    ],
    "trend_note": null
  },
  "drill_down": {"live": true, "route": "/statistics/tasks", "query": {"period": "year", "day": "2025-01-01"}},
  "next_year": {"year": 2026, "from_year": 2025, "available": true, "has_plan": true, "unmet_key_results": 2, "links": 3},
  "year_note": {"id": "uuid", "body": "A year of learning.", "updated_at": "datetime"},
  "stored_period_review": {"plan_id": "uuid", "period_start": "2025-01-01"}
}
```

Rules of the response:

- `state` is `past`, `current` or `future` (006 `year_state`). `in_progress` is true for `current`. A `future` year answers with `empty.reason = "future_year"`, no goals and no months with data.
- `rules.hit` names the one rule (R-03) so the client shows the matching text. `rules.differ_threshold` is 0.25 (R-05).
- `months` always has twelve items. `action` is `open_monthly_review` for `missing` and `open` months and null otherwise. The client opens the monthly review of 007 for that month. `version` is the current version of the snapshot (FR-026). `schema_version` null means the payload has no version.
- `coverage.expected` is 12 for a past year and the number of months up to the current month for the current year. Every total in the response states `months_covered` (FR-010).
- `empty` is null, or `{"reason": "no_snapshots|no_goals|future_year", "actions": ["open_annual_plan"]}`. `no_snapshots` still returns the goals and key results with start, target and `current_value` (FR-011); their `outcome` is `no_value` (or `retired`) and `series` has only gaps.
- `goals` holds every goal of the year, active first, then retired (FR-002). `counts` sums the outcomes of its key results. A goal with no key result has `flags: [{"code": "no_key_result"}]` and the action `open_annual_plan` (US1, scenario 4). Flags use the codes and wording of 006 and only point to annual planning.
- `last_value`, `last_month`, `last_at` are null when `outcome` is `no_value` (the start value is never shown as a last value). `deadline_line.state = open` means the deadline is not over at the end of the stored data (FR-025). `deadline_line.value` and `month` are null for `open` and `no_value`.
- `series[].value` is null for a gap. `not_stored` is true when a stored snapshot has no entry for the key result. A gap is never filled (FR-004).
- `peak` is null when the best value equals the last value or there is no value.
- `moved_after_snapshot` is null unless `state = past` and the newest value of the 006 series is later than the last snapshot value and differs (FR-029). `current_value` is the live value of 006, labelled by the client as "current value (not from a snapshot)". Neither changes `outcome`.
- `changes` lists the target and deadline edits and the retirement of the item in time order, from `plan_changes` of 006 (FR-013). `target` is the target at the end of the year.
- `themes` is the list of linked themes of the year for that key result, with the stored name. A theme linked to two key results appears under both with its own contribution. `orphaned` is `null` or `{"reason": "missing|archived", "at": "datetime"}` (003). `label` is the current label, so the client can say "relabelled". An orphaned or relabelled theme stays in the list (FR-015, scenario 2 of user story 6).
- `ranges[].to` is null for a link that was active at the end of the year. `months` lists the months in which the link was active (FR-006, scenario 3 of user story 5).
- `shipped` counts milestones of the snapshots with a `done_on` inside the ranges, in the focus; `shipped_outside_focus` counts the ones listed under `outside_focus` for the theme (R-04). `target_sum` is null when no covered month has a target. `movement` is null when a covered month has no value of the key result or the span is zero (R-05). `hint` follows R-05.
- `milestones_shipped.count` is the number of distinct milestones over the snapshots of the year, so a theme under two key results is counted once (FR-006).
- `split.counts` always has the three keys, also with zero. `total` is their sum. `hidden` is not in `total` and is shown as its own part (FR-008). `percentages` are three whole numbers that add up to 100, or all zero, computed on every request (never stored). `months` has twelve items; a month without a snapshot has `counts: null`. A snapshot with no categories has `not_stored: true` and is not in `months_covered`. `trend_note` is null for now and reserved for the wording of the trend (no judgement, scenario 2 of user story 3).
- `drill_down.live` is always true. The client calls `GET /statistics/tasks` of 005 with `query` and the chosen `category`, and writes "Live list, may differ from the bar" next to it (FR-009, SC-008).
- `next_year.unmet_key_results` and `links` are the numbers that `AnnualPlanService.suggestions(year + 1, from_year=year)` of 006 gives (R-09, FR-020). `available` is false for a future year. `has_plan` is false when year N has no plan. The review shows the numbers and nothing else (FR-018).
- `year_note` and every `goals[].note` are null when no note exists.
- `stored_period_review` is null or the entry to link to (R-10).

The response is built from stored data only. A test fails when the review reads `tasks`, `milestones` or `weekly_plans` (FR-001).

## `PUT /annual-review/{year}/notes`

Creates or replaces the note of the year or of one goal (R-08).

Body: `{"goal_id": "uuid|null", "body": "A year of learning."}`. `goal_id` null is the note of the year.

Response 200: `{"id": "uuid", "year": 2025, "goal_id": "uuid|null", "body": "A year of learning.", "updated_at": "datetime"}`.

Errors: 404 `not_found` for a goal that is not the user's, not annual or not of that year; 409 `future_year`; 422 `invalid` for an empty or too long text. The write is allowed in a past year because it changes no plan (FR-017). Nothing else is written (SC-002).

## `DELETE /annual-review/{year}/notes`

Query: `goal_id` (optional; absent means the note of the year).

Response 200: `{"deleted": {"id": "uuid", "year": 2025, "goal_id": "uuid|null", "body": "A year of learning.", "updated_at": "datetime"}}`. The client shows the text that was lost and offers Undo for 8 seconds. Undo calls `PUT` with the same body (R-08). Errors: 404 `not_found` when there is no such note or the goal is not the user's.

## Routes of other features that this feature uses as they are

- `GET /statistics/tasks` (005): the live drill-down list (R-07).
- `GET /annual/{year}`, `GET /annual/{year}/history` (006): read in process by the service for goals, key results, links and history. The client of the review does not call them.
- `GET /annual/{year}/suggestions?from_year=N` (006): the client of annual planning calls it after "Start next year". The review calls the same service function in process for the count.
- `GET /monthly/snapshots` (007): not used by the review (it calls `MonthlyReviewService.current_snapshots`).
- `GET /plans`, `GET /plans/{id}/review` (old reviews): the stored period reviews, unchanged.

## Changed existing routes

None. `GET /views/year/{year}` stays as it is. The client stops calling it (R-10).

## Capability flags

None. This feature adds no port operation and no capability, and no adapter changes.
