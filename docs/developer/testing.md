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

The fake apps are in `tests/fakes/`. They keep their items in memory, and a test can make
them unreachable or make their credentials expire.

Recipes:

- `just backend::test` runs all tests except the smoke tests and the PostgreSQL tests.
- `just backend::e2e` runs only the end-to-end tests.
- `just backend::test-postgres` runs the tests with the `postgres` mark. Set
  `TEFTERI_TEST_POSTGRES_URL` first, for example to a database from `just deploy::up-postgres`.

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
