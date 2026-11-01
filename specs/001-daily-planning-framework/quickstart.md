# Quickstart: Validating Tefteri

Everything is run through `just`. Run `just --list` for the full set of recipes.

## Prerequisites
- devbox installed (`devbox shell` provides Python, uv, just, linters and Flutter).
- Docker installed separately (documented exception) for image and Postgres scenarios.

## 1. Quality gate
```bash
just lint        # pre-commit: all linters (ruff, mypy, tach, dart, shellcheck, yamllint, vale, ...)
just test        # backend and frontend tests
just docs::build  # Sphinx + MyST, warnings as errors
```
Expected: all pass; any linter finding, STE style finding (Vale) or doc warning fails the command.

## 2. Run the server (SQLite)
```bash
export TEFTERI_ADMIN_USERNAME=admin
export TEFTERI_ADMIN_PASSWORD_HASH='<argon2 hash, from `just hash-password`>'
just run
```
Expected: server starts; it refuses to start if the admin value is not a valid hash.

## 3. Validate the P1 flow with fake backends
```bash
just backend::e2e
```
Expected: connects fake Vikunja/Google/Trilium backends, syncs, creates/completes a task,
schedules it (task date written back, no calendar event created), appends a daily note, and
reports a conflict that is resolved by choice.

## 4. Postgres
```bash
just deploy::up-postgres      # compose with Postgres
just backend::test-postgres   # integration tests against Postgres
```

## 5. Release artifacts
```bash
just packaging::deb; just packaging::appimage; just packaging::apk   # client packages
just deploy::build-image      # server Docker image
just version-nightly         # prints <prev-stable>.<hash>.postN
```
CI performs the same through `just` on a tag push (release) and on a schedule (nightly,
image `ghcr.io/bergercookie/tefteri:nightly`).

## 6. Manual check with real apps
1. Connect Vikunja, one or more Google accounts and Trilium Next in Settings → Connections.
2. Press **Sync**; verify items and the last-sync time.
3. Switch the all/life/work selector and confirm only matching items remain on every view.
4. Break an annual goal into monthly/weekly goals and tasks, schedule one, and confirm the
   date appears in Vikunja.
5. At the end of a period, open the review and save a retrospective; confirm the note in Trilium.
6. Stop the Vikunja service and press **Sync**; confirm tefteri names the connection and the
   reason, offers retry/reconnect, and neither applies nor queues any change silently.
7. Timed checks (manual, from the spec's success criteria): connect the three apps in under
   10 minutes (SC-001), plan a full week in under 10 minutes (SC-006), and complete the daily
   flow on first attempt (SC-009). The review opening in under 5 seconds (SC-008) is
   also covered by an automated test.
8. With a keyboard, reach each of the daily, weekly, monthly, annual, goals, review, notes and
   settings views using shortcuts alone, open the shortcut help, and confirm shortcuts do not
   trigger while typing in a text field (SC-010).
9. Documentation: open the built docs (`just docs::build`). Confirm that `user/` and
   `developer/` are separate sections, that each user guide can be followed without reading
   code, and that `vale` reports no findings on the README, CONTRIBUTING and `docs/`.
10. Screenshots: run `just docs::screenshots`. Confirm that `docs/images/` has changes only for
   screens you changed, that each user guide shows the screen it describes with alt text, and that
   no image shows real credentials or personal data.
