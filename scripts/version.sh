#!/usr/bin/env bash
# Compute tefteri version strings for releases and nightly builds.
#
# Usage:
#   version.sh nightly [image|pep440|flutter]   # default form: image
#   version.sh release [image|pep440|flutter]
#   version.sh nightly-built                    # exit 0 when HEAD already has a nightly
#
# Nightly forms, for previous stable release 1.4.0, commit a1b2c3d and post number 3:
#   image    1.4.0.a1b2c3d.post3   (image tag and artifact names; not PEP 440)
#   pep440   1.4.0.post3+a1b2c3d   (Python package version)
#   flutter  1.4.0+3               (Flutter build name and build number)
# Release forms for tag v1.5.0: image and pep440 1.5.0, flutter 1.5.0+<commits up to HEAD>
# (Android needs a build number above 0).
# All three forms come from the same inputs. The previous stable release is the newest
# tag vX.Y.Z reachable from HEAD (0.0.0 when there is none). The post number is one more
# than the highest .postN already published for that release.
#
# Published tags come from TEFTERI_PUBLISHED_TAGS (one tag on each line) when it is set.
# Otherwise the script reads the tags of ghcr.io/bergercookie/tefteri with `gh api`.
set -euo pipefail
# Let a failure inside $(...) stop the script too.
shopt -s inherit_errexit

readonly package_path="/users/bergercookie/packages/container/tefteri/versions"

die() {
    echo "version.sh: $*" >&2
    exit 1
}

previous_stable() {
    local tag
    tag=$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null || true)
    if [[ -z ${tag} ]]; then
        echo "0.0.0"
    else
        echo "${tag#v}"
    fi
}

short_hash() {
    git rev-parse --short=7 HEAD
}

published_tags() {
    if [[ -n ${TEFTERI_PUBLISHED_TAGS+set} ]]; then
        printf '%s\n' "${TEFTERI_PUBLISHED_TAGS}"
        return
    fi
    local out
    if out=$(gh api --paginate "${package_path}" --jq '.[].metadata.container.tags[]' 2>&1); then
        printf '%s\n' "${out}"
    elif [[ ${out} == *"(HTTP 404)"* ]]; then
        # The image was never published: there are no tags yet.
        return 0
    else
        die "cannot read the published image tags (set TEFTERI_PUBLISHED_TAGS): ${out}"
    fi
}

# Highest post number published for the stable release $1 (0 when there is none).
highest_post() {
    local stable=$1 tags tag max=0 n
    local pattern="^${stable//./\\.}\\.[0-9a-f]+\\.post([0-9]+)$"
    tags=$(published_tags)
    while IFS= read -r tag; do
        if [[ ${tag} =~ ${pattern} ]]; then
            n=${BASH_REMATCH[1]}
            if ((n > max)); then
                max=${n}
            fi
        fi
    done <<<"${tags}"
    echo "${max}"
}

nightly() {
    local form=${1:-image} stable hash highest post
    stable=$(previous_stable)
    hash=$(short_hash)
    highest=$(highest_post "${stable}")
    post=$((highest + 1))
    case ${form} in
    image) echo "${stable}.${hash}.post${post}" ;;
    pep440) echo "${stable}.post${post}+${hash}" ;;
    flutter) echo "${stable}+${post}" ;;
    *) die "unknown form: ${form}" ;;
    esac
}

release() {
    local form=${1:-image} tag
    tag=${GITHUB_REF_NAME:-$(git describe --tags --exact-match --match 'v[0-9]*' 2>/dev/null || true)}
    [[ ${tag} =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]] || die "HEAD has no release tag vX.Y.Z"
    case ${form} in
    image | pep440) echo "${BASH_REMATCH[1]}" ;;
    flutter) echo "${BASH_REMATCH[1]}+$(git rev-list --count HEAD)" ;;
    *) die "unknown form: ${form}" ;;
    esac
}

nightly_built() {
    local hash tags
    hash=$(short_hash)
    tags=$(published_tags)
    grep -Eq "\\.${hash}\\.post[0-9]+$" <<<"${tags}"
}

case ${1:-} in
nightly) nightly "${2:-image}" ;;
release) release "${2:-image}" ;;
nightly-built) nightly_built ;;
*) die "usage: version.sh nightly|release [image|pep440|flutter] | nightly-built" ;;
esac
