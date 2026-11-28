# Release recipes. Call as `just release::<recipe>`.
# The GitHub workflow release.yml calls only these recipes.
# Recipes run in this directory, so paths to the repository root start with `..`.
# The version comes from TEFTERI_RELEASE_VERSION (the workflow sets it from `next`), or from the
# tag vX.Y.Z at HEAD. See scripts/version.sh.

# List the recipes of this module.
default:
    @just --list release

# Print the next release version, one patch above the newest version tag.
next-version:
    bash ../scripts/version.sh next

# Print GITHUB_OUTPUT lines: needed (HEAD has no version tag yet), version and tag.
next:
    @bash ../scripts/version.sh next-outputs

# Build the server image for the release version; push it as X.Y.Z and latest.
image:
    TEFTERI_VERSION="$(bash ../scripts/version.sh release pep440)" TEFTERI_FLUTTER_VERSION="$(bash ../scripts/version.sh release flutter)" just deploy::build-image
    just deploy::push-image "$(bash ../scripts/version.sh release)" latest

# Build all client packages for the release version into dist/.
clients: clients-linux clients-android

# Build the .deb package and the AppImage. Run it outside devbox, with the system GTK.
clients-linux:
    TEFTERI_VERSION="$(bash ../scripts/version.sh release)" TEFTERI_FLUTTER_VERSION="$(bash ../scripts/version.sh release flutter)" just packaging::deb packaging::appimage

# Build the .apk. This needs the Android SDK and the Flutter SDK of devbox.
clients-android:
    TEFTERI_VERSION="$(bash ../scripts/version.sh release)" TEFTERI_FLUTTER_VERSION="$(bash ../scripts/version.sh release flutter)" just packaging::apk

# Create the GitHub release with the packages in dist/. This also creates the tag vX.Y.Z at HEAD,
# the commit that was built.
publish:
    gh release create "v$(bash ../scripts/version.sh release)" ../dist/* --target "$(git rev-parse HEAD)" --generate-notes
