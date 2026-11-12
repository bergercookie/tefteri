# Monthly planning and review

Monthly planning stores a user's focus themes and their milestone-count targets. Monthly review
compares those targets with completed milestones and key result values. The code for this feature
is in `backend/src/tefteri/domain/monthly.py`, `backend/src/tefteri/services/monthly_focus.py`,
`backend/src/tefteri/services/monthly_review.py` and
`backend/src/tefteri/db/models/monthly.py`.

The month is a local calendar period in the user's time zone. Database month values are the
first day of the month.

## Tables

Migration `0022_monthly_cycle` adds five tables:

| Table | Purpose |
| --- | --- |
| `monthly_focuses` | One saved focus header for a user and month. No row means no focus data. |
| `monthly_focus_entries` | One theme in a focus, its optional target, count start date, and leave state. |
| `focus_changes` | Append-only log of focus changes and undo actions. |
| `monthly_reviews` | Mutable header for the current review version of a user and month. |
| `monthly_review_snapshots` | One immutable JSON snapshot per review version. |

A target is a nullable whole number. `NULL` means no target; `0` is a real target. An entry has a
`counts_from` date. The first plan uses the first day of the month. An entry added later uses the
change date. `left_on` and `left_reason` retain a removed or swapped-out entry for the review.

`focus_changes` is append only. Undo adds a new log entry; it does not edit or delete the earlier
change. A review snapshot row is never updated or deleted by application code. Saving a review
again adds a new snapshot row and advances `monthly_reviews.current_version`. Making an earlier
version current changes only the header pointer and its change time.

## Pure rules

`domain/monthly.py` has no database, service or task-provider imports. It holds rules shared by
live reads and snapshots:

- `parse_target` accepts an empty value or a non-negative whole number. It rejects booleans,
  negative numbers, decimals and other text.
- `count_note` gives quiet guidance for an empty focus or a focus with fewer than three or more
  than five themes. It never refuses a plan.
- `month_bounds` returns the first day and the exclusive first day of the next month.
  `month_state` compares months by the user's local date.
- `classify_done` groups done milestones as counted, earlier-not-counted or outside focus.
- Key result helpers calculate status, change, shared status and flags.
- `off_plan_share` calculates a share from visible category counts. `trend` marks a share as
  rising only when it is greater than the shares of both immediately previous months.
- `decision_effect` and `build_suggestions` describe review decisions and next-month suggestions.
- `build_payload` makes a JSON-compatible schema-version-1 snapshot from loaded facts.

## Milestone counting

The service reads the done date and the theme at done from feature 004. It does not define the
done rule. A milestone counts only when its done date is within the month:

```text
month start <= done date < first day of next month
```

The month and the date of a focus change use the user's time zone. A milestone counts under the
theme it had when it became done. A later move or rename does not change that fact.

For a theme in the focus, a milestone counts toward its target only when its done date is on or
after `counts_from` and is not after the entry left the focus. Work finished before an entry's
`counts_from` date appears as earlier work and does not count towards that target. Work under a
theme outside the focus, or with no theme, appears in the outside-focus list. Closed and parked
milestones are not done milestones.

The review counts the month of the done date, not the month when a user opens the review. Result
markers compare the count with the target: no target, missed, met or beaten. A target of zero is
compared with zero like any other number.

## Snapshot schema version 1

`MonthlyReviewService` builds the live draft from loaded database facts. On save, it writes any
manual key result values first, builds the final payload, and inserts a snapshot row with
`schema_version = 1`. The payload contains:

- `schema_version`, `month`, `month_end` and `taken_at`;
- `themes`, including stored theme names, targets, count windows, results, milestones and key
  result links;
- `changes` and `outside_focus`;
- `categories`, with goal-aligned, maintenance, off-plan and hidden counts;
- `key_results`, with start, base and latest values, time stamps, change, status, flags and
  sharing information;
- `decisions`, including replacement details or decide-later values.

The payload stores counts, not percentages or shares. The trend and shares are calculated when
the review is read. The snapshot also has a `values_written` field that records the 006 series
rows written during that save. It does not change the payload.

The schema-v1 payload uses ISO date and time strings. Its root fields are `schema_version`,
`month`, `month_end`, `taken_at`, `themes`, `changes`, `outside_focus`, `categories`,
`key_results` and `decisions`.

