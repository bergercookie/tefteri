# Tests and migrations

Every new behavior needs an automated test. `just test` runs the backend and the frontend
tests. The CI runs the same recipes.

## Backend tests

The backend tests are in `backend/tests/`:

| Folder | What the tests check |
| --- | --- |
| `unit/` | Single functions, for example the review computation and the version script. |
| `integration/` | The API and the services with a real SQLite database and fake apps. |
| `integration/adapters/` | Each adapter against recorded or faked HTTP answers (respx). |
| `e2e/` | Full user flows through HTTP. |
| `migrations/` | The Alembic migrations (pytest-alembic). |
| `smoke/` | The server image, alone and through `deploy/compose.yaml`. `just deploy::smoke` runs them. |

The tests of weekly planning with milestones are in `unit/test_milestones.py`,
`integration/test_milestone_*.py`, `integration/test_weekly_*.py`, `e2e/test_milestones_api.py` and
`migrations/test_migrations.py` (migration 0019 with old rows). Read
[Weekly planning](weekly-planning.md#test-it) for the list.

The tests of work categories and statistics are in `unit/test_work_categories.py`,
`unit/test_week_progress.py`, `unit/test_statistics_schema.py`,
`integration/test_work_categories_*.py`, `integration/test_statistics_*.py`,
`e2e/test_statistics_api.py` and `migrations/test_migrations.py` (migration 0021). The performance
tests check a week of 1,000 tasks and a year of 20,000 tasks. Read
[Work categories and statistics](work-categories.md#test-it) for the list.

Monthly planning and review rules are tested in `unit/test_monthly.py` and
`unit/test_monthly_review_rules.py`. The monthly integration tests cover focus changes, counting,
key results, categories, decisions, snapshots and the rule that monthly planning does not write
to the task app. The HTTP flow is in `e2e/test_monthly_api.py`. Read
[Monthly planning and review](monthly-cycle.md) for the data and read contracts.

The fake apps are in `tests/fakes/`. They keep their items in memory, and a test can make
them unreachable or make their credentials expire.

Recipes:

- `just backend::test` runs all tests except the smoke tests and the PostgreSQL tests.
- `just backend::e2e` runs only the end-to-end tests.
- `just backend::test-postgres` runs the tests with the `postgres` mark. Set
  `TEFTERI_TEST_POSTGRES_URL` first, for example to a database from `just deploy::up-postgres`.

## Live tests with a real Vikunja

The fake apps are only as good as our knowledge of the real apps. The live tests in
`backend/tests/live/` talk to a real Vikunja instead. They are **not** part of `just test` and
the CI does not run them. Run them by hand when you change the Vikunja adapter, the sync or the
scheduling code, and before a release.

```bash
just backend::live-vikunja
```

The recipe starts a throw-away Vikunja with `scripts/vikunja-dev.sh`, runs the tests and stops
Vikunja. The script downloads the binary from `dl.vikunja.io` once, checks its SHA-256 sum and
keeps it in `.cache/vikunja-dev/`. It works on Linux with an x86-64 CPU and needs no Docker.

| Setting | Meaning |
| --- | --- |
| `VIKUNJA_DEV_VERSION` | Version to run, for example `v2.7.1` (default) or `0.24.6`. |
| `VIKUNJA_DEV_PORT` | Port on 127.0.0.1 (default 3456). Use another port to run two versions at once. |
| `VIKUNJA_DEV_TIMEZONE` | Time zone of the Vikunja server (default `UTC`). Try `Europe/Athens`. |
| `TEFTERI_LIVE_VIKUNJA_URL` | Use this server and start nothing, for example a Vikunja in Docker. |
| `TEFTERI_LIVE_VIKUNJA_TOKEN` | A token of a user on that server. Without it, the tests register a new user. |

Never point the tests at a server with real data. They create users, projects and tasks.

Check the matrix before a release: the current version, the oldest version that you support
and a server in a time zone with an offset.

```bash
just backend::live-vikunja
VIKUNJA_DEV_VERSION=0.24.6 VIKUNJA_DEV_PORT=3457 just backend::live-vikunja
VIKUNJA_DEV_TIMEZONE=Europe/Athens VIKUNJA_DEV_PORT=3458 just backend::live-vikunja
```

To look at the server yourself, run `just backend::vikunja-up`. It prints the address and keeps
Vikunja running. Stop it with `just backend::vikunja-down`.

The live tests found two faults that the fake did not show:

- Vikunja answers a create with a nanosecond `updated` stamp, and a read with whole seconds. The
  version of a task was different in the two answers, so the next change raised a conflict.
  The adapter now compares whole seconds.
- A Vikunja server in a time zone with an offset sends times such as `11:00+02:00`. The cache
  (SQLite) keeps only the wall-clock part, so tefteri showed the time two hours late after each
  sync. The adapter and the cache now convert every time to UTC first.

The fake `tests/fakes/http/vikunja.py` can now run in a time zone (`FakeVikunja(timezone=...)`),
so the normal tests check the second fault too. When a live test finds a new difference, teach the
fake about it and add a normal test.

The tests `test_sync_performance.py` and `test_review_performance.py` check the speed targets of
the specification. A sync of 2,000 tasks, 1,000 events and 500 notes must take less than 30
seconds. A review of a year must open in less than 5 seconds.

The test `test_openapi_snapshot.py` compares the API with `docs/openapi.json`. When you change
the API, run `just backend::openapi` and commit the new file.

## Shared adapter contract

`integration/test_backend_contracts.py` holds one set of contract tests for each port: task,
calendar and notes. The tests run against the fake apps and against each real adapter with a
fake HTTP server. A new adapter must pass the same tests. Refer to
[Add an adapter](adding-an-adapter.md).

## Frontend tests

The frontend tests are in `frontend/test/`. They are Flutter widget tests with a fake HTTP
client (`test/support/fake_api.dart`). `just frontend::test` runs them.

The screenshot tests in `frontend/test/screenshots/` do not run in `just test`. They write the
images in `docs/images/`. Run `just docs::screenshots` by hand when a screen changes. Then look
at each changed image and commit it. Use fake data only.

## Migrations

The database schema changes only through Alembic migrations in `backend/migrations/versions/`.

1. Change the models in `backend/src/tefteri/db/models/`.
2. Add a migration file with the next number, for example `0006_<name>.py`.
3. Add a test for the new revision in `backend/tests/migrations/test_migrations.py`. Check the
   upgrade and the downgrade.
4. Run `just backend::test`. The built-in checks make sure that there is one head, that every
   migration goes up and down, and that the models match the migrations.

`just backend::migrate` applies the migrations to the database in `TEFTERI_DATABASE_URL`.
