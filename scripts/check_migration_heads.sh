#!/usr/bin/env bash
# Fail when the Alembic history is broken: more than one head, or a revision id used twice.
# Two branches that each add the next revision number merge cleanly in git, but the app then
# refuses to start ("Multiple head revisions"). Run by pre-commit and by `just lint`.
set -euo pipefail

cd "$(dirname "$0")/../backend"
output="$(uv run alembic heads 2>&1)" || {
	echo "${output}" >&2
	echo "alembic could not read the migration history." >&2
	exit 1
}

heads="$(grep -c '(head)' <<<"${output}" || true)"
if [[ "${heads}" -ne 1 ]] || grep -q 'present more than once' <<<"${output}"; then
	echo "${output}" >&2
	echo >&2
	echo "The migration history must have one head and no repeated revision id." >&2
	echo "Renumber the newer migration so that it revises the current head." >&2
	exit 1
fi
