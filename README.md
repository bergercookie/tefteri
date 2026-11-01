# Tefteri

Daily planning and execution framework: a Python backend plus a Flutter client that sync with
your own task, calendar and note apps (Vikunja, Google Calendar, Trilium Next).

## Setup

```sh
devbox shell
just backend::install frontend::install
just --list
```

## Tooling exceptions to devbox

- Docker (>= 24) for image builds and the smoke test.
- Android SDK (for `just packaging::apk`) if devbox cannot provide it reliably.

See `CONTRIBUTING.md`. Specs live in `specs/`.
