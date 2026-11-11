# Quickstart: Annual Planning, Goals and Key Results

Run guide that proves the feature works. Contract details are in [contracts/api.md](contracts/api.md) and the tables in [data-model.md](data-model.md).

## Prerequisites

```bash
source /root/tefteri-env.sh   # session helper; on a normal machine use devbox shell
just backend::test
just frontend::test
```

## 1. Automated checks

```bash
just backend::test             # unit and integration, incl. the 0020 migration tests
just backend::e2e              # the annual routes and the push
just backend::test-postgres    # migration 0020 and the concurrent limit of three on Postgres
just backend::live-vikunja     # create a theme in a real Vikunja through feature 003
just frontend::test
just docs::check
just lint
```

Expected: all pass.

## 2. Existing data survives the change

1. Take a copy of a database that has year, month and week goals, tasks linked to goals, and stored period reviews (the migration test builds one; a copy of real data also works).
2. Count before: `goals` by `period_type`, `tasks` with a `goal_id`, `period_reviews`.
3. Run `just backend::migrate`.
4. Count after: the numbers are the same. Dropped year goals are `retired`. Month and week rows are unchanged.
5. Open the annual plan for the year of an old year goal. The goal is there, with its old criteria text offered as a metric suggestion and no key result.
6. Open an old review. It loads as before.

## 3. First-time user walkthrough (manual or with the browser script)

Goal: a new user plans a year with two goals, three key results and links in under 15 minutes without reading the docs (SC-001).

1. Start a throw-away Vikunja and seed it: `just backend::vikunja-up`, then `just backend::seed-demo`. The seed makes a user, an API token, three top-level projects (`Open source`, `Work`, `Admin`) with sub-projects, and an old goal in Tefteri with a criteria text. It also labels `Open source` as theme and leaves `Work` unlabelled.
2. Start the app: `just serve`. Sign in and connect the Vikunja.
3. Open `Annual plan`. A quiet hint explains "planning year" once. Add the goal "Get better at open source". The goal shows a quiet note: it needs at least one key result.
4. Add a key result "Stars on the main repository", start 120, target 500, deadline in this year. Add a second one for the same goal. Try a fourth after adding a third: the screen says the limit is three.
5. Open the theme picker of the first key result. Only `Open source` is offered. A quiet note says that unsorted projects can be classified first.
6. Link `Open source`. The flag "no usable theme" is gone.
7. On the second key result open the picker, choose "Create a theme", type `Talks`, save. Check that the project exists in Vikunja and is a theme. Make Vikunja refuse the creation (stop the server) and check that nothing is stored and an error shows.
8. In Tefteri open `Projects` and mark `Open source` as ignored. Back on `Annual plan` the key result shows "no usable theme" with the theme name and the reason "ignored", and the inline actions "Link a theme" and "Create a theme".
9. Retire a key result. The dialog shows the effect first. Confirm and tap Undo. Open the history and check both lines.
10. Enter a value for a key result with a date. Check the current value and the progress bar. Enter a second value for an older date and check that the current value does not change.
11. Mark a key result as automatic. In the settings of the annual plan create the push token. Push a value with the `curl` example of [contracts/api.md](contracts/api.md) (use the fake host of your local server). Check that the value shows with the automatic mark. Push to a manual key result and check the `409 not_automatic` answer.
12. Switch to next year. Check that suggestions from this year show, that the "from year" field is set to this year, and that nothing is stored. Accept one goal and one unmet key result, edit the start value, save. Check that this year is unchanged.
13. Open the week view, the month view and the weekly planning flow. Check that no goal is offered. Open the history view and check that the old month and week goals show there and cannot be changed.
14. Open a task and open its goal picker. Only goals of this year's annual plan are offered.
15. Check a phone-sized window and dark mode: nothing is cut off, flags and chips are readable, and the key result rows do not overflow.

## 4. Evidence to keep

- Screenshots from `just docs::screenshots` in light and dark and in both widths.
- The result of the browser walkthrough (one screenshot per step) kept in the session notes, not committed.
- The counts of step 2 in the pull request description.
