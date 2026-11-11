# Quickstart: Project Classification and Onboarding

Run guide that proves the feature works. Contract details are in [contracts/api.md](contracts/api.md) and the tables in [data-model.md](data-model.md).

## Prerequisites

```bash
source /root/tefteri-env.sh   # session helper; on a normal machine use devbox shell
just backend::test
just frontend::test
```

## 1. Automated checks

```bash
just backend::test             # unit and integration
just backend::test-postgres    # migration 0018 on Postgres
just backend::live-vikunja     # rename, restore and archive against a real Vikunja
just frontend::test
just docs::check
just lint
```

Expected: all pass.

## 2. First-time user walkthrough (manual or with the browser script)

Goal: a new user sorts their projects in under 10 minutes without reading the docs.

1. Start a throw-away Vikunja: `bash scripts/vikunja-dev.sh start`. Create a user and an API token, and a tree of projects: three top-level (`Open source`, `Work`, `Admin`) with sub-projects, and one very old project (`Old stuff`).
2. Start the app: `just backend::run` and `just frontend::run`. Sign in and connect the Vikunja.
3. After the first sync a card says "Sort your projects" with the count. Open it.
4. Check: every project already shows a suggested label. Top-level projects show "Theme (suggestion)", deeper ones "Milestone (suggestion)". Each group has a one-sentence explanation.
5. Tap "Admin" and choose "Routine". Tap "Old stuff" and choose "Ignored". Rename one project. Press "Accept suggestions" for the rest.
6. Check: the summary says what will change before saving. After saving an "Undo" action is shown. Tap it and check the labels go back.
7. Save again. Open weekly planning. Check: "Admin" and "Old stuff" are not in the project picker.
8. In Vikunja rename "Open source" and delete "Work". Press sync in Tefteri. Check: the label stays on the renamed project. "Work" is in the group "No longer in your task app" with its label and does not break the weekly page.
9. Check the empty states: remove every project in a second Vikunja account and open the Projects screen. It offers "Sync now" and "Create a theme".
10. Check on a phone-sized window and in dark mode: nothing is cut off and the chips are readable.

## 3. Evidence to keep

- Screenshots from `just docs::screenshots` in light and dark and in both widths.
- The result of the browser walkthrough (one screenshot per step) kept in the session notes, not committed.
