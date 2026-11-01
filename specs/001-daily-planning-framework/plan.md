# Implementation Plan: Tefteri Daily Planning & Execution Framework

**Branch**: `001-daily-planning-framework` | **Date**: 2026-11-01 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-daily-planning-framework/spec.md`

## Summary

Tefteri is a server-client planning framework. A Python backend exposes a REST API and syncs on
demand with the user's own apps (Vikunja for tasks, Google Calendar for events, Trilium Next
for notes) through adapter interfaces. A Flutter client (Linux desktop, Android, and web)
provides the daily, weekly, monthly and annual views, the work/life filter and the review
screens. tefteri's own store holds goals, plans, labels, reviews, users and cached copies of
synced items.

The plan also covers the repository's engineering system, which the user asked for explicitly:
one `justfile` with small per-directory `.just` modules as the only entry point, a single
pre-commit config for all linting, a linter per technology, CI and release workflows that call
only `just`, MyST/Sphinx docs, tagged releases (`.deb`, AppImage, `.apk`, Docker image) and a
nightly build with a computed version.

## Technical Context

**Language/Version**: Python 3.12 (backend); Dart/Flutter stable (frontend); Bash for scripts

**Primary Dependencies**: FastAPI, pydantic v2, SQLAlchemy 2.x (async) with Alembic, httpx
(app adapters), Authlib (OIDC), argon2-cffi (password verification), cryptography (token
encryption at rest). Flutter: Riverpod, go_router, dio, `flutter_lints`.

**Storage**: SQLite by default (aiosqlite); PostgreSQL optional (asyncpg), selected by one
database URL setting. Same models and migrations for both.

**Testing**: pytest (+ pytest-asyncio, respx for mocked HTTP, coverage) for backend unit,
integration, e2e and smoke tests; `flutter test` for the client.

**Target Platform**: Server: Linux container (Docker image) or direct run. Client: Linux
desktop (`.deb`, AppImage), Android (`.apk`), web.

**Project Type**: Web service + multi-platform client (backend + frontend in one repository)

**Performance Goals**: Per spec: sync of 2,000 tasks / 1,000 events / 500 notes in < 30 s
(SC-002); review screen opens in < 5 s (SC-008); ordinary reads from the local cache feel
instant (< 200 ms p95 for list endpoints on SQLite).

**Writing style**: All prose (README, CONTRIBUTING, `docs/user/`, `docs/developer/`) follows
ASD-STE100 Simplified Technical English (constitution Principle VI). Vale enforces the checkable rules (sentence length,
passive voice, contractions, simpler-word list) in pre-commit and CI. The official STE
dictionary is licensed, so the style is an approximation and reviewers apply the rest.

**Constraints**: User-triggered sync only; connected apps are assumed up and, when one is not, the user is told which one and why and can retry or reconnect (no offline editing or queued changes);
no raw passwords in configuration; per-user data isolation on every query; app tokens
encrypted at rest.

**Scale/Scope**: Households and small teams (≈ 1-50 users per installation); about 8 client
screens (daily, weekly, monthly, annual, goals, reviews, notes, settings/connections), with keyboard shortcuts for navigating between all views.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design. Checked against constitution v1.1.0.*

| Principle | Status | How the plan satisfies it |
|-----------|--------|---------------------------|
| I. Python backend, Flutter frontend | PASS | Backend in Python/FastAPI; client in Flutter. Bash is limited to thin scripts. |
| II. Justfile is the single interface | PASS | Root `justfile` declares `backend`, `frontend`, `deploy`, `docs` and `packaging` as just modules (`just backend::test`). CI and release workflows call `just` recipes only; pre-commit hooks call the linters directly. |
| III. Reproducible environments via devbox | PASS, with documented exceptions | `devbox.json` provides python, uv, just, pre-commit, linters, Flutter. Docker is the stated exception. Android SDK is the second likely exception if devbox cannot provide it reliably (see research R-12). |
| IV. Pluggable backends | PASS | Three ports (`TaskBackend`, `CalendarBackend`, `NoteBackend`) with one adapter each. `tach` enforces that core code cannot import adapters. Adapters are tested with recorded HTTP responses. |
| V. Documented, tested, CI-verified | PASS | mypy/ruff/tach/pytest across source, tests and e2e; pytest-alembic tests for every migration; per-technology linters; Vale checks prose against our ASD-STE100 rule set; Sphinx docs build with warnings as errors in CI. |
| VI. Documentation for two audiences (STE) | PASS | `docs/` is split into `docs/user/` (task-based end-user guides) and `docs/developer/` (architecture, `just`, contracts, release). All prose follows ASD-STE100; Vale (`.vale/styles/STE`) runs in pre-commit and, through `just lint`, in CI. Behaviour changes update the matching guide in the same change. See research R-13. |

No violations, so Complexity Tracking is empty. Re-check after Phase 1 (with Principle VI added in v1.1.0): still PASS.

## Project Structure

### Documentation (this feature)

```text
specs/001-daily-planning-framework/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── api.md             # REST API surface
│   └── backend-ports.md   # task / calendar / note adapter contracts
└── tasks.md               # created later by /speckit-tasks
```

### Source Code (repository root)

```text
justfile                      # imports every module below; only entry point
devbox.json                   # dependency setup
.pre-commit-config.yaml       # the single file listing all checks (incl. Vale)
.vale.ini, .vale/styles/STE/  # ASD-STE100 style checks for prose
tach.toml                     # module boundaries for the backend
.github/workflows/            # ci.yml, release.yml, nightly.yml (call `just` only)

