# Backend recipes (run with the module directory as cwd). Call as `just backend::<recipe>`.

# List the recipes of this module.
default:
    @just --list backend

install:
    uv sync

test:
    uv run pytest -m "not postgres and not live" --ignore=tests/smoke --ignore=tests/live

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

seed-demo:
    #!/usr/bin/env bash
    set -euo pipefail
    # Requires an explicit loopback URL, absolute *-demo.db URL, secret key, and confirmation.
    uv run --project backend python scripts/seed_demo.py

# Write fake annual-review data. Set TEFTERI_DATABASE_URL to an absolute sqlite *-demo.db file.
seed-annual-review:
    #!/usr/bin/env bash
    set -euo pipefail
    uv run --project backend python scripts/seed_annual_review.py

# Start a throw-away Vikunja, run the live tests against it, then stop it. These tests are not
# part of `just test`. With TEFTERI_LIVE_VIKUNJA_URL set, they use that server and start nothing.
# Extra arguments go to pytest, for example `just backend::live-vikunja -k move`.
live-vikunja *args:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -z "${TEFTERI_LIVE_VIKUNJA_URL:-}" ]; then
        TEFTERI_LIVE_VIKUNJA_URL=$(../scripts/vikunja-dev.sh start)
        export TEFTERI_LIVE_VIKUNJA_URL
        trap '../scripts/vikunja-dev.sh stop' EXIT
    fi
    echo "Live tests against ${TEFTERI_LIVE_VIKUNJA_URL}"
    uv run pytest tests/live -m live -p no:cacheprovider {{ args }}

# Start the throw-away Vikunja and keep it running, for manual work. Stop it with vikunja-down.
vikunja-up:
    ../scripts/vikunja-dev.sh start

vikunja-down:
    ../scripts/vikunja-dev.sh stop
