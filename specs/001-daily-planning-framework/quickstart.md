# Quickstart: Validating Tefteri

Everything is run through `just`. Run `just --list` for the full set of recipes.

## Prerequisites
- devbox installed (`devbox shell` provides Python, uv, just, linters and Flutter).
- Docker installed separately (documented exception) for image and Postgres scenarios.

## 1. Quality gate
```bash
just lint        # pre-commit: all linters (ruff, mypy, tach, dart, shellcheck, yamllint, ...)
just test        # backend and frontend tests
just docs-build  # Sphinx + MyST, warnings as errors
```
Expected: all pass; any linter finding or doc warning fails the command.

## 2. Run the server (SQLite)
```bash
export TEFTERI_ADMIN_USERNAME=admin
export TEFTERI_ADMIN_PASSWORD_HASH='<argon2 hash, from `just hash-password`>'
just run
```
Expected: server starts; it refuses to start if the admin value is not a valid hash.

## 3. Validate the P1 flow with fake backends
```bash
just backend-e2e
```
Expected: connects fake Vikunja/Google/Trilium backends, syncs, creates/completes a task,
schedules it (task date written back, no calendar event created), appends a daily note, and
reports a conflict that is resolved by choice.

## 4. Postgres
```bash
just deploy-up-postgres      # compose with Postgres
just backend-test-postgres   # integration tests against Postgres
```

## 5. Release artifacts
```bash
just build-client            # .deb, AppImage, .apk (build recipes in packaging.just)
just build-image             # server Docker image
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
