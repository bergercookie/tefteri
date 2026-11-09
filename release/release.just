# Release and nightly build recipes. Call as `just release::<recipe>`.
# The GitHub workflows release.yml and nightly.yml call only these recipes.
# Recipes run in this directory, so paths to the repository root start with `..`.

# List the recipes of this module.
default:
    @just --list release

# --- Tagged releases ---

# Build the server image for the release tag at HEAD; push it as X.Y.Z and latest.
image:
    TEFTERI_VERSION="$(bash ../scripts/version.sh release pep440)" TEFTERI_FLUTTER_VERSION="$(bash ../scripts/version.sh release flutter)" just deploy::build-image
    just deploy::push-image "$(bash ../scripts/version.sh release)" latest

# Build all client packages for the release tag at HEAD into dist/.
clients: clients-linux clients-android

# Build the .deb package and the AppImage. Run it outside devbox, with the system GTK.
clients-linux:
    TEFTERI_VERSION="$(bash ../scripts/version.sh release)" TEFTERI_FLUTTER_VERSION="$(bash ../scripts/version.sh release flutter)" just packaging::deb packaging::appimage

# Build the .apk. This needs the Android SDK and the Flutter SDK of devbox.
clients-android:
    TEFTERI_VERSION="$(bash ../scripts/version.sh release)" TEFTERI_FLUTTER_VERSION="$(bash ../scripts/version.sh release flutter)" just packaging::apk

# Create the GitHub release for the tag at HEAD with the packages in dist/.
publish:
    gh release create "v$(bash ../scripts/version.sh release)" ../dist/* --verify-tag --generate-notes

# --- Nightly builds ---

# Print the nightly version string.
version-nightly:
    bash ../scripts/version.sh nightly

# Print GITHUB_OUTPUT lines: needed (HEAD has no nightly yet) and the three version forms.
nightly-versions:
    @if bash ../scripts/version.sh nightly-built; then echo needed=false; else echo needed=true; fi
    @echo "image=$(bash ../scripts/version.sh nightly image)"
    @echo "pep440=$(bash ../scripts/version.sh nightly pep440)"
    @echo "flutter=$(bash ../scripts/version.sh nightly flutter)"

# Build the nightly server image; push it as `nightly` and as the version string.
nightly-image image pep440 flutter:
    TEFTERI_VERSION="{{ pep440 }}" TEFTERI_FLUTTER_VERSION="{{ flutter }}" just deploy::build-image
    just deploy::push-image "{{ image }}" nightly

# Build all nightly client packages into dist/.
nightly-clients image flutter: (nightly-clients-linux image flutter) (nightly-clients-android image flutter)

# Build the nightly .deb package and AppImage. Run outside devbox (see `clients-linux`).
nightly-clients-linux image flutter:
    TEFTERI_VERSION="{{ image }}" TEFTERI_FLUTTER_VERSION="{{ flutter }}" just packaging::deb packaging::appimage

# Build the nightly .apk.
nightly-clients-android image flutter:
    TEFTERI_VERSION="{{ image }}" TEFTERI_FLUTTER_VERSION="{{ flutter }}" just packaging::apk

# Publish the nightly packages. Every build gets its own pre-release `nightly-<version>`, and only
# the newest `keep` of them stay. The pre-release `nightly` always holds the newest build: the
# update check of the app reads it, so it is replaced each time.
nightly-publish image keep="5":
    gh release create "nightly-{{ image }}" ../dist/* --prerelease --target "$(git rev-parse HEAD)" --title "Nightly {{ image }}" --notes "Nightly build {{ image }} of commit $(git rev-parse --short HEAD)."
    gh release delete nightly --cleanup-tag --yes || true
    gh release create nightly ../dist/* --prerelease --target "$(git rev-parse HEAD)" --title "Nightly {{ image }}" --notes "Nightly build {{ image }} of commit $(git rev-parse --short HEAD)."
    just release::nightly-prune "{{ keep }}"

# Delete the pre-releases `nightly-<version>` (and their tags) except the newest `keep`.
nightly-prune keep="5":
    #!/usr/bin/env bash
    set -euo pipefail
    old=$(gh release list --limit 200 --json tagName,createdAt --jq '[.[] | select(.tagName | startswith("nightly-"))] | sort_by(.createdAt) | reverse | .[{{ keep }}:] | .[].tagName')
    for tag in ${old}; do
        gh release delete "${tag}" --cleanup-tag --yes
    done
