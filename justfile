# Tefteri: the single entry point for every repeatable task.

set shell := ["bash", "-euo", "pipefail", "-c"]

mod backend 'backend/backend.just'
mod frontend 'frontend/frontend.just'
mod deploy 'deploy/deploy.just'
mod docs 'docs/docs.just'
mod packaging 'packaging/packaging.just'
mod release 'release/release.just'

# List recipes.
default:
    @just --list

# Run every lint/format check (single list lives in .pre-commit-config.yaml).
lint:
    pre-commit run --all-files

# Run all test suites.
test: backend::test frontend::test

# Build all deliverables.
build: deploy::build-image frontend::build-linux frontend::build-web docs::build

# Run the backend locally.
run: backend::run

# Prompt for a password and print its Argon2 hash.
hash-password:
    uv run --project backend python scripts/hash_password.py
