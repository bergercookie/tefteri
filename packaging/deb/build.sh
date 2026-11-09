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

bash "${root}/packaging/check-bundle.sh" "${bundle}"

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

desktop=${root}/packaging/dev.bergercookie.tefteri.desktop
if command -v desktop-file-validate >/dev/null; then
    desktop-file-validate "${desktop}"
fi

mkdir -p "${stage}/DEBIAN" "${stage}/opt/tefteri" "${stage}/usr/bin" \
    "${stage}/usr/share/applications" "${stage}/usr/share/pixmaps"
cp -r "${bundle}/." "${stage}/opt/tefteri/"
ln -s /opt/tefteri/tefteri "${stage}/usr/bin/tefteri"
# The file name is the application ID of the program. The desktop then ties the window to the
# launcher and shows its icon.
cp "${desktop}" "${stage}/usr/share/applications/dev.bergercookie.tefteri.desktop"
for size in 192 512; do
    mkdir -p "${stage}/usr/share/icons/hicolor/${size}x${size}/apps"
    cp "${root}/frontend/web/icons/Icon-${size}.png" \
        "${stage}/usr/share/icons/hicolor/${size}x${size}/apps/tefteri.png"
done
cp "${root}/frontend/web/icons/Icon-512.png" "${stage}/usr/share/pixmaps/tefteri.png"

cat >"${stage}/DEBIAN/control" <<CONTROL
Package: tefteri
Version: ${version}
Architecture: amd64
Maintainer: Tefteri maintainers <noreply@github.com>
Depends: libgtk-3-0 (>= 3.24), libegl1, libgl1, libblkid1, liblzma5
Section: utils
Priority: optional
Homepage: https://github.com/bergercookie/tefteri
Description: Tefteri daily planning client
 Plan and do your daily work with your own task, calendar and note apps.
CONTROL

# Refresh the caches of the desktop, so that the launcher and the icon show at once.
for script in postinst postrm; do
    cat >"${stage}/DEBIAN/${script}" <<'SCRIPT'
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
fi
exit 0
SCRIPT
    chmod 0755 "${stage}/DEBIAN/${script}"
done

mkdir -p "${dist}"
dpkg-deb --build --root-owner-group "${stage}" "${dist}/tefteri_${version}_amd64.deb"
