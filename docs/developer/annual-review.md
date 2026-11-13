# Annual review

The annual review is the Year view since feature 008. It reads the stored monthly review
snapshots of feature 007 and the annual plan of feature 006. It never reads `tasks`, `milestones`
or `weekly_plans`.

## Layers and files

| Part | File |
| --- | --- |
| Tolerant snapshot reader | `backend/src/tefteri/domain/snapshot_view.py` |
| Pure rules | `backend/src/tefteri/domain/annual_review.py` |
| Read model and readers | `backend/src/tefteri/services/annual_review.py` |
| Notes | `backend/src/tefteri/services/review_notes.py` |
| Database model | `backend/src/tefteri/db/models/review_note.py` |
| Migration | `backend/migrations/versions/0023_annual_review.py` |
| Router | `backend/src/tefteri/api/routers/annual_review.py` |

The service takes three protocols. `SnapshotReader` wraps
`MonthlyReviewService.current_snapshots`. `PlanReader` is `AnnualPlanService.plan` and `.history`.
`SeedCounter` wraps `AnnualPlanService.suggestions`. `main.py` wires the real services.

## Rules

`domain/annual_review.py` owns the display rules:

- `last_value` takes the newest snapshot that holds a value with a time stamp;
- `key_result_outcome` uses `is_met` from feature 006; a retired item is `retired`, the current
  year is `in_progress`, and no value is `no_value`;
- `deadline_line` gives `is_met` the last value stored on or before the end of the deadline day;
- `series` leaves a gap as a gap;
- `link_months` and `contribution` count milestones by `done_on` inside the link dates;
- `theme_hint` uses the 25% threshold and states two numbers;
- `year_split` sums stored category counts, with `percentages` from feature 005;
- `month_statuses` and `coverage` describe the twelve months.

The rules import `is_met`, `year_state`, `percentages` and `CategoryCounts`. They do not restate
them.

## Precision

The hit and deadline lines use monthly snapshots. A value that was entered and replaced inside one
month is not visible. The docs and the screen say "from a snapshot". A value entered after the last
snapshot of a past year appears in `moved_after_snapshot` and never changes the result.

## The no-write guarantee

Opening the review writes nothing. `backend/tests/integration/test_annual_review_no_write.py`
compares the rows of every table before and after the read, and scans the source for writes and for
reads of task tables. The only write is a review note.

## Snapshot payload changes

`read_snapshot` gives `None` for a missing or malformed field. A new key is ignored until the
reader knows it. Raise `schema_version` in feature 007 when you add a field, then extend
`SnapshotView` and the reader. An old snapshot keeps loading as far as its keys allow.

## Tests

- Unit rules: `backend/tests/unit/test_annual_review_rules.py`, `test_snapshot_view.py`,
  `test_annual_review_schema.py`.
- Integration: `backend/tests/integration/test_annual_review_*.py`, `test_review_notes.py`.
- Migration: `backend/tests/migrations/test_migrations.py` (0023).
- E2E: `backend/tests/e2e/test_annual_review_api.py`.
- Smoke test over HTTP: `backend/tests/live/test_annual_review_live.py`.

## Seed data for a walkthrough

`just backend::seed-annual-review` writes fake snapshots and prints the sign-in details. It uses
the same `store_snapshot` helper as the tests and writes no task data.
