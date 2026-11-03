# Tefteri server image. Build from the repository root: `just deploy::build-image`.

FROM python:3.12-slim AS build
COPY --from=ghcr.io/astral-sh/uv:0.12.22 /uv /usr/local/bin/uv
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_PYTHON_DOWNLOADS=never
WORKDIR /app
COPY backend/pyproject.toml backend/uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project
COPY backend/src ./src
# Release builds pass the PEP 440 version (from scripts/version.sh); /version reports it.
ARG TEFTERI_VERSION=""
RUN if [ -n "$TEFTERI_VERSION" ]; then \
      sed -i "s/^version = .*/version = \"$TEFTERI_VERSION\"/" pyproject.toml; \
    fi \
    && uv sync --frozen --no-dev --no-editable

FROM python:3.12-slim
RUN useradd --system --uid 10001 --home-dir /app tefteri \
    && mkdir /data \
    && chown tefteri /data
WORKDIR /app
COPY --from=build /app/.venv /app/.venv
COPY backend/alembic.ini ./
COPY backend/migrations ./migrations
COPY deploy/entrypoint.sh /usr/local/bin/tefteri-entrypoint
# Built on the host by `just deploy::build-image` (frontend::build-web).
COPY frontend/build/web ./web
ENV PATH=/app/.venv/bin:$PATH \
    TEFTERI_DATABASE_URL=sqlite+aiosqlite:////data/tefteri.db \
    TEFTERI_WEB_DIR=/app/web
USER tefteri
VOLUME /data
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s \
  CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health')"]
ENTRYPOINT ["tefteri-entrypoint"]
