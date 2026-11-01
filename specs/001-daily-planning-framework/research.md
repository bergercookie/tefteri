# Research: Tefteri Planning Framework

All decisions below resolve open technical questions from the plan. Decisions explicitly
requested by the user are marked **(user)**.

## R-01 Backend stack **(user)**
- **Decision**: FastAPI + pydantic v2 + async SQLAlchemy 2.x, Alembic for migrations, uv for
  Python dependency locking.
- **Rationale**: Async fits I/O-heavy sync work against three external APIs; pydantic gives
  validated schemas and an OpenAPI document for free.
- **Alternatives**: Django (heavier, sync-first), Litestar (smaller ecosystem).

## R-02 Database **(user)**
- **Decision**: SQLite by default via aiosqlite; PostgreSQL optionally via asyncpg. One
  `TEFTERI_DATABASE_URL` setting selects it. Only portable SQLAlchemy constructs are used;
  CI runs integration tests against both.
- **Rationale**: Zero-setup for households, Postgres when needed. Testing both prevents drift.
- **Alternatives**: Postgres only (heavier install); SQLite only (does not meet the request).

## R-03 Backend quality tooling **(user)**
- **Decision**: ruff (lint + format), mypy (strict), tach (module boundaries), pytest. All four
  run over `backend/src`, `backend/tests` (unit, integration, e2e, smoke) and scripts written
  in Python.
- **Rationale**: One configuration in `backend/pyproject.toml` / `tach.toml`, so no part of
  the codebase is exempt.

## R-04 Pre-commit as the single check file **(user)**
- **Decision**: `.pre-commit-config.yaml` lists every check. Hooks are `language: system` and
  call `just <recipe>` for tool-specific steps, so the tool invocation lives in the justfile
  modules. `just lint` runs `pre-commit run --all-files`. Recipes that hooks call MUST NOT
  call `just lint`, which would be circular.
- **Rationale**: Developers, CI and agents get identical checks and use only `just`.
- **Alternatives**: Separate lint recipes per tool without pre-commit (loses the one-file
  overview and git-hook integration).

## R-05 Linter for every technology **(user)**

| Technology | Tool |
|------------|------|
| Python | ruff, mypy, tach |
| Dart/Flutter | `dart format`, `flutter analyze` with `flutter_lints` (`analysis_options.yaml`) |
| Bash | shellcheck, shfmt |
| Dockerfile | hadolint |
| docker compose files | `docker compose config` validation |
| YAML (incl. workflows) | yamllint, actionlint for GitHub workflows |
| Markdown | markdownlint-cli2; docs also built by Sphinx with warnings as errors |
| TOML | taplo |
| justfiles | `just --fmt --check --unstable` |
| JSON | pre-commit `check-json` |

Each tool has its configuration file committed (for example `.yamllint.yaml`,
`.markdownlint-cli2.yaml`, `.hadolint.yaml`, `.shellcheckrc`, `taplo.toml`). Adding a new
technology requires adding its linter and configuration in the same change.

## R-06 Justfile layout **(user)**
- **Decision**: Root `justfile` uses `import` for `backend/backend.just`,
  `frontend/frontend.just`, `deploy/deploy.just`, `docs/docs.just` and
  `packaging/packaging.just`. Because `import` shares one namespace, recipes are prefixed
  (`backend-test`, `frontend-build`, `deploy-up`, ...). Top-level aggregators exist as
  `just test`, `just lint`, `just build`, `just run`, `just deploy`.
- **Rationale**: Small files per area, one flat discoverable command list (`just --list`).
- **Alternatives**: `mod` (namespaced, but changes the call syntax and working directory
  semantics; the user asked for imports).

## R-07 CI **(user)**
- **Decision**: GitHub Actions workflows install devbox (via the devbox GitHub action) and run
  `devbox run -- just <recipe>`. No workflow calls `pre-commit`, `mypy`, etc. directly.
  Docker and the Android SDK are provisioned by the runner or an action where devbox cannot
  provide them.
- **Rationale**: Matches constitution principle II and III.

## R-08 Documentation **(user)**
- **Decision**: Markdown in `docs/`, built by Sphinx with `myst-parser`; `just docs-build`
  uses `-W` so warnings fail the build. Spec Kit files under `specs/` are not part of the
  published docs.
- **Rationale**: Plain Markdown remains readable on GitHub and renders in Sphinx.

## R-09 Releases **(user)**
- **Decision**: Pushing a tag `vX.Y.Z` triggers `release.yml`, which runs `just` recipes to
  build: the Linux client `.deb` and AppImage, the Android `.apk`, and the server Docker image.
  It creates a GitHub release with the three client artifacts attached and pushes the image
  to `ghcr.io/bergercookie/tefteri` tagged `X.Y.Z` and `latest`.
