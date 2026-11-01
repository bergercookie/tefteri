# Client packaging recipes. Call as `just packaging::<recipe>`.
# TEFTERI_VERSION (from scripts/version.sh) sets the package version. Output goes to dist/.

deb:
    just frontend::build-linux
    bash deb/build.sh

appimage:
    just frontend::build-linux
    bash appimage/build.sh

# Signed with the release keystore when TEFTERI_KEYSTORE_BASE64 (CI secret) or
# TEFTERI_KEYSTORE and the passwords are set; otherwise debug-signed.
apk:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -n ${TEFTERI_KEYSTORE_BASE64:-} ]]; then
        TEFTERI_KEYSTORE=$(mktemp --suffix=.jks)
        export TEFTERI_KEYSTORE
        trap 'rm -f "$TEFTERI_KEYSTORE"' EXIT
        base64 -d <<<"$TEFTERI_KEYSTORE_BASE64" >"$TEFTERI_KEYSTORE"
    fi
    just frontend::build-apk
    mkdir -p ../dist
    cp ../frontend/build/app/outputs/flutter-apk/app-release.apk "../dist/tefteri-${TEFTERI_VERSION:-dev}.apk"
