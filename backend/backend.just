# Backend recipes (run with the module directory as cwd). Call as `just backend::<recipe>`.

install:
    uv sync

test:
    uv run pytest -m "not postgres" --ignore=tests/smoke

e2e:
    uv run pytest tests/e2e

test-postgres:
    uv run pytest -m postgres

run:
    uv run uvicorn tefteri.main:create_app --factory --reload

openapi:
    uv run python -m tefteri.openapi ../docs/openapi.json

migrate:
    uv run alembic upgrade head
