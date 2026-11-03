#!/usr/bin/env bash
# Start and stop a throw-away Vikunja for the live tests. Never use it for real data.
#
#   scripts/vikunja-dev.sh start    download (once) and start Vikunja, print the URL
#   scripts/vikunja-dev.sh stop     stop it and delete its data
#   scripts/vikunja-dev.sh status   say whether it runs
#   scripts/vikunja-dev.sh url      print the URL
#
# Settings (environment variables):
#   VIKUNJA_DEV_VERSION   version to run, for example v2.7.1 or 0.24.6 (default v2.7.1)
#   VIKUNJA_DEV_PORT      port on 127.0.0.1 (default 3456)
#   VIKUNJA_DEV_TIMEZONE  time zone of the Vikunja server (default UTC)
#
# The binary comes from https://dl.vikunja.io and its SHA-256 sum is checked. This works on
# Linux with an x86-64 CPU. On another system, run Vikunja yourself (for example with Docker)
# and set TEFTERI_LIVE_VIKUNJA_URL for `just backend::live-vikunja`.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
version=${VIKUNJA_DEV_VERSION:-v2.7.1}
port=${VIKUNJA_DEV_PORT:-3456}
timezone=${VIKUNJA_DEV_TIMEZONE:-UTC}
state=${root}/.cache/vikunja-dev
run_dir=${state}/run-${port}
pid_file=${run_dir}/vikunja.pid
url=http://127.0.0.1:${port}

die() {
    echo "vikunja-dev: $*" >&2
    exit 1
}

binary_path() {
    local file_version=${version}
    [[ ${file_version} == v* ]] || file_version=v${file_version}
    echo "${state}/${version}/vikunja-${file_version}-linux-amd64"
}

fetch_binary() {
    local binary
    binary=$(binary_path)
    [[ -x ${binary} ]] && return 0
    [[ $(uname -s)-$(uname -m) == Linux-x86_64 ]] \
        || die "no download for $(uname -s)-$(uname -m). Run Vikunja yourself and set TEFTERI_LIVE_VIKUNJA_URL."
    local file_version=${version}
    [[ ${file_version} == v* ]] || file_version=v${file_version}
    local base="https://dl.vikunja.io/vikunja/${version}"
    local zip="vikunja-${file_version}-linux-amd64-full.zip"
    local work
    work=$(mktemp -d)
    echo "vikunja-dev: downloading ${zip}" >&2
    curl --fail --silent --show-error --location --output "${work}/${zip}" "${base}/${zip}" \
        || die "cannot download ${base}/${zip}"
    mkdir -p "${state}/${version}"
    python3 -I -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' \
        "${work}/${zip}" "${work}/unpacked"
    local sum_file
    sum_file=$(find "${work}/unpacked" -name '*.sha256' | head -n 1)
    if [[ -n ${sum_file} ]]; then
        (cd "$(dirname "${sum_file}")" && sha256sum --check --status "$(basename "${sum_file}")") \
            || die "the SHA-256 sum of the download is wrong"
    else
        echo "vikunja-dev: the download has no .sha256 file; the sum was not checked" >&2
    fi
    install -m 755 "${work}/unpacked/$(basename "${binary}")" "${binary}"
    rm -rf "${work}"
}

# Prints "running" or "stopped".
state_of() {
    if [[ -f ${pid_file} ]] && kill -0 "$(cat "${pid_file}")" 2>/dev/null; then
        echo running
    else
        echo stopped
    fi
}

start() {
    local current
    current=$(state_of)
    if [[ ${current} == running ]]; then
        echo "${url}"
        return 0
    fi
    fetch_binary
    rm -rf "${run_dir}"
    mkdir -p "${run_dir}/files"
    (
        cd "${run_dir}"
        export VIKUNJA_SERVICE_INTERFACE="127.0.0.1:${port}"
        export VIKUNJA_SERVICE_PUBLICURL="${url}/"
        export VIKUNJA_SERVICE_ENABLEREGISTRATION=true
        export VIKUNJA_SERVICE_JWTSECRET=tefteri-live-test-secret
        export VIKUNJA_SERVICE_TIMEZONE="${timezone}"
        export VIKUNJA_DATABASE_TYPE=sqlite
        export VIKUNJA_DATABASE_PATH="${run_dir}/vikunja.db"
        export VIKUNJA_FILES_BASEPATH="${run_dir}/files"
        export VIKUNJA_MAILER_ENABLED=false
        export VIKUNJA_RATELIMIT_ENABLED=false
        nohup "$(binary_path)" >"${run_dir}/vikunja.log" 2>&1 &
        echo $! >"${pid_file}"
    )
    for _ in $(seq 1 60); do
        if curl --silent --fail --max-time 2 "${url}/api/v1/info" >/dev/null 2>&1; then
            echo "${url}"
            return 0
        fi
        sleep 0.5
    done
    tail -n 20 "${run_dir}/vikunja.log" >&2 || true
    die "Vikunja did not start. The log is ${run_dir}/vikunja.log"
}

stop() {
    local current
    current=$(state_of)
    if [[ ${current} == running ]]; then
        kill "$(cat "${pid_file}")" 2>/dev/null || true
    fi
    rm -rf "${run_dir}"
}

case ${1:-} in
start) start ;;
stop) stop ;;
status)
    current=$(state_of)
    if [[ ${current} == running ]]; then echo "running at ${url}"; else echo stopped; fi
    ;;
url) echo "${url}" ;;
*) die "usage: vikunja-dev.sh start|stop|status|url" ;;
esac
