#!/bin/sh
# Run the database migrations, then start the server.
set -eu
alembic upgrade head
exec uvicorn tefteri.main:create_app --factory --host 0.0.0.0 --port 8000 --proxy-headers
