# Quickstart: Monthly Planning and Review

Run guide that proves the feature works. Contract details are in [contracts/api.md](contracts/api.md) and the tables in [data-model.md](data-model.md).

## Prerequisites

Features 003, 004, 005 and 006 are implemented.

```bash
source /root/tefteri-env.sh   # session helper; on a normal machine use devbox shell
just backend::test
just frontend::test
```

## 1. Automated checks

```bash
just backend::test             # unit and integration, incl. the 0022 migration tests
just backend::e2e              # the monthly routes
just backend::test-postgres    # migration 0022 and a monthly flow on Postgres
just backend::live-vikunja     # the cycle in process, and the smoke test of the real server over HTTP
just frontend::test
just docs::check
just lint
```

Expected: all pass.

## 2. Existing data survives the change

1. Take a copy of a database that has month goals, a stored period review and a monthly checklist with ticks (the migration test builds one).
2. Count before: `goals` by `period_type`, `period_reviews`, `checklists` and their items.
3. Run `just backend::migrate`.
4. Count after: the numbers are the same, and no row changed.
5. Open an old month in the new Month screen. It shows the read-only "earlier format" view with the old goals and offers no edit. No snapshot exists for it.
6. Open the old stored period review in the review screens. It loads as before.

## 3. First-time user walkthrough (manual or with the browser script)

Goal: a user plans a month with three themes in under 3 minutes (SC-001) and finishes the review of a month with five themes in under 10 minutes (SC-002), without reading the docs.

1. Start a throw-away Vikunja and seed it: `just backend::vikunja-up`, then `just backend::seed-demo`. The seed makes eight theme projects with milestones done in three months (some under no theme), key results with series values (one manual, one automatic) linked to two themes, and tasks of all three work categories with a rising off-plan share. One theme is deleted in Vikunja after the first sync, so it is orphaned.
2. Start the app: `just serve`. Sign in, connect the Vikunja and sync.
3. Open `Month` for the current month. A quiet hint explains "monthly focus" once. The screen has no goal list and no control to add a goal. The monthly checklist is at the top and works.
4. Open the picker. Only live themes are listed. The orphaned theme, milestones and routines are not. Search for a theme by name. Pick six themes. Check the quiet note that three to five is usual. Remove three. Check that the note goes away.
5. Set targets: 3 for the first theme, 0 for the second and leave the third empty. Try -1, 2.5 and "abc". Check the clear message and that nothing is saved. Save, reload and check 3, 0 and "no target".
6. Check the key results beside the themes: start value, latest value with time stamp, target, deadline. One key result has no theme in focus and is flagged quietly with its goal. A theme with no key result says "not linked to a key result".
7. Empty state: in a second account with no theme, open the picker. Check the explanation and both inline actions. "Label a project as theme" works from the picker. "Create a theme" creates the project in Vikunja first (check it there) and then picks it. Stop the Vikunja and try again: an error shows and nothing is stored.
8. Open weekly planning. Check that the three focus themes are shown first and highlighted, and that the other themes are still offered. Commit four milestones: the cap only warns.
9. Mid-month change: swap the second theme for another one. Check that the screen shows the effect first (counts from today, finished work and weekly commitments stay). Confirm. Check the history line and the date. Choose Undo and check that the old theme is back. Swap again and keep it.
10. In Vikunja complete the tasks of two milestones under the first theme, one under the swapped-in theme and one under a theme that is not in the focus. Sync Tefteri.
11. Open the review (it shows the label "Draft"). Check: the first theme shows its result against 3 with the right marker, the swapped-in theme counts from the swap date, the earlier milestone of that theme is shown apart, the swapped-out theme is listed with its target and result, and the milestone of the theme that is not in the focus is in "outside focus". A milestone with no parent theme is under "no theme".
12. Key results: the automatic one shows its latest value and time stamp and no prompt. A value older than the month shows "not updated this month". For the manual one, type a new value. Check that the gap shows the milestones shipped next to base value, latest value and change, with no cause claimed. Check that a key result with two themes is listed under both and marked shared. Skip another manual one.
13. Work categories: check the three counts and the hidden line, and the "rising" marker on off-plan. Check that each category is explained once and that a steady maintenance share has no marker.
14. Decisions: carry one theme, drop one, replace one with another theme. Check the effect line for each and the hint that "replace" is the month-end decision and "swap" is the change during the month. Leave one theme undecided and finish: the review asks once and then stores it.
15. Check that the typed key result value is now in the series (open the annual plan and its value list).
16. Open the next month. Check the suggestions: the carried theme with its target and the replacement theme with no target, no dropped theme, and the month they come from. Nothing is saved until Save.
17. Immutability: in Vikunja rename a theme, delete a milestone and a task. Sync. Open the stored review: every name and number is as before.
18. Reopen the review, change a decision and save. Check the notice that this creates a new version and keeps the old one. Open the versions, make version 1 current again, and check that the next month's suggestions follow the current version.
19. Leave the review halfway (go to another screen and back): the draft is still there.
20. Check a phone-sized window and dark mode: nothing is cut off, markers and chips are readable, and the key result rows do not overflow.

## 4. Smoke test of the real server (automated)

`just backend::live-vikunja` runs `backend/tests/live/test_monthly_http_live.py`. It starts the real server on a port, calls every monthly route over HTTP against a live Vikunja, and checks that no answer is a 500 and that every answer parses with its response model. The data covers every enum value of the response models, so a schema that misses a new value fails here and not in production.

## 5. Evidence to keep

- Screenshots from `just docs::screenshots` in light and dark and in both widths.
- The result of the browser walkthrough (one screenshot per step) kept in the session notes, not committed.
- The counts of step 2 in the pull request description.
