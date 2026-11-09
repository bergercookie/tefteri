#!/usr/bin/env bash
# Fail when a program or library of the Flutter Linux bundle depends on files outside the
# system, such as /nix/store. Such a bundle starts only on the computer that built it: on other
# computers it stops with errors like "No provider of eglGetPlatformDisplayEXT found".
# Usage: check-bundle.sh <bundle directory>
set -euo pipefail

bundle=${1:?usage: check-bundle.sh <bundle directory>}
bad=0
while IFS= read -r -d '' file; do
    readelf -h "${file}" >/dev/null 2>&1 || continue
    interpreter=$(readelf -l "${file}" 2>/dev/null | sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p')
    search=$(readelf -d "${file}" 2>/dev/null | grep -E '\((RPATH|RUNPATH)\)' || true)
    if [[ ${interpreter} == /nix/* || ${search} == */nix/store/* ]]; then
        echo "bundle: ${file#"${bundle}"/} is linked to /nix/store" >&2
        bad=1
    fi
done < <(find "${bundle}" -type f -print0)

if ((bad)); then
    echo "bundle: build the Linux bundle outside devbox, with the system compiler and GTK" >&2
    exit 1
fi
