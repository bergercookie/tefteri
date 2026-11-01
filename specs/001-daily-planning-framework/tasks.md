---

description: "Task list for Tefteri Daily Planning & Execution Framework"
---

# Tasks: Tefteri Daily Planning & Execution Framework

**Input**: Design documents from `/specs/001-daily-planning-framework/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/api.md, contracts/backend-ports.md, quickstart.md

**Tests**: Included. The constitution (Principle V, non-negotiable) requires automated tests for all new behaviour, so each story has test tasks that are written first and must fail before the implementation.

**Documentation**: Constitution Principle VI applies to every story: each story ships its user guide (`docs/user/`) and, where relevant, its developer guide (`docs/developer/`) in ASD-STE100, in the same phase as the behaviour. Vale (`just lint`) and `just docs::build` must pass. User guides show the app with screenshots from golden tests (`just docs::screenshots`, run by hand), and developer guides use Mermaid diagrams (constitution VI).

**Organization**: Tasks are grouped by user story (US1-US9, priority order from spec.md). All commands run through `just` recipes (constitution Principle II).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on incomplete tasks)
- **[Story]**: User story label (US1...US9); none for Setup, Foundational and Polish
- Paths are relative to the repository root

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Repository skeleton, tooling, and the justfile/pre-commit/CI system

- [X] T001 Create the directory skeleton from plan.md: `backend/src/tefteri/{api,services,domain,adapters/{vikunja,google_calendar,trilium},db,auth,security}`, `backend/tests/{unit,integration,e2e,smoke}`, `frontend/`, `deploy/`, `packaging/{deb,appimage}`, `scripts/`, `docs/`
- [X] T002 Create `devbox.json` pinning python, uv, just, pre-commit, shellcheck, shfmt, hadolint, yamllint, actionlint, markdownlint-cli2, taplo and flutter; document Docker (and Android SDK if needed) as exceptions in `README.md`
- [X] T003 Create `backend/pyproject.toml` (uv-managed deps: fastapi, pydantic, sqlalchemy[asyncio], alembic, aiosqlite, asyncpg, httpx, argon2-cffi, cryptography; dev: pytest, pytest-asyncio, respx, coverage, ruff, mypy, tach) with ruff (including pydocstyle rules so public modules, classes and functions must be documented), strict mypy and pytest config covering `src` and `tests`
- [X] T004 [P] Create `tach.toml` declaring modules `api`, `services`, `domain`, `adapters`, `db`, `auth`, `security` and the rule `api → services → domain ← adapters` (adapters never imported by core)
- [X] T005 Create the root `justfile` that declares them as modules (`mod backend 'backend/backend.just'`, etc., called as `backend::test`) and defines aggregators `lint`, `test`, `build`, `run`
- [X] T006 [P] Create `backend/backend.just` as a just module (`mod backend`) with recipes `install`, `test`, `e2e`, `test-postgres`, `run`, `openapi`, `migrate`, called as `just backend::test`
- [X] T007 [P] Create `frontend/frontend.just` (module recipes `install`, `analyze`, `format-check`, `test`, `build-linux`, `build-apk`, `build-web`, called as `just frontend::analyze`)
- [X] T008 [P] Create `deploy/deploy.just` (`build-image`, `up`, `up-postgres`, `down`), `docs/docs.just` (`build` with `-W`) and `packaging/packaging.just` (`deb`, `appimage`, `apk`)
- [X] T009 Create `.pre-commit-config.yaml` as the single list of all checks; hooks are `language: system` and call the tools directly (no `just` recipe needed); `just lint` runs `pre-commit run --all-files` and `just lint` is the only thing that runs it
- [X] T010 [P] Add linter configs: `.yamllint.yaml`, `.markdownlint-cli2.yaml`, `.hadolint.yaml`, `.shellcheckrc`, `taplo.toml`, `.editorconfig` (shfmt), and justfile format check hook
- [X] T011 [P] Create Flutter project in `frontend/` (`pubspec.yaml`, `analysis_options.yaml` with `flutter_lints` and the `public_member_api_docs` lint, Linux, Android and web targets enabled)
- [X] T012 [P] Create `docs/conf.py`, `docs/index.md`, `docs/requirements.txt` (Sphinx + `myst-parser`) and an architecture overview page
- [X] T013 Create `.github/workflows/ci.yml` that installs devbox and runs only `just lint`, `just test`, just docs::build (Postgres test job via `just backend::test-postgres`); no direct pre-commit/mypy calls
- [X] T014 [P] Create `.gitignore`, `.env.example` in `deploy/`, and a `CONTRIBUTING.md` that tells contributors and agents to use `just` only
- [X] T118 [P] Add pytest-alembic migration tests (single head, upgrade, up/down consistency, models match DDL, per-revision checks) in `backend/tests/migrations/`; every new migration task adds a per-revision test there
- [X] T119 [P] Add Vale with a custom ASD-STE100 style (`.vale.ini`, `.vale/styles/STE/`), `vale` in `devbox.json` and a pre-commit hook for `README.md`, `CONTRIBUTING.md` and `docs/*.md`
- [ ] T120 Run `vale` in `devbox shell`, fix all findings in existing prose and tune the STE rules (the hook is written but not yet run); every docs task (T092, T107, T114, quickstart) must pass it
- [X] T121 [P] Restructure `docs/` for the two audiences (constitution VI): move `docs/architecture.md` to `docs/developer/architecture.md`, create `docs/user/index.md` and `docs/developer/index.md`, make `docs/index.md` link both sections, keep `just docs::build` (-W) passing, and add any new technical terms to `.vale/styles/config/vocabularies/Tefteri/accept.txt`
- [ ] T147 [P] Run the shared adapter contract suite (`backend/tests/integration/test_backend_contracts.py`) against the real Vikunja, Google Calendar and Trilium adapters, using a stateful respx fake server per app, so the contract in `contracts/backend-ports.md` holds for every adapter
- [X] T148 [P] Wire all backend tests into `just`: `backend::test` runs unit, integration, migrations and e2e tests (not smoke, not `postgres`-marked); add `backend/tests/migrations/test_postgres.py` (marked `postgres`, reads `TEFTERI_TEST_POSTGRES_URL`, upgrades to head and downgrades to base); `backend::test-postgres` runs the marked tests
- [ ] T149 Run `just frontend::analyze` and `just frontend::test` in `devbox shell` and fix findings in the Flutter code written so far (T031, T048-T051); do T133 (pin Flutter) first
- [ ] T133 [P] Set up Mermaid diagrams in the docs: add `sphinxcontrib-mermaid` to `docs/requirements.txt`, enable it in `docs/conf.py`, keep `just docs::build` (-W) passing, and pin the Flutter version in `devbox.json` so screenshots are reproducible
- [ ] T134 [P] Set up app screenshots: bundle an open-licence font in `frontend/assets/fonts/` (declare it in `frontend/pubspec.yaml`), add the shared helper `frontend/test/screenshots/screenshot_helper.dart` (loads the font, fixed window size and fake data, writes the PNG to `docs/images/`), and add the recipe `screenshots` to `docs/docs.just` (`just docs::screenshots` runs `flutter test --update-goldens test/screenshots`; run by hand, no CI check)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T015 Implement settings in `backend/src/tefteri/config.py` (env-based: `TEFTERI_DATABASE_URL`, `TEFTERI_ADMIN_USERNAME`, `TEFTERI_ADMIN_PASSWORD_HASH`, `TEFTERI_SECRET_KEY`, `TEFTERI_GOOGLE_CLIENT_ID`/`TEFTERI_GOOGLE_CLIENT_SECRET`, login throttling limits per account (default 5 failures per 15 minutes, 15-minute block), session lifetime (default 8 hours) and `TEFTERI_PUBLIC_URL` (base URL used for OAuth redirect addresses)); startup MUST fail if the admin value is not a valid Argon2 hash (never accept a raw password)
- [X] T016 Implement async engine/session factory supporting SQLite (aiosqlite) and PostgreSQL (asyncpg) in `backend/src/tefteri/db/session.py`
- [X] T017 Set up Alembic in `backend/migrations/` with async env and an initial migration that works on both SQLite and Postgres (portable SQLAlchemy constructs only)
- [X] T018 [P] Implement `User` model in `backend/src/tefteri/db/models/user.py`: `username` unique, `password_hash` (nullable), `is_admin`, `timezone`, `disabled`
- [X] T019 [P] Implement `Connection` and `SourceContainer` models in `backend/src/tefteri/db/models/connection.py` with `kind` (`tasks`|`calendar`|`notes`), `provider`, `default_context` (`work`|`life`), `encrypted_credentials`, `status` (`ok`|`needs_attention`|`error`), container `context` override
- [X] T020 [P] Implement `SyncRun` and `Conflict` models in `backend/src/tefteri/db/models/sync.py` (`resolution`: `keep_local`|`keep_remote`; item `sync_state`: `synced`|`conflict`|`deleted_remotely`)
- [X] T021 [P] Implement token encryption (Fernet) in `backend/src/tefteri/security/crypto.py`
- [X] T022 Implement repository base with mandatory `user_id` scoping on every query in `backend/src/tefteri/db/repositories/base.py`
- [X] T023 Implement password verification, admin bootstrap at startup and session/bearer-token issuing with login throttling (limit repeated failed attempts) and expiring sessions per config in `backend/src/tefteri/auth/` and `backend/src/tefteri/api/routers/auth.py` (`POST /auth/login`, `POST /auth/logout`, `GET /auth/me`, `GET /auth/methods`)
- [X] T024 Implement FastAPI app factory, dependency injection, auth dependency, error model `{"detail", "code"}` and `/health`, `/version` in `backend/src/tefteri/main.py` and `backend/src/tefteri/api/`
- [X] T025 Define domain entities, enums and exceptions (`BackendUnavailable`, `AuthExpired`, `NotSupported`, `RemoteConflict`) in `backend/src/tefteri/domain/`
- [X] T026 Define the `TaskBackend`, `CalendarBackend`, `NoteBackend` ports and `Capability` set per `contracts/backend-ports.md` in `backend/src/tefteri/domain/ports.py`
- [X] T027 [P] Implement in-memory fake backends for all three ports in `backend/tests/fakes/` for use by service, integration and e2e tests
- [X] T028 [P] Write shared adapter contract test suite parametrised over adapters in `backend/tests/integration/test_backend_contracts.py`
- [X] T029 [P] Write tests for login throttling (5 failures in 15 minutes blocks for 15 minutes), session expiry (default 8 hours) and config validation (reject raw password, accept Argon2 hash) in `backend/tests/unit/test_config.py` and for login/admin bootstrap in `backend/tests/integration/test_auth.py`
- [X] T030 [P] Implement a `just hash-password` recipe and `scripts/hash_password.py` (prompts, prints Argon2 hash)
- [X] T031 Create the Flutter app shell in `frontend/lib/` (go_router, Riverpod, dio client with auth, login screen, global context switch (all/life/work) and sync button placeholders)

**Checkpoint**: Foundation ready — user story work can begin

---

## Phase 3: User Story 1 - Connect apps and sync (Priority: P1) 🎯 MVP

**Goal**: Connect Vikunja, Google Calendar and Trilium Next and see their data in tefteri; sync button refreshes it.

**Independent Test**: Connect one app of each kind, press sync, verify items match the source apps; one app failing does not block the others.

### Tests for User Story 1

- [X] T032 [P] [US1] Unit tests for sync service (per-connection results, failure isolation, deletion marking) in `backend/tests/unit/test_sync_service.py`
- [X] T033 [P] [US1] Integration tests for connections and sync endpoints with fake backends in `backend/tests/integration/test_connections_sync.py`
- [X] T034 [P] [US1] Recorded-HTTP tests for the Vikunja adapter in `backend/tests/integration/adapters/test_vikunja.py`
- [X] T035 [P] [US1] Recorded-HTTP tests for the Google Calendar adapter (multiple accounts, calendars) in `backend/tests/integration/adapters/test_google_calendar.py`
- [X] T036 [P] [US1] Recorded-HTTP tests for the Trilium Next adapter in `backend/tests/integration/adapters/test_trilium.py`

### Implementation for User Story 1

- [X] T037 [P] [US1] Implement `Task` mirror model in `backend/src/tefteri/db/models/task.py` (unique `connection_id`+`remote_id`; fields from data-model.md)
- [X] T038 [P] [US1] Implement `CalendarEntry` mirror model in `backend/src/tefteri/db/models/calendar_entry.py`
- [X] T039 [P] [US1] Implement `Note` mirror model in `backend/src/tefteri/db/models/note.py` (`kind`: `daily`|`custom`|`process`|`retrospective`)
- [X] T040 [US1] Add Alembic migration for the mirror tables in `backend/migrations/versions/` with a per-revision test in `backend/tests/migrations/`
- [X] T041 [P] [US1] Implement Vikunja adapter (token auth, projects as containers) in `backend/src/tefteri/adapters/vikunja/`
- [X] T042 [P] [US1] Implement Google Calendar adapter (OAuth2 per account, personal/family/company calendars, sync tokens) in `backend/src/tefteri/adapters/google_calendar/`
- [X] T043 [P] [US1] Implement Trilium Next ETAPI adapter in `backend/src/tefteri/adapters/trilium/`
- [X] T044 [US1] Implement adapter registry (provider → adapter) and connection service with credential encryption in `backend/src/tefteri/services/connections.py`
- [X] T045 [US1] Implement sync service (per connection, cursor/etag, failure isolation, `SyncRun` records, structured per-connection error reasons (`unreachable`, `auth_expired`, `error`) so the UI can name the connection and cause; status transitions `ok`↔`needs_attention`↔`error`) in `backend/src/tefteri/services/sync.py`
- [X] T046 [US1] Implement endpoints `GET/POST/PATCH/DELETE /connections`, `/connections/google/authorize|callback`, `POST /sync`, `POST /connections/{id}/sync`, `GET /sync/status` in `backend/src/tefteri/api/routers/connections.py` and `sync.py`
- [X] T047 [US1] Implement read endpoints `GET /tasks`, `GET /calendar`, `GET /notes` from the cache in `backend/src/tefteri/api/routers/`
- [X] T048 [P] [US1] Implement Flutter connections settings screen and sync button with last-sync time/outcome per connection in `frontend/lib/features/settings/`
- [X] T049 [P] [US1] Flutter widget tests for the sync button and failure display in `frontend/test/features/settings/`
- [X] T050 [P] [US1] Implement the Flutter "service unavailable" presentation: for each failing connection show its name and reason (unreachable, credentials expired/revoked, other) with actions Retry, Reconnect and Open settings, and never hide or silently queue a failed change, in `frontend/lib/features/settings/`
- [X] T051 [P] [US1] Flutter widget tests and a backend integration test (stopped fake backend, expired credentials) for the service-unavailable flow in `frontend/test/features/settings/` and `backend/tests/integration/test_service_unavailable.py`
- [X] T122 [P] [US1] User guides in `docs/user/connect-apps.md` (connect Vikunja, Google Calendar accounts and Trilium Next, use Sync, read last-sync status) and `docs/user/troubleshooting.md` (an app is unreachable, credentials expired: what the message means, Retry, Reconnect), written in ASD-STE100
- [X] T123 [P] [US1] Developer guide `docs/developer/adding-an-adapter.md`: the three ports, capabilities and errors, the shared contract test suite, how to record HTTP fixtures, and the `tach` layering rule, written in ASD-STE100
- [ ] T135 [P] [US1] Screenshot tests in `frontend/test/screenshots/connections_test.dart` (fake data, no real credentials or personal data) writing the connections list, a sync result and the unavailable-app card (unreachable and credentials expired) to `docs/images/`; embed them with alt text in `docs/user/connect-apps.md` and `docs/user/troubleshooting.md` next to the steps they show

**Checkpoint**: US1 independently functional (MVP)

---

## Phase 4: User Story 2 - Daily planning and execution (Priority: P1)

**Goal**: Daily view combining entries, tasks and the day's note; manage tasks and notes from it.

**Independent Test**: Open today's view, create/complete/delete a task and add a note; changes appear in the apps after sync.

### Tests for User Story 2

- [ ] T052 [P] [US2] Integration tests for task CRUD/complete write-through in `backend/tests/integration/test_tasks.py`
- [ ] T053 [P] [US2] Integration tests for daily note get-or-create, append and task link in `backend/tests/integration/test_daily_notes.py`
- [ ] T054 [P] [US2] E2E test of the daily flow against fake backends in `backend/tests/e2e/test_daily_flow.py`

### Implementation for User Story 2

- [ ] T055 [P] [US2] Implement `TaskNoteLink` model in `backend/src/tefteri/db/models/links.py`
- [ ] T056 [US2] Implement task service (create, edit, complete, delete via port, then update cache; pass `expected_version` and raise `RemoteConflict` on a changed remote; if the app is unreachable apply nothing locally and return a clear error naming the connection and reason; surface `NotSupported` as a clear "unavailable for this app" message) in `backend/src/tefteri/services/tasks.py`
- [ ] T057 [US2] Implement note service (daily get-or-create, append, link to task) in `backend/src/tefteri/services/notes.py`
- [ ] T058 [US2] Implement endpoints `POST/GET/PATCH/DELETE /tasks`, `POST /tasks/{id}/complete`, `GET /notes/daily/{date}`, `POST /notes/daily/{date}/append`, `POST /tasks/{id}/notes`, `GET /views/day/{date}` in `backend/src/tefteri/api/routers/`
- [ ] T059 [P] [US2] Implement the Flutter daily view (entries, tasks, daily note, quick add, complete, delete; show clear messages for unreachable apps and unsupported actions) in `frontend/lib/features/daily/`
- [ ] T060 [P] [US2] Flutter widget tests for the daily view in `frontend/test/features/daily/`
- [ ] T124 [P] [US2] User guide `docs/user/daily-planning.md` (daily view, add/complete/delete tasks, the daily note, link a note to a task), written in ASD-STE100
- [ ] T136 [P] [US2] Screenshot tests in `frontend/test/screenshots/daily_test.dart` (fake data, no real credentials or personal data) writing the daily view (entries, tasks, daily note) and quick add to `docs/images/`; embed them with alt text in `docs/user/daily-planning.md` next to the steps they show

**Checkpoint**: US1 + US2 work together

---

## Phase 5: User Story 3 - Schedule tasks on the calendar (Priority: P1)

**Goal**: Place tasks on the calendar; date/time written back to the task manager; edit calendar entries.

**Independent Test**: Schedule an unscheduled task; verify date/time updated in Vikunja, no calendar event created, task shown in calendar next to entries.

### Tests for User Story 3

- [ ] T061 [P] [US3] Integration tests for `PUT/DELETE /tasks/{id}/schedule` (write-back, no event created) in `backend/tests/integration/test_scheduling.py`
- [ ] T062 [P] [US3] Integration tests for calendar entry create/edit/delete and overlap reporting in `backend/tests/integration/test_calendar_entries.py`
- [ ] T063 [P] [US3] Unit tests for time zone, DST, all-day and recurring handling in `backend/tests/unit/test_time_handling.py`

### Implementation for User Story 3

- [ ] T064 [US3] Implement scheduling service (set/clear schedule via `TaskBackend.set_schedule`, overlap detection; same `expected_version`, unreachable and `NotSupported` handling as the task service) in `backend/src/tefteri/services/scheduling.py`
- [ ] T065 [US3] Implement calendar service for entry CRUD through `CalendarBackend` in `backend/src/tefteri/services/calendar.py`
- [ ] T066 [US3] Implement endpoints `PUT/DELETE /tasks/{id}/schedule`, `POST/PATCH/DELETE /calendar/entries`, and make `GET /calendar` return entries and scheduled tasks tagged `type: entry|task` in `backend/src/tefteri/api/routers/calendar.py`
- [ ] T067 [P] [US3] Implement the Flutter calendar view with drag/choose-time scheduling and distinct styling for tasks vs entries and clear unsupported/unreachable messages in `frontend/lib/features/calendar/`
- [ ] T068 [P] [US3] Flutter widget tests for scheduling interactions in `frontend/test/features/calendar/`
- [ ] T125 [P] [US3] User guide `docs/user/scheduling.md` (put a task on the calendar, why no calendar event is created, edit calendar entries, overlaps, apps that cannot store a time), written in ASD-STE100
- [ ] T137 [P] [US3] Screenshot tests in `frontend/test/screenshots/calendar_test.dart` (fake data, no real credentials or personal data) writing the calendar view with a task scheduled beside entries, and the unsupported-app message to `docs/images/`; embed them with alt text in `docs/user/scheduling.md` next to the steps they show

**Checkpoint**: All P1 stories independently functional

---

## Phase 6: Conflict Resolution (Cross-Cutting, FR-008)

**Purpose**: Detect and resolve changes made both in tefteri and in a connected app, before the remaining stories build on write-through. Nothing is ever overwritten automatically.

- [ ] T069 [P] Write unit and integration tests for conflict detection and resolution (`keep_local|keep_remote`, nothing overwritten automatically) in `backend/tests/{unit,integration}/test_conflicts.py`
- [ ] T070 Implement conflict detection in the sync/write-through services and `GET /conflicts`, `POST /conflicts/{id}/resolve` in `backend/src/tefteri/services/conflicts.py` and `api/routers/conflicts.py`
- [ ] T071 [P] Implement the Flutter conflict resolution screen showing both versions in `frontend/lib/features/conflicts/`
- [ ] T126 [P] User guide `docs/user/conflicts.md` (what a conflict is, compare both versions, keep local or keep remote), written in ASD-STE100
- [ ] T138 [P] Screenshot tests in `frontend/test/screenshots/conflicts_test.dart` (fake data, no real credentials or personal data) writing the conflict screen showing both versions to `docs/images/`; embed them with alt text in `docs/user/conflicts.md` next to the steps they show

---

## Phase 7: User Story 4 - Separate work and life (Priority: P2)

**Goal**: Label items work/life (individually or per container) and filter every view.

**Independent Test**: With mixed items, "work only" shows only work items on every view; same for "life only".

### Tests for User Story 4

- [ ] T072 [P] [US4] Unit tests for effective-context resolution (item override → container → connection default; unclassified marker) in `backend/tests/unit/test_context.py`
- [ ] T073 [P] [US4] Integration tests that `context=work|life|all` filters tasks, calendar entries and notes with zero leakage (goals and views are tested in the US5 planning tests) in `backend/tests/integration/test_context_filter.py`

### Implementation for User Story 4

- [ ] T074 [US4] Implement effective-context resolution and `context` query filter in `backend/src/tefteri/services/context.py` and repositories
- [ ] T075 [US4] Implement `PATCH /connections/{id}/containers/{cid}` and per-item context update on tasks, entries and notes in `backend/src/tefteri/api/routers/`
- [ ] T076 [P] [US4] Wire the global all/life/work switch to every Flutter view and show an "unclassified" marker in `frontend/lib/core/context_filter.dart`
- [ ] T077 [P] [US4] Flutter tests for the context switch across views in `frontend/test/core/context_filter_test.dart`
- [ ] T127 [P] [US4] User guide `docs/user/work-and-life.md` (label items and containers, the all/life/work switch, the unclassified marker), written in ASD-STE100
- [ ] T139 [P] [US4] Screenshot tests in `frontend/test/screenshots/context_test.dart` (fake data, no real credentials or personal data) writing the all/life/work switch and the unclassified marker to `docs/images/`; embed them with alt text in `docs/user/work-and-life.md` next to the steps they show

---

## Phase 8: User Story 5 - Weekly, monthly and annual planning (Priority: P2)

**Goal**: Goals broken down year → month → week → tasks, with progress roll-up and scheduling from any view.

**Independent Test**: Create an annual goal, break it into monthly milestones and weekly tasks, schedule one; goal shows progress.

### Tests for User Story 5

- [ ] T078 [P] [US5] Unit tests for goal hierarchy rules (child period inside parent, progress roll-up computed not stored) in `backend/tests/unit/test_goals.py`
- [ ] T079 [P] [US5] Integration tests for `/goals`, `/goals/{id}/breakdown`, delete with `linked_tasks=keep|delete`, and `/views/week|month|year`, `context` filtering of goals and views, and scheduling a goal-derived task from a planning view in `backend/tests/integration/test_planning.py`

### Implementation for User Story 5

- [ ] T080 [P] [US5] Implement `Goal` model in `backend/src/tefteri/db/models/goal.py` (`period_type`: `year`|`month`|`week`; `status`: `active`|`done`|`dropped`; `parent_id` nullable; `progress` derived)
- [ ] T081 [P] [US5] Implement `Plan` model in `backend/src/tefteri/db/models/plan.py` and a migration (with a test in `backend/tests/migrations/`) in `backend/migrations/versions/`
- [ ] T082 [US5] Implement goal service (hierarchy validation, breakdown into child goals/tasks, progress roll-up, delete with keep/delete linked tasks) in `backend/src/tefteri/services/goals.py`
- [ ] T083 [US5] Implement endpoints `/goals`, `/goals/{id}/breakdown`, `/plans`, and aggregated `/views/week/{date}`, `/views/month/{date}`, `/views/year/{year}` in `backend/src/tefteri/api/routers/planning.py`
- [ ] T084 [P] [US5] Implement Flutter weekly, monthly and annual views and goal breakdown UI, including scheduling goal-derived tasks onto a day or time from any planning view in `frontend/lib/features/{week,month,year,goals}/`
- [ ] T085 [P] [US5] Flutter widget tests for planning views in `frontend/test/features/`
- [ ] T128 [P] [US5] User guide `docs/user/planning-goals.md` (goals for year, month and week, break a goal down, progress, schedule from a planning view), written in ASD-STE100
- [ ] T140 [P] [US5] Screenshot tests in `frontend/test/screenshots/planning_test.dart` (fake data, no real credentials or personal data) writing the weekly, monthly and annual views and the goal breakdown to `docs/images/`; embed them with alt text in `docs/user/planning-goals.md` next to the steps they show

---

## Phase 9: User Story 6 - Multiple users (Priority: P2)

**Goal**: Several users, admin-created, each isolated. Sign-in is by username and password only; SSO/OIDC is deferred to a later version.

**Independent Test**: Two users with different connections see only their own data; signed-out access denied.

### Tests for User Story 6

- [ ] T086 [P] [US6] Integration tests: cross-user access to every resource type returns nothing/404, and unauthenticated requests are denied, in `backend/tests/integration/test_isolation.py`
- [ ] T087 [P] [US6] Integration tests for admin-only user management and no self-registration in `backend/tests/integration/test_users.py`
- [ ] T088 [P] [US6] Integration tests for the `/auth/methods` endpoint and for admin-created users signing in with the password the admin set (a disabled user cannot sign in), in `backend/tests/integration/test_sign_in.py`

### Implementation for User Story 6

- [ ] T089 [US6] Implement admin-only `GET/POST/PATCH/DELETE /users` (the admin sets the initial password, stored as an Argon2 hash; users can be disabled) in `backend/src/tefteri/api/routers/users.py`
- [X] T090 Remove the unfinished SSO/OIDC parts (settings, `oidc_*` user columns, `/auth/methods` oidc flag, `authlib` dependency) until SSO is specified in a later version
- [ ] T091 [P] [US6] Implement Flutter admin user management screen in `frontend/lib/features/{admin,auth}/`
- [ ] T092 [P] [US6] Document multi-user setup, admin bootstrap with a password hash, and reverse-proxy deployment in `docs/developer/deployment.md` (audience: administrators and developers), written in ASD-STE100
- [ ] T129 [P] [US6] User guide `docs/user/accounts-and-sign-in.md` (sign in with a password, session expiry, blocked sign-in after repeated failures, administrator user management), written in ASD-STE100
- [ ] T141 [P] [US6] Screenshot tests in `frontend/test/screenshots/accounts_test.dart` (fake data, no real credentials or personal data) writing the login screen and the admin user management screen to `docs/images/`; embed them with alt text in `docs/user/accounts-and-sign-in.md` next to the steps they show

---

## Phase 10: User Story 7 - Long-term plans and retrospectives (Priority: P3)

**Goal**: Keep long-term plans; planned-vs-completed reviews; retrospectives saved to Trilium.

**Independent Test**: For a past period with mixed outcomes, generate the review and save a retrospective that appears as a note.

### Tests for User Story 7

- [ ] T093 [P] [US7] Unit tests for review computation (planned vs completed, carried over) in `backend/tests/unit/test_review.py`
- [ ] T094 [P] [US7] Integration tests for `/plans/{id}/review` and `PUT .../review/retrospective` writing a note to the fake note backend in `backend/tests/integration/test_reviews.py`

### Implementation for User Story 7

- [ ] T095 [P] [US7] Implement `PeriodReview` model in `backend/src/tefteri/db/models/review.py` and a migration (snapshot semantics per data-model.md)
- [ ] T096 [US7] Implement review service and retrospective note writing through `NoteBackend` in `backend/src/tefteri/services/reviews.py`
- [ ] T097 [US7] Implement review endpoints and plan history browsing in `backend/src/tefteri/api/routers/reviews.py`
- [ ] T098 [P] [US7] Implement Flutter review, retrospective and plan history screens in `frontend/lib/features/review/`
- [ ] T099 [P] [US7] Flutter widget tests for review screens in `frontend/test/features/review/`
- [ ] T130 [P] [US7] User guide `docs/user/reviews-and-retrospectives.md` (open a review, planned versus done, save a retrospective to your notes app, plan history), written in ASD-STE100
- [ ] T142 [P] [US7] Screenshot tests in `frontend/test/screenshots/review_test.dart` (fake data, no real credentials or personal data) writing the review, retrospective and plan history screens to `docs/images/`; embed them with alt text in `docs/user/reviews-and-retrospectives.md` next to the steps they show

---

## Phase 11: User Story 8 - Documentation and process notes (Priority: P3)

**Goal**: Custom documentation and process notes saved in the note-taking app and linked to tasks.

**Independent Test**: Create a process note, link it to a task, open it from the task and edit it; verify it is saved in the note-taking app.

### Tests for User Story 8

- [ ] T100 [P] [US8] Integration tests for custom documentation/process notes (create, edit, delete) and task links in `backend/tests/integration/test_custom_notes.py`

### Implementation for User Story 8

- [ ] T101 [US8] Extend the note service with custom documentation and process notes and two-way task links in `backend/src/tefteri/services/notes.py`
- [ ] T102 [US8] Implement note endpoints `POST/PATCH/DELETE /notes` and `POST /tasks/{id}/notes` in `backend/src/tefteri/api/routers/notes.py`
- [ ] T103 [P] [US8] Implement Flutter notes screens (list, edit, open from a task) in `frontend/lib/features/notes/` with widget tests in `frontend/test/features/notes/`
- [ ] T131 [P] [US8] User guide `docs/user/notes-and-processes.md` (documentation and process notes, link them to tasks, open from a task), written in ASD-STE100
- [ ] T143 [P] [US8] Screenshot tests in `frontend/test/screenshots/notes_test.dart` (fake data, no real credentials or personal data) writing the notes list and note editor to `docs/images/`; embed them with alt text in `docs/user/notes-and-processes.md` next to the steps they show

---

## Phase 12: User Story 9 - Keyboard navigation (Priority: P2)

**Goal**: Navigate between all views and trigger sync and the work/life filter from the keyboard.

**Independent Test**: From any view, reach every other view with the keyboard alone (at most two key presses) and open the shortcut help.

### Tests for User Story 9

- [ ] T104 [P] [US9] Flutter widget tests: each shortcut opens its view from every other view (at most two key presses), plain-key shortcuts are ignored while a text field has focus, and the help overlay lists every shortcut, in `frontend/test/core/shortcuts_test.dart`

### Implementation for User Story 9

- [ ] T105 [US9] Implement a central keymap with Flutter `Shortcuts`/`Actions` for the daily, weekly, monthly, annual, goals, review, notes and settings views plus sync and the all/life/work switch in `frontend/lib/core/shortcuts/`
- [ ] T106 [US9] Implement the shortcut help overlay (opened with `?`) generated from the keymap, and suppress plain-key shortcuts while a text field has focus, in `frontend/lib/core/shortcuts/`
- [ ] T107 [P] [US9] Document all shortcuts in `docs/user/shortcuts.md` (user guide, written in ASD-STE100)
- [ ] T144 [P] [US9] Screenshot tests in `frontend/test/screenshots/shortcuts_test.dart` (fake data, no real credentials or personal data) writing the shortcut help overlay to `docs/images/`; embed them with alt text in `docs/user/shortcuts.md` next to the steps they show

---

## Phase 13: Delivery & Polish (Cross-Cutting)

**Purpose**: Release engineering, docs, hardening

- [ ] T108 [P] Create `deploy/Dockerfile`, `deploy/compose.yaml` (tefteri + optional Postgres profile) and the smoke test `backend/tests/smoke/test_container.py`
- [ ] T109 [P] Create `scripts/version.sh` (nightly `<prev>.<hash>.postN` from ghcr tags; PEP 440 and Flutter forms derived from same inputs) with a test and `just version-nightly`
- [ ] T110 [P] Create `packaging/deb/` and `packaging/appimage/` build files and the `packaging::*` recipes; produce signed `.apk` via keystore secret
- [ ] T111 Create `.github/workflows/release.yml` (tag `v*` → GitHub release with `.deb`, AppImage, `.apk`; push image `X.Y.Z` and `latest` to `ghcr.io/bergercookie/tefteri`) calling only `just`
- [ ] T112 Create `.github/workflows/nightly.yml` (scheduled; skip if HEAD unchanged; push image tags `nightly` and the version string; rolling `nightly` pre-release with client artifacts) calling only `just`
- [ ] T113 [P] Add the OpenAPI snapshot check (`just backend::openapi` → `docs/openapi.json`; test fails on drift)
- [ ] T114 [P] Write the remaining docs: `docs/user/getting-started.md` (install the client, first sign-in, company Google OAuth approval) and `docs/developer/{setup,testing,releases}.md` (devbox and `just`, tests and migrations, release and nightly versioning), all in ASD-STE100
- [ ] T115 [P] Add performance tests for the sync target (2,000 tasks / 1,000 entries / 500 notes < 30 s) in `backend/tests/integration/test_sync_performance.py`
- [ ] T116 [P] Add an automated review-latency test (a review for a year of goals and tasks opens in under 5 seconds, SC-008) in `backend/tests/integration/test_review_performance.py`
- [ ] T132 [P] Add a docs coverage check `scripts/check_docs.sh` (behind `just docs::check`, shellcheck-clean) that also fails when an image in `docs/` has no alt text or points to a missing file, and that fails when a page listed in `docs/user/index.md` or `docs/developer/index.md` is missing, and when a user guide required by tasks T122, T124-T131, T107 and T114 does not exist
- [ ] T145 [P] Add Mermaid diagrams to the developer guides: architecture layers (`api`, `services`, `domain`, `adapters`) in `docs/developer/architecture.md`, the sync flow with failure isolation in `docs/developer/sync.md`, and the conflict flow in the same page; add `sync` to the developer toctree
- [ ] T146 In `devbox shell` run `just docs::screenshots`, check every image for fake data only and readable text (fonts loaded), fix the screenshot tests, and commit `docs/images/`; repeat by hand when a screen changes
- [ ] T117 Run the full `quickstart.md` validation (`just lint`, `just test`, just docs::build, `just docs::screenshots`, e2e, Postgres, image build) and fix findings

---

## Dependencies & Execution Order

- Screenshot tasks (T135-T144) need the screen they show (their story's Flutter UI) and the setup in T133-T134; T146 runs after all of them.
- Docs tasks follow the behaviour they describe inside the same phase, and every docs task must pass Vale (run T120 when Vale is available in `devbox shell` and recheck the docs written before it, T121-T123).
- **Setup (Phase 1)** → **Foundational (Phase 2)** → user stories → **Polish (Phase 13)**.
- **US1** first: every other story needs synced data. **US2** and **US3** build on US1's models and services; US3 reuses US2's task service.
- **US4** touches repositories and views from US1-US3 but is testable on its own with fake data.
- **US5** needs tasks (US1/US2); scheduling from planning views reuses US3.
- **US6** user management is independent; basic login and `user_id` scoping are already in Foundational.
- **US7** needs goals/plans (US5) and the note backend (US1). **US8** extends the note service from US2. **US9** (keyboard navigation) comes after US8 so every view it navigates to already exists.
- Conflict resolution (Phase 6) depends on the sync and write-through services (US1-US3) and is done before US4+ so no later story can overwrite a changed remote item.

### Within each story
Tests first (must fail) → models → services → endpoints → Flutter UI.

### Parallel Opportunities
- Setup `[P]` tasks (justfile modules, linter configs, Flutter project, docs scaffold).
- Foundational models, fakes and crypto.
- The three adapters (US1) and their recorded-HTTP tests.
- Backend and Flutter work within a story once the API contract is fixed.
- After US1: US4, US6 and US8 can proceed in parallel with US2/US3.

## Implementation Strategy

1. **MVP**: Phases 1-3 (US1): connect the apps, sync, browse data.
2. Add US2 and US3 for the full daily plan-and-schedule loop (all P1).
3. Add P2 stories (US4, US5, US6), then P3 (US7, US8). US9 (keyboard navigation, P2) follows US8 so that all views exist; it can start earlier for the views already built.
4. Release engineering (Phase 13) should land before the first tagged release; the CI workflow from Phase 1 gates every change.
