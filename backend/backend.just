# Backend recipes (run with the module directory as cwd). Call as `just backend::<recipe>`.

install:
    uv sync

test:
    uv run pytest -m "not postgres" --ignore=tests/smoke

e2e:
    uv run pytest tests/e2e

test-postgres:
    uv run pytest -m postgres

# Extra arguments go to uvicorn, for example `just backend::run --host 0.0.0.0`.
run *args:
    uv run uvicorn tefteri.main:create_app --factory --reload {{ args }}

openapi:
    uv run python -m tefteri.openapi ../docs/openapi.json

migrate:
    uv run alembic upgrade head
