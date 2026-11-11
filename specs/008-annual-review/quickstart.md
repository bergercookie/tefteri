# Quickstart: Annual Review

Run guide that proves the feature works. Contract details are in [contracts/api.md](contracts/api.md) and the tables in [data-model.md](data-model.md). Features 003, 004, 005, 006 and 007 must be built first: this feature reads their data.

## Prerequisites

```bash
source /root/tefteri-env.sh   # session helper; on a normal machine use devbox shell
just backend::test
just frontend::test
```

## 1. Automated checks

```bash
just backend::test             # unit and integration, incl. no-write and no-task-read tests
just backend::e2e              # the review and notes routes
just backend::test-postgres    # migration 0023 on Postgres
just backend::live-vikunja     # the smoke test of the real server over HTTP (live task app)
just frontend::test
just frontend::analyze
just docs::check
just lint
```

Expected: all pass. The smoke test starts the real server, stores snapshots for a fake year, calls `GET /annual-review/{year}` over HTTP and checks status 200 and the schema for a year that shows every outcome, every deadline state, every month status and every hint.

## 2. Counts to keep in the pull request

Run the seed (section 3, step 1) and record: rows in `review_notes`, `monthly_review_snapshots`, `key_results`, `key_result_themes` and `goals` before and after opening the review of every seeded year. Expected: equal, apart from the notes the walkthrough adds (SC-002).

## 3. First-time walkthrough (manual or with the browser script)

Goal: a user reads a past year in under 10 seconds per key result, without the docs (SC-001).

1. Seed the data. Start a throw-away task app with `just backend::vikunja-up`, then run `just backend::seed-annual-review`. The seed makes fake data only: a user, a tree of themes, goals and key results for the previous year (two goals, three key results, one retired goal), links with one theme re-linked in August, one orphaned theme, and monthly snapshots for 8 of 12 months (one with a second version, one in the older shape with no categories). It also makes the current year (in progress) and one year with no snapshots. It prints the sign-in details.
2. Start the app: `just serve` (web client and server). Sign in. The browser test injects the long session token through the API, not by typing, because the Flutter web client draws on a canvas.
3. Open "Year review" (key `y`). Go to the seeded year.
4. Check: every goal is listed with its key results. Each key result shows start, target, last value with its month, "Hit" or "Missed", the line "Reached by deadline", and twelve monthly values with gaps for the four missing months. The rule for hit and missed is on the screen.
5. Check: a key result that passed the target and fell back shows "Missed", the peak in the series, and "Reached by deadline: yes".
6. Check: the retired goal shows its retirement date and no hit or missed. The re-linked theme shows two date ranges.
7. Check: under a key result, each theme shows milestones shipped and the key result movement. The quiet hint shows only where the rule says so, and it names no cause.
8. Check: the year bar equals the sum of the month rows. Percentages add up to 100. The hidden count is a separate part. Open the drill-down of one category. It says "Live list, may differ from the bar".
9. Check: the four missing months are marked. Each has an action that opens that month's review. Every total says "8 of 12 months".
10. Check: the orphaned theme shows its stored name, the orphaned mark and the reason, and its numbers.
11. Add a note to a goal and to the year. Reload. The notes are back. Delete one. The screen shows the lost text and offers Undo. Use Undo.
12. Open "Start next year". Annual planning opens with "from year" set to the reviewed year. Leave without saving. Go back. Nothing was created (check the counts of section 2).
13. Open the year with no snapshots: the page loads, says that no monthly review was stored, and shows goals and key results with their current values. Open the current year: it is shown as "In progress" and claims no final result. Open a future year: an empty state.
14. Open the history (`/review`) from "Earlier reviews of this year". The stored period reviews load unchanged. Month and week goals are not on the review page.
15. Check on a phone-sized window and in dark mode: nothing is cut off, the series and the bar stay readable, and the touch targets are large enough.

## 4. Evidence to keep

- Screenshots from `just docs::screenshots` in light and dark and in both widths.
- The result of the browser walkthrough (one screenshot per step) kept in the session notes, not committed.
- The counts of section 2.
