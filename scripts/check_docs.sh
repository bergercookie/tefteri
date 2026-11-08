#!/usr/bin/env bash
# Check the documentation: required guides exist, every page in a toctree exists, and every
# image has alt text and points to an existing file. Run through `just docs::check`.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
docs=${root}/docs
failures=0

fail() {
    echo "check_docs: $*" >&2
    failures=$((failures + 1))
}

# Guides that the tasks require (T122, T124-T131, T107, T114).
required=(
    user/getting-started.md
    user/connect-apps.md
    user/daily-planning.md
    user/scheduling.md
    user/conflicts.md
    user/planning-goals.md
    user/weekly-planning.md
    user/accounts-and-sign-in.md
    user/reviews-and-retrospectives.md
    user/shortcuts.md
    user/troubleshooting.md
    developer/setup.md
    developer/testing.md
    developer/releases.md
)
for page in "${required[@]}"; do
    [[ -f ${docs}/${page} ]] || fail "missing required guide docs/${page}"
done

# Every entry of the toctree in each section index must exist.
for index in user/index.md developer/index.md; do
    section=$(dirname "${index}")
    while IFS= read -r entry; do
        [[ -f ${docs}/${section}/${entry}.md ]] \
            || fail "docs/${index} lists '${entry}' but docs/${section}/${entry}.md is missing"
    done < <(awk '/^```\{toctree\}/ {in_tree = 1; next}
        /^```/ {in_tree = 0}
        in_tree && $0 !~ /^:/ && NF {print $1}' "${docs}/${index}")
done

# Every Markdown image needs alt text and an existing target.
while IFS= read -r -d '' page; do
    rel=${page#"${root}"/}
    while IFS= read -r image; do
        alt=${image#'!['}
        alt=${alt%%']('*}
        target=${image#*']('}
        target=${target%')'}
        target=${target%% *}
        [[ -n ${alt// /} ]] || fail "${rel}: image ${target} has no alt text"
        [[ ${target} == http* || -f $(dirname "${page}")/${target} ]] \
            || fail "${rel}: image ${target} does not exist"
    done < <(grep -o '!\[[^]]*\]([^)]*)' "${page}" || true)
done < <(find "${docs}" -name '*.md' -not -path '*/_build/*' -print0)

if ((failures > 0)); then
    echo "check_docs: ${failures} problem(s) found" >&2
    exit 1
fi
echo "check_docs: all documentation checks passed"
