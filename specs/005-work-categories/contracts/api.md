# API Contract Delta (v1): Work Categories and Statistics

Base path `/api/v1`. The OpenAPI document (`just backend::openapi` → `docs/openapi.json`) is the authority. A snapshot test fails if it is stale. All routes need a signed-in user and only see that user's data. Errors have the shape of the rest of the API: `{"detail": "message", "code": "..."}`.

The category and reason fields use the enum classes of the domain in the response models, never a hand-written `Literal` (research R-17).

## Error codes used here

| Code | Status | When |
|---|---|---|
| `invalid` | 422 | A period that is not `week`, `month` or `year`; a `limit` outside 1 to 200; an unknown `category` or `order`. |
| `invalid_cursor` | 422 | A cursor that is not from this route, or was made for another filter. |
| `not_found` | 404 | An id that is not the user's. |

No route of this feature writes to the task app, so there is no 409 or 502.

## `GET /statistics`

The counts of one period. Query: `period` (`week`, `month`, `year`), `day` (any date inside the period, default today in the time zone of the user).

```json
{
  "period": "month",
  "start": "2030-03-01",
  "end": "2030-04-01",
  "available": true,
  "unavailable_reason": null,
  "counts": {"goal_aligned": 12, "maintenance": 5, "off_plan": 3},
  "total": 20,
  "percentages": {"goal_aligned": 60, "maintenance": 25, "off_plan": 15},
  "hidden": 2,
  "unsorted": 1,
  "part_kind": "day",
  "parts": [
    {"start": "2030-03-01", "end": "2030-03-02",
     "counts": {"goal_aligned": 1, "maintenance": 0, "off_plan": 0}, "hidden": 0}
  ],
  "empty": null,
  "sync": {"last_synced_at": "datetime|null", "outcome": "ok|auth_expired|unreachable|error|null"},
  "progress": null
}
```

- `end` is the first day after the period (as `week_end` in the weekly state).
- `counts` always has the three keys, also with zero (FR-013). `total` is their sum. `hidden` is not in `total` (FR-008). `total + hidden` is the number of tasks completed in the period.
- `percentages` come from `percentages(counts)`: three whole numbers that add up to 100, or all zero when `total` is 0 (FR-018). They are computed on every request and never stored.
- `parts` are the days for `week` (7) and `month` (28 to 31), and the months for `year` (12, `part_kind` is `month`). Each part has the same count keys. The sum of the parts equals `counts` and `hidden` (FR-009, SC-002). A task is in exactly one part.
- `unsorted` is the number of counted tasks with the "unsorted" note.
- `available` is false and `unavailable_reason` is `weekly_commitment_unavailable` when the weekly commitment (feature 004) cannot be read. Then `counts`, `parts` and `percentages` are all zero, `empty` is null and the client shows the reason, never a guessed number (FR-026).
- `empty` is `null` when the period has a counted or hidden task. Otherwise it is `{"reason": "no_tasks|no_labels", "action": "plan_week|label_projects"}`. `no_labels` is used when no project has a label yet (FR-027, US2 scenario 5).
- `sync.last_synced_at` is the end of the newest sync run of the task connections; `outcome` is the outcome of the newest run (FR-022, FR-028). The numbers are the last stored ones also when the outcome is not `ok`.
- `progress` is `null` for `month` and `year`, and for a week without a committed plan. For a week with a committed plan:

```json
"progress": {
  "committed": 8,
  "done": 5,
  "done_before": 0,
  "done_undated": 0,
  "done_after": 0,
  "done_by_day": [1, 2, 0, 2, 0, 0, 0],
  "days_elapsed": 4,
  "days_left": 3,
  "cadence": 1.25,
  "needed_per_day": 1.0,
  "on_track": true,
  "remaining_by_day": [7, 5, 5, 3, null, null, null],
  "ideal_by_day": [6.86, 5.71, 4.57, 3.43, 2.29, 1.14, 0.0],
  "scope": 8
}
```