- **Interpretation**: The `.deb`, AppImage and `.apk` are Flutter **client** packages. The
  server ships as the Docker image. If a server `.deb` is also wanted, it can be added later.
- **Android signing**: the `.apk` is signed with a release keystore stored as a repository
  secret; without it, only debug-signed APKs can be produced.

## R-10 Nightly builds and version format **(user)**
- **Decision**: A scheduled workflow builds the default branch nightly if `HEAD` differs from
  the last nightly. Version string: `<previous-stable>.<short-hash>.post<N>`, for example
  `1.4.0.a1b2c3d.post3`. `N` is one more than the highest `post` number already published for
  that previous stable release (read from existing nightly image tags via the GitHub API),
  starting at 1 after each stable release.
- **Publishing**: Docker tags `nightly` (moving) and the full version string on
  `ghcr.io/bergercookie/tefteri`; client artifacts go to a rolling pre-release named `nightly`.
  Computation lives in one shellcheck-clean script behind `just version-nightly`.
- **Caveat**: `<prev>.<hash>.postN` is **not a valid PEP 440 version** (a hash is not a
  numeric release segment). It is used as the artifact/image identifier. Inside the packages
  the equivalent valid forms are used: Python `1.4.0.post3+a1b2c3d` and Flutter
  `1.4.0+<N>`. A test asserts that both forms are derived from the same inputs.
- **Alternatives**: Using only PEP 440 everywhere (cleanest, but does not match the requested
  format).

## R-11 Sync design
- **Decision**: Sync is triggered from the API, runs per connection, and returns a per-
  connection result. Each connection stores a cursor/ETag/`updated` marker where the app
  offers it, otherwise a full comparison by remote id. Local edits made through tefteri are
  applied to the remote app immediately and mirrored to the cache; when the remote has changed
  since the cached version, the item enters a `conflict` state and nothing is overwritten
  (spec FR-008). Failures in one connection do not abort others.
- **Adapters**: Vikunja REST API (token auth); Google Calendar API via OAuth2, one
  credential per Google account, multiple calendars per account (personal, shared family,
  company); Trilium Next ETAPI (token auth).
- **Open check**: Company Google Workspace accounts may need the organisation's approval of
  the OAuth client; documented in the connection guide.

## R-12 Reproducible environments (devbox)
- **Decision**: `devbox.json` pins python, uv, just, pre-commit, shellcheck, shfmt, hadolint,
  yamllint, actionlint, markdownlint, taplo and flutter. Docker is installed by the user.
  The Android SDK is attempted through devbox; if that is unreliable it is documented as a
  second exception (like Docker) in the README.
- **Risk**: Flutter Linux packaging needs system libraries (GTK, etc.) that must also be
  declared.

## R-13 Authentication
- **Decision**: Password logins verify against an Argon2 hash stored per user. The initial
  admin comes from `TEFTERI_ADMIN_USERNAME` and `TEFTERI_ADMIN_PASSWORD_HASH` (pre-computed
  hash, never a raw password); the server refuses to start on a value that is not a valid
  hash. Admin-only account creation; no self-registration. Optional OIDC login via Authlib
  (Authorization Code with PKCE); either method can be disabled. API access uses an expiring
  bearer token / secure session cookie issued after login.
- **Rationale**: Meets FR-022, FR-023, FR-015.

## R-14 Secrets at rest
- **Decision**: App tokens and OAuth refresh tokens are encrypted with a key supplied through
  configuration (Fernet). Losing the key means users reconnect their apps; nothing else is
  lost.

## R-15 Client
- **Decision**: Flutter with Riverpod for state, go_router, dio for HTTP; client generated
  against the OpenAPI document where practical. Views: daily, weekly, monthly, annual, goals,
  review, notes, settings/connections, plus a global sync button and
  all/life/work switch. Navigation between views uses Flutter's `Shortcuts`/`Actions` with a
  central keymap (`frontend/lib/core/shortcuts/`) and a help overlay; plain-key shortcuts are
  disabled while a text field has focus.
- **Alternatives**: A web-only UI (does not meet the Flutter requirement).

## R-16 HTTP client **(user)**
- **Decision**: Use `httpx` for all adapter and OIDC HTTP calls. `httpx2` (Pydantic's
  continuation of httpx) was considered and rejected by the user.
- **Rationale**: Established ecosystem support: `respx` for mocking, Authlib's httpx
  integration and FastAPI's `TestClient` all work with `httpx` directly.