| Payload item | Fields |
| --- | --- |
| Each `themes` item | `project_id`, `name`, `target`, `counts_from`, `left_on`, `status`, `orphaned`, `label_changed`, `done`, `marker`, `milestones`, `earlier_not_counted`, `key_result_ids`. |
| A milestone in either theme list | `milestone_id`, `name`, `done_on`. |
| Each `changes` item | `kind`, `on`, `out_project_id`, `out_name`, `in_project_id`, `in_name`, `target_before`, `target_after`, `undone`. |
| Each `outside_focus` item | `milestone_id`, `name`, `done_on`, `theme_project_id`, `theme_name`. Null theme fields mean no theme. |
| `categories` | `goal_aligned`, `maintenance`, `off_plan`, `hidden`. These are counts. |
| Each `key_results` item | `key_result_id`, `goal_id`, `goal_title`, `metric`, `update_source`, `start_value`, `base_value`, `latest_value`, `latest_at`, `change`, `status`, `entered_in_review`, `after_month_end`, `target`, `deadline`, `past_deadline`, `retired`, `theme_ids`, `shared`, `flags`. |
| Each `decisions` item | `project_id`, `name`, `decision`, `replacement_project_id`, `replacement_name`. |

### Evolve the payload

Do not edit an existing snapshot when the payload shape changes. Add the field to the typed input
and `build_payload`, then update schema and snapshot tests and the documented payload. If a
change is not backward-compatible, assign a new `schema_version` and make readers handle both
versions. Keep the 008 reader tolerant of missing fields. Existing rows keep their old schema
version and payload forever.

## Focus seam with weekly planning

Feature 004 defines `FocusProvider` in `services/focus.py`:

```python
async def themes_for_month(db, user_id, month_start) -> set[UUID] | None
```

`WeeklyService` reads this provider for the month of the Monday of the week. `NoFocus` returns
`None` when no monthly focus exists. `MonthlyFocusService` is the real provider wired at startup.
It returns the set of themes in a saved focus, including an empty set for a saved empty focus.
The weekly picker puts focus themes first. It computes outside-focus state when it reads the
focus; it does not store that state on a milestone.

## Reads and writes across features

| Feature | Monthly cycle reads | Monthly cycle writes |
| --- | --- | --- |
| 003, project classification | Eligible theme labels and current project information. | Nothing. |
| 004, weekly milestones | Milestone state, done date, theme at done, and weekly commitments for change-effect text. | Nothing. A swap does not change milestones or weekly commitments. |
| 005, work categories | Monthly summary counts through `CategoryCountsReader`, adapted from `StatisticsService`. | Nothing. The monthly review does not classify tasks again. |
| 006, annual planning | Goals, key results, links, history, latest series values and time stamps. | One value in `key_result_values` for each manual value that the user enters in the review, through `KeyResultService`. |

The feature never pulls an automatic key result value. It reads the value already in the 006
series. It does not create or change projects, tasks, labels, key result links or key result
structure. The typed-value write is the only write outside the monthly feature's tables.

## Read contract for feature 008

Feature 008 calls `MonthlyReviewService.current_snapshots(db, user_id, year)` in process. The
service returns each month in that year that has a review, with the month, current version,
snapshot time and the current snapshot payload. It follows the pointer in `monthly_reviews`.
It does not recalculate the review or join live project, milestone or key result data. The
`GET /monthly/snapshots?year=YYYY` route exposes the same list. Feature 008 treats the payload
as versioned data and tolerates fields that are not present in an older schema version.

For the API shapes, see
[the monthly API contract](../../specs/007-monthly-cycle/contracts/api.md) and
[the annual review contract](../../specs/008-annual-review/contracts/api.md).

## Tests

The pure rules are tested in `backend/tests/unit/test_monthly.py` and
`backend/tests/unit/test_monthly_review_rules.py`. The focus, counting, key result, category,
decision, snapshot and no-task-app-write behavior is covered by
`backend/tests/integration/test_monthly_*.py`. The HTTP flow is covered by
`backend/tests/e2e/test_monthly_api.py`. Read [Tests and migrations](testing.md) for the test
commands.
