#!/usr/bin/env bash
# Build dist/tefteri_<version>_amd64.deb from the Flutter Linux bundle.
# Run through `just packaging::deb`. TEFTERI_VERSION sets the package version.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
bundle=${TEFTERI_BUNDLE:-${root}/frontend/build/linux/x64/release/bundle}
version=${TEFTERI_VERSION:-$(sed -n 's/^version: \([^+]*\).*/\1/p' "${root}/frontend/pubspec.yaml")}
dist=${root}/dist

[[ -x ${bundle}/tefteri ]] || {
    echo "deb: no Linux bundle at ${bundle} (run just frontend::build-linux)" >&2
    exit 1
}

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

mkdir -p "${stage}/DEBIAN" "${stage}/opt/tefteri" "${stage}/usr/bin" \
    "${stage}/usr/share/applications" "${stage}/usr/share/icons/hicolor/512x512/apps"
cp -r "${bundle}/." "${stage}/opt/tefteri/"
ln -s /opt/tefteri/tefteri "${stage}/usr/bin/tefteri"
cp "${root}/packaging/tefteri.desktop" "${stage}/usr/share/applications/tefteri.desktop"
cp "${root}/frontend/web/icons/Icon-512.png" \
    "${stage}/usr/share/icons/hicolor/512x512/apps/tefteri.png"

cat >"${stage}/DEBIAN/control" <<CONTROL
Package: tefteri
Version: ${version}
Architecture: amd64
Maintainer: Tefteri maintainers <noreply@github.com>
Depends: libgtk-3-0
Section: utils
Priority: optional
Homepage: https://github.com/bergercookie/tefteri
Description: Tefteri daily planning client
 Plan and do your daily work with your own task, calendar and note apps.
CONTROL

mkdir -p "${dist}"
dpkg-deb --build --root-owner-group "${stage}" "${dist}/tefteri_${version}_amd64.deb"
