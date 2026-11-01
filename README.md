# Tefteri

Tefteri is a framework to plan and do your daily work. It has a Python backend and a Flutter client.
They sync with your own task, calendar and note apps (Vikunja, Google Calendar, Trilium Next).

## Setup

```sh
devbox shell
just backend::install frontend::install
just --list
```

## Tooling exceptions to devbox

- Docker (>= 24) for image builds and the smoke test.
- Android SDK (for `just packaging::apk`) if devbox cannot provide it reliably.
- The Linux desktop build tools for `just frontend::build-linux` and the AppImage:
  `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`, `file` and
  `desktop-file-utils` (from the system package manager).

See `CONTRIBUTING.md`. Specs live in `specs/`.
