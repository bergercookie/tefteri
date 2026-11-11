# Quickstart: Work Categories and Statistics

Run guide that proves the feature works. Contract details are in [contracts/api.md](contracts/api.md) and the tables in [data-model.md](data-model.md).

## Prerequisites

```bash
source /root/tefteri-env.sh   # session helper; on a normal machine use devbox shell
just backend::test
just frontend::test
```

Features 003 (labels), 004 (weekly commitment) and 006 must be merged. Migration `0021` follows `0020`.

## 1. Automated checks

```bash
just backend::test             # unit and integration, incl. the 1,000 and 20,000 task tests
just backend::e2e              # the routes, privacy, the OpenAPI snapshot
just backend::test-postgres    # migration 0021 on Postgres
just backend::live-vikunja     # smoke test of the real server over HTTP against a live task app
just frontend::test
just frontend::analyze
just docs::check
just lint
```

Expected: all pass.

## 2. Walkthrough with a seeded task app (manual or with the browser script)

Goal: a user sees the three work categories for a week, a month and a year, and can open every number.

1. Start a throw-away task app: `bash scripts/vikunja-dev.sh start`. Create a user, an API token and this tree: theme `Open source` with milestones `Ship the login flow` and `Write the docs`; theme `Home`; a maintenance project `Chores`; an ignored project `Old stuff`; an unlabelled project `Inbox`.
2. Start the app with `just serve`, sign in and connect the task app. Label the projects on the Projects screen (feature 003). Plan the current week and commit `Ship the login flow` (feature 004).
3. Complete tasks in the task app: three in `Ship the login flow`, two in `Write the docs` (not committed), two in `Chores`, one in `Home`, one in `Old stuff`, one in `Inbox`. Press sync in tefteri.
4. Open the Week view. Check: the card shows Goal-aligned 3, Maintenance 2, Off-plan 4 (two in `Write the docs`, one in `Home`, one in `Inbox` with the note "unsorted"), and the quiet line "1 task in ignored projects is not counted". The helper line says "Goal-aligned means work in a milestone you committed to this week." Each term has a one-sentence hint at its first use.
5. Check the three styles in a greyscale screenshot: icon, outline or hatch and the printed name tell them apart. Check light, dark, a phone width and a desktop width.
6. Open the Month view and the Year view. Check: three counts, one proportion bar, percentages that add up to 100, the counts next to them, and the same numbers as the week for this week's tasks. Tap a count: a list opens, grouped by project, newest first. Tap the hidden line: the task of `Old stuff` is listed.
7. Relabel `Chores` as theme, edit the commitment of this week, move a completed task to another project in the task app, press sync. Check: no count of an earlier task changes. Complete one more task in `Chores`: it is off-plan now.
8. Reopen one completed task and complete it again. Check: it counts once, with the new decision.
9. Delete a completed task in the task app and sync. Check: the count drops and the sync time is shown.
10. Seed 250 completed tasks in `Home` in one week through the API (long titles and ids are injected through the API, not typed on the canvas). Check: Off-plan shows 250 and the list reaches all 250 with "Show more".
11. Open a week with no completed task: no bar, a message and the action "Plan your week". On a new account with no labels: the message offers "Label your projects" and opens the Projects screen.
12. Disconnect the task app (stop it) and press sync. Check: the views still show the last numbers with the time of the last sync and a failed state, and nothing blocks.

## 3. Evidence to keep

- Screenshots from `just docs::screenshots` in light and dark and in both widths.
- The browser walkthrough with one screenshot per step, kept in the session notes, not committed.
- The greyscale screenshot of the three styles.
- The timing of the 1,000 task week and the 20,000 task year from the performance test.
