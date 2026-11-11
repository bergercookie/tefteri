# Quickstart: Weekly Planning and Review with Milestone Projects

Run guide that proves the feature works. Contract details are in [contracts/api.md](contracts/api.md) and the tables in [data-model.md](data-model.md).

## Prerequisites

```bash
source /root/tefteri-env.sh   # session helper; on a normal machine use devbox shell
just backend::test
just frontend::test
```

## 1. Automated checks

```bash
just backend::test             # unit and integration, incl. the weekly and milestone tests
just backend::test-postgres    # migration 0019 on Postgres
just backend::live-vikunja     # move_task and the weekly loop against a real Vikunja
just backend::openapi          # regenerate docs/openapi.json; the snapshot test must pass
just frontend::test
just frontend::analyze
just docs::check
just lint
```

Expected: all pass. `just docs::screenshots` is run by hand and its images are committed.

## 2. Two-week walkthrough (manual or with the browser script)

Goal: a user who knows feature 003 plans one week with milestones, reviews it, and plans the next week, without reading the docs.

1. Start a throw-away Vikunja: `bash scripts/vikunja-dev.sh start`. Create a user and an API token. Create the themes `Open source` and `Home`, and the milestones `Ship the login flow` (five tasks) and `Fix the fence` (three tasks) under them. Create a top-level project `Inbox` with no label. Create one project `Taxes` and put it in a past weekly plan as a legacy entry with the choice carry (seed the database or use the old API fixture).
2. Start the app: `just backend::run` and `just frontend::run` (or `just serve`). Sign in, connect the Vikunja, open the Projects screen, accept the suggestions, set `Home` and `Open source` as themes and the two sub-projects as milestones.
3. Open Week. Start planning. Check the picker: milestones are grouped under their theme, `Inbox` is under "Unsorted", and `Taxes` appears as a milestone because it was in a past plan. No theme, routine or ignored project is offered.
4. Choose `Ship the login flow` and `Fix the fence`. Create a new milestone under `Home` named `Paint the shed` and leave the done-state empty. Check that it is refused with a hint and your text stays. Fill the done-state and create it. Choose a fourth milestone. Check the quiet warning "You chose 4 milestones". Commit anyway. Remove one. Check that the warning goes away.
5. In the step "Give tasks a day" add a task under a milestone from the page. Check that it exists in Vikunja. Give days to three of the five tasks of `Ship the login flow`. Check that the other two show as "Not this week". Commit.
6. In Vikunja close every task of `Fix the fence`. Press refresh. Check that the milestone shows as done with today's date and the theme.
7. Move to the next week (or use a clock override). Open the look-back. Check the numbers: committed tasks done out of committed, milestones finished out of committed, the pace per day, and the work done outside the plan. Check that no goal question appears.
8. Decide: recommit `Ship the login flow` and leave "expected" off. Park `Paint the shed`. Close `Home` milestone tasks: for a milestone with open tasks press "Close and return tasks". Check the dialog says "N open tasks will move to Home". Confirm. Check in Vikunja that the tasks are now in `Home`. Press "Reopen" in the review and check that they go back.
9. Try a milestone with no choice. Press "Save the look-back". Check that the review names it and offers "Decide later for all of these". Use it. Check that the milestone is unchanged.
10. Open the next week's picker. Check: `Ship the login flow` is already committed with rollover count 1, `Paint the shed` is shown as parked, and the milestone left with "Decide later" shows a reminder.
11. Recommit `Ship the login flow` again in a third review without the "expected" marker. Check that the nudge "This milestone rolled over twice. Shrink it, split it or close it." appears and that committing still works. Repeat with the marker on one more rollover and check that no nudge shows.
12. Open the history. Check that the legacy week shows `Taxes` as "Keep and recommit".
13. Remove `Ship the login flow` in Vikunja and sync. Check that the weekly pages still load with the stored name and the label "orphaned".
14. Stop the connector's move capability (use the fake or a connector without it) and check that the close option is hidden with a line that says why.
15. Check a phone-sized window and dark mode on the picker, the review and the close dialog: nothing is cut off and the text is readable.

## 3. Evidence to keep

- Screenshots from `just docs::screenshots` in light and dark and in both widths.
- One screenshot per step of the browser walkthrough, kept in the session notes, not committed.
- The list of usability findings and what fixed each one (task T080 and T081 of [tasks.md](tasks.md)).