The fields are the ones of `week_progress.dart` today, computed by `domain/week_progress.py` from the committed tasks of the plan and the clock of the server in the time zone of the user (R-12). `cadence` and `needed_per_day` are `null` as in the Dart class. The committed-task numbers do not use categories: a committed task completed in a committed milestone is also goal-aligned in `counts`, and the two views never disagree because both read the same completed tasks.

Errors: 422 `invalid`.

## `GET /statistics/tasks`

The completed tasks behind a count, in pages. Query: `period`, `day` (as above), `category` (`goal_aligned`, `maintenance`, `off_plan`, `hidden`; omit for the three work categories), `order` (`newest`, default, or `project`), `limit` (1 to 200, default 50), `cursor` (from the previous page).

```json
{
  "period": "week",
  "start": "2030-03-04",
  "end": "2030-03-11",
  "category": "off_plan",
  "order": "newest",
  "total": 250,
  "items": [
    {
      "id": "uuid",
      "title": "Fix the gutter",
      "completed_at": "datetime",
      "completed_day": "2030-03-06",
      "category": "off_plan",
      "reason": "theme",
      "unsorted": false,
      "project": {"id": "uuid|null", "name": "Home", "color": "#aabbcc|null", "orphaned": false},
      "url": "string|null"
    }
  ],
  "next_cursor": "string|null"
}
```

- `total` is the number of tasks for the filter (the whole period, not the page). It is not limited.
- `next_cursor` is `null` on the last page. Paging follows research R-10: no task is lost or repeated when the list has more than 200 tasks, and a task that is completed while the user pages does not shift the next page.
- `order = newest`: completion time descending, then id. `order = project`: project name (case-folded; "no project" last), then completion time descending, then id. The client groups the page by `project.name`.
- `project.name` is the stored name (`task_categories.project_name`), also for an orphaned project. `project.orphaned` is read from the label row. `project.id` is the id of the label row of feature 003 and is null for a task with no project.
- `category = hidden` lists the tasks of the quiet hidden line (R-16).
- `url` is the link to the task in the task app, built by the same helper as the weekly router had (`api/task_links.py`, moved from `api/routers/weekly.py`).
- A task that is deleted in the task app, or open again, is not listed.

Errors: 422 `invalid`, 422 `invalid_cursor`.

## `GET /weekly/{day}` (changed)

`done_outside_plan` is **removed** from `WeeklyStateOut` together with `ExtraDoneOut`. The week page gets the completed tasks and the counts from the two routes above. Everything else in the weekly state is as feature 004 defines it. The weekly look-back of feature 004 uses `GET /statistics/tasks` for its list and sets no limit of its own.

## `GET /views/week/{day}`, `/views/month/{day}`, `/views/year/{year}` (unchanged)

The `PeriodView` (goals, tasks due in the period, calendar entries) is not changed by this feature. Feature 006 removes the goal parts. The new category card is a separate request.

## Python service API for later features (not HTTP)

Feature 007 stores the counts of a month in its snapshot and reads them through the service, not through HTTP.

```python
class StatisticsService:
    async def daily_counts(db, user_id, start: date, end: date) -> dict[date, CategoryCounts]
    async def counts(db, user_id, start: date, end: date) -> CategoryCounts   # sum of daily_counts
```

`CategoryCounts` has `goal_aligned`, `maintenance`, `off_plan` and `hidden` (data-model.md). `end` is exclusive. Both functions read stored categories only and never recompute a category.

## Removed

- `done_outside_plan` in `GET /weekly/{day}`.
- `ExtraDoneOut`, `MAX_EXTRA_DONE`, `ExtraDone` and `WeeklyService.done_outside_plan` in the code.
- The Dart `ExtraDoneTask` and the `extra` parameter of `WeekProgress.of`.

## Capability flags

No change. The route reads only data that is already in the cache.
