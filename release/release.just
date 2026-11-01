# Release and nightly build recipes. Call as `just release::<recipe>`.
# The GitHub workflows release.yml and nightly.yml call only these recipes.
# Recipes run in this directory, so paths to the repository root start with `..`.

# --- Tagged releases ---

# Build the server image for the release tag at HEAD; push it as X.Y.Z and latest.
image:
    TEFTERI_VERSION="$(bash ../scripts/version.sh release pep440)" just deploy::build-image
    just deploy::push-image "$(bash ../scripts/version.sh release)" latest

# Build the client packages for the release tag at HEAD into dist/.
clients:
    TEFTERI_VERSION="$(bash ../scripts/version.sh release)" TEFTERI_FLUTTER_VERSION="$(bash ../scripts/version.sh release flutter)" just packaging::deb packaging::appimage packaging::apk

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
nightly-image image pep440:
    TEFTERI_VERSION="{{ pep440 }}" just deploy::build-image
    just deploy::push-image "{{ image }}" nightly

# Build the nightly client packages into dist/.
nightly-clients image flutter:
    TEFTERI_VERSION="{{ image }}" TEFTERI_FLUTTER_VERSION="{{ flutter }}" just packaging::deb packaging::appimage packaging::apk

# Replace the rolling `nightly` pre-release with the packages in dist/.
nightly-publish image:
    gh release delete nightly --cleanup-tag --yes || true
    gh release create nightly ../dist/* --prerelease --target "$(git rev-parse HEAD)" --title "Nightly {{ image }}" --notes "Nightly build {{ image }} of commit $(git rev-parse --short HEAD)."
