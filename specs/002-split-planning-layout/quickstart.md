# Quickstart: Validate the Split Planning Layout

Run everything through `just` inside `devbox shell` (constitution Principle II).

## Automated checks
```bash
just backend::test       # unit, integration, e2e incl. scheduling, filters, settings, migration
just frontend::test      # widget tests incl. planner drag and drop, filters, search, narrow
just lint
just docs::screenshots   # regenerates planner screenshots from golden tests
just docs::build         # warnings are errors
```

## Manual scenario (about 5 minutes)
Prerequisites: a running stack (`just run`), a user with a connected Vikunja and Google
Calendar (the e2e fake world can stand in), and a handful of tasks: two due today, one
tomorrow, one overdue, three with no due date.

1. Open the app. **Expect** the planner: task column on the left, calendar on the right, filter
   "Today" active (spec SC-004, FR-001, FR-018).
2. Click each filter. **Expect** the matching tasks and counts (FR-018). Type part of a title in
   the search bar. **Expect** matches from all open tasks (FR-019).
3. Drag a task with no due date onto Wednesday 14:00. **Expect** a block 14:00–15:00; in
   Vikunja the due date is Wednesday 15:00 and no start or end date is set (FR-004, FR-006,
   FR-007, FR-008).
4. Drag that block to Thursday 10:15. **Expect** due Thursday 11:15 (FR-005).
5. Drag it back to the task column. **Expect** it is unscheduled, due date cleared (FR-005).
6. Drag a task onto the all-day row. **Expect** an all-day item and a date-only due date
   (FR-017). Turn on "random time for date-only drops" in settings and repeat. **Expect** a
   timed block between 08:00 and 20:00.
7. In Vikunja set a due date and time on a task and press sync in tefteri. **Expect** the block
   in the right slot (FR-009). Set a date without time. **Expect** the all-day row (FR-010).
8. Stop Vikunja and drop a task. **Expect** an error that names the connection and the task
   does not show as scheduled (FR-012).
9. Shrink the window below 840 dp. **Expect** two tabs and a "Schedule…" action that works
   without dragging (FR-014, SC-005).

## Contract and data references
See [contracts/api.md](contracts/api.md) and [data-model.md](data-model.md).