backend/
├── backend.just
├── pyproject.toml            # ruff, mypy, pytest, coverage configuration
├── alembic.ini
├── migrations/
├── src/tefteri/
│   ├── api/                  # FastAPI routers, request/response schemas
│   ├── services/             # use cases: sync, scheduling, planning, review
│   ├── domain/               # entities, enums, ports (adapter interfaces)
│   ├── adapters/
│   │   ├── vikunja/
│   │   ├── google_calendar/
│   │   └── trilium/
│   ├── db/                   # SQLAlchemy models, session handling, repositories
│   ├── auth/                 # password hash verification, sessions, OIDC
│   ├── security/             # token encryption
│   ├── config.py             # settings from environment
│   └── main.py
└── tests/
    ├── unit/
    ├── integration/          # real DB (SQLite, and Postgres in CI), mocked HTTP
    ├── e2e/                  # full app through HTTP against fake backends
    └── smoke/                # run against a built image / running server

frontend/
├── frontend.just
├── pubspec.yaml
├── analysis_options.yaml
├── lib/                      # features/{daily,week,month,year,goals,review,notes,settings}
├── test/
└── integration_test/

deploy/
├── deploy.just
├── Dockerfile
├── compose.yaml              # tefteri + optional postgres
└── .env.example

packaging/
├── packaging.just            # .deb, AppImage, .apk build recipes
├── deb/
└── appimage/

scripts/                      # small, shellcheck-clean Bash helpers (version computation, etc.)
docs/
├── docs.just
├── conf.py                   # Sphinx + myst-parser
├── index.md                  # splits into the two audiences
├── user/                     # end users: setup, connections, daily use, shortcuts, troubleshooting
└── developer/                # developers: architecture, just recipes, contracts, testing, release
├── index.md                  # splits into the two audiences
├── user/                     # end users: setup, connections, daily use, shortcuts, troubleshooting
└── developer/                # developers: architecture, just recipes, contracts, testing, release
```

**Structure Decision**: Web-service-plus-client layout with one top-level directory per
deliverable, each owning a small `.just` module. The backend's internal layers are fixed by
`tach.toml`: `api → services → domain ← adapters`, and `db`/`auth`/`security` used by
services but never by `domain`.

## Complexity Tracking

No constitution violations to justify.
