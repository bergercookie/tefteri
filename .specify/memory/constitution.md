# Tefteri Constitution

Tefteri is a daily planning and execution framework. It is a server-client system that
integrates with a user's existing task management, calendar and note taking applications
through flexible backends.

## Core Principles

### I. Python Backend, Flutter Frontend
The server MUST be implemented in Python. The client MUST be implemented in Flutter. Other
languages for core application code require a constitution amendment.

Rationale: a small, fixed stack keeps the project maintainable and lets contributors and
coding agents move across the codebase without context switching.

### II. Justfile Is the Single Interface
The `justfile` is the single source of truth for every interaction with this repository.
Developers, CI pipelines and coding agents MUST use `just` recipes for building, testing,
linting, formatting, running, and any other repeatable task.

- CI workflows MUST invoke `just` recipes and MUST NOT duplicate their logic inline.
- A task that is run more than once MUST get a recipe.
- Documentation and agent instructions MUST reference recipes, not raw underlying commands.

Rationale: one entry point guarantees that local, CI and agent runs behave identically.

### III. Reproducible Environments via Devbox
Project dependencies and toolchains MUST be declared and installed with devbox. The exception
is a major dependency that is impractical to install through devbox (for example `docker`);
each such exception MUST be documented in the README together with its required version.

Rationale: a clone-and-`devbox shell` setup removes "works on my machine" problems.

### IV. Pluggable Backends
Integrations with task management, calendar and note taking applications MUST sit behind
well-defined adapter interfaces. The core planning and execution logic MUST NOT depend on a
specific third-party application. Adding a new integration MUST NOT require changes to core
logic. Each adapter MUST be testable without access to the live third-party service.

Rationale: users bring their own tools; flexibility is the product's core value.

### V. Documented, Tested, CI-Verified Code (NON-NEGOTIABLE)
All code MUST be well documented, testable and tested.

- Public modules, classes, functions and widgets MUST have documentation describing purpose
  and behaviour; user-visible behaviour changes MUST update the docs in the same change.
- New behaviour MUST ship with automated tests; bug fixes MUST include a regression test.
- Code MUST be designed for testability (dependency injection, no hidden global state).
- A CI pipeline MUST run linting, formatting checks and the full test suite for both backend
  and frontend on every pull request, via `just` recipes. Changes MUST NOT be merged while
  CI is failing.

Rationale: a planning tool that people rely on daily has to be dependable.

## Technology & Environment Constraints

- Backend: Python, with dependencies managed in a way that is reproducible and locked.
- Frontend: Flutter, communicating with the backend over a documented API.
- Tooling: `just` for tasks, devbox for dependencies, as set out in Principles II and III.
- Credentials and tokens for third-party services MUST NOT be committed to the repository.

## Development Workflow & Quality Gates

- Work is done on branches and merged through pull requests.
- Every pull request MUST pass CI and be reviewed for constitution compliance.
- The `justfile` recipes used by CI MUST be runnable locally inside `devbox shell`.
- Complexity beyond what a feature requires MUST be justified in the plan or pull request.

## Governance

This constitution supersedes other practices in this repository. Amendments require a pull
request that updates this file, states the rationale, and describes any migration needed for
existing code or tooling.

Versioning follows semantic versioning: MAJOR for backward-incompatible removals or
redefinitions of principles, MINOR for new principles or materially expanded guidance, PATCH
for clarifications and wording fixes.

Compliance is checked in code review and in the Constitution Check step of Spec Kit plans.
Violations MUST be fixed or explicitly justified and recorded.

**Version**: 1.0.0 | **Ratified**: 2026-11-01 | **Last Amended**: 2026-11-01
