#!/usr/bin/env bash
# Build dist/tefteri-<version>-x86_64.AppImage from the Flutter Linux bundle.
# Run through `just packaging::appimage`. TEFTERI_VERSION sets the version in the file name.
# Uses appimagetool from PATH, or downloads it once to ~/.cache/tefteri.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
bundle=${TEFTERI_BUNDLE:-${root}/frontend/build/linux/x64/release/bundle}
version=${TEFTERI_VERSION:-$(sed -n 's/^version: \([^+]*\).*/\1/p' "${root}/frontend/pubspec.yaml")}
dist=${root}/dist
tool_url=https://github.com/AppImage/appimagetool/releases/download/1.9.0/appimagetool-x86_64.AppImage

[[ -x ${bundle}/tefteri ]] || {
    echo "appimage: no Linux bundle at ${bundle} (run just frontend::build-linux)" >&2
    exit 1
}

tool=$(command -v appimagetool || true)
if [[ -z ${tool} ]]; then
    tool=${HOME}/.cache/tefteri/appimagetool
    if [[ ! -x ${tool} ]]; then
        mkdir -p "$(dirname "${tool}")"
        curl -fsSL -o "${tool}" "${tool_url}"
        chmod +x "${tool}"
    fi
fi

appdir=$(mktemp -d)
trap 'rm -rf "$appdir"' EXIT

mkdir -p "${appdir}/usr/lib/tefteri"
cp -r "${bundle}/." "${appdir}/usr/lib/tefteri/"
cp "${root}/packaging/tefteri.desktop" "${appdir}/tefteri.desktop"
cp "${root}/frontend/web/icons/Icon-512.png" "${appdir}/tefteri.png"
cat >"${appdir}/AppRun" <<'APPRUN'
#!/bin/sh
here=$(dirname "$(readlink -f "$0")")
exec "$here/usr/lib/tefteri/tefteri" "$@"
APPRUN
chmod +x "${appdir}/AppRun"

mkdir -p "${dist}"
# --appimage-extract-and-run: works without FUSE (for example in CI containers).
ARCH=x86_64 VERSION=${version} "${tool}" --appimage-extract-and-run "${appdir}" \
    "${dist}/tefteri-${version}-x86_64.AppImage"
