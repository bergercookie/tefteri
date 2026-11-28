#!/usr/bin/env bash
# Compute the version of the next tefteri release, and the forms of a version.
#
# Usage:
#   version.sh next                    # the next version, for example 1.2.4
#   version.sh next-outputs            # GITHUB_OUTPUT lines: needed, version, tag
#   version.sh release [image|pep440|flutter]
#
# Every push to the main branch is a release. Its version is one patch above the newest version
# tag. A version tag is vX.Y.Z or vX.Y (the v is optional), and the newest is the highest
# version, not the latest tag in time. A missing patch number counts as 0:
#   newest tag 1.2.3 -> next 1.2.4
#   newest tag 3.3   -> next 3.3.1
#   no tag           -> next 0.0.1
# To start a new major or minor version, push a tag by hand, for example `git tag v1.3`: the
# next release is then 1.3.1. Tags that are not versions (such as the old `nightly-...` tags)
# are ignored.
#
# `release` prints the version that the recipes of `release/release.just` build. It is the
# version in TEFTERI_RELEASE_VERSION (the workflow sets it from `next`), or else the version
# of the tag vX.Y.Z at HEAD, so that the recipes also work on your computer.
#   image and pep440  X.Y.Z      (image tag, Python package, file names)
#   flutter           X.Y.Z+<commits up to HEAD>   (Android needs a build number above 0)
set -euo pipefail
# Let a failure inside $(...) stop the script too.
shopt -s inherit_errexit

readonly version_tag='^v?[0-9]+\.[0-9]+(\.[0-9]+)?$'

die() {
    echo "version.sh: $*" >&2
    exit 1
}

# The newest version tag without its v, or nothing when there is none.
newest_tag() {
    git tag --list | grep -E "${version_tag}" | sed 's/^v//' | sort -V | tail -n 1 || true
}

next() {
    local newest major minor patch
    newest=$(newest_tag)
    newest=${newest:-0.0.0}
    IFS=. read -r major minor patch <<<"${newest}"
    echo "${major}.${minor}.$((${patch:-0} + 1))"
}

# Prints true when HEAD has a version tag already: it is a release, so nothing is made for it.
head_released() {
    if git tag --points-at HEAD | grep -Eq "${version_tag}"; then
        echo true
    else
        echo false
    fi
}

next_outputs() {
    local version released needed=true
    version=$(next)
    released=$(head_released)
    if [[ ${released} == true ]]; then
        needed=false
    fi
    echo "needed=${needed}"
    echo "version=${version}"
    echo "tag=v${version}"
}

release() {
    local form=${1:-image} version tag
    version=${TEFTERI_RELEASE_VERSION:-}
    if [[ -z ${version} ]]; then
        tag=$(git describe --tags --exact-match --match 'v[0-9]*' 2>/dev/null || true)
        [[ ${tag} =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]] || die "set TEFTERI_RELEASE_VERSION, or tag HEAD vX.Y.Z"
        version=${BASH_REMATCH[1]}
    fi
    [[ ${version} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "not a version X.Y.Z: ${version}"
    case ${form} in
    image | pep440) echo "${version}" ;;
    flutter) echo "${version}+$(git rev-list --count HEAD)" ;;
    *) die "unknown form: ${form}" ;;
    esac
}

case ${1:-} in
next) next ;;
next-outputs) next_outputs ;;
release) release "${2:-image}" ;;
*) die "usage: version.sh next | next-outputs | release [image|pep440|flutter]" ;;
esac
