#!/usr/bin/env bash
# Usage: install-protoc.sh [dest-dir]
#
# Installs the pinned protoc release (scripts/pins/protoc.sh) into dest-dir,
# default $RUNNER_TEMP/protoc, after verifying its SHA-256, with no root
# privileges, so every runner compiles protobuf code with the same, publicly
# visible compiler. Under GitHub Actions it exports PROTOC (read by
# prost-build and others) and sets the step outputs path and version.
#
# Environment, for tests: PROTOC_PLATFORM overrides the detected
# <os>-<arch>; PROTOC_BASE_URL replaces the download location (the pinned
# SHA-256 still applies).
#
# Exit status: 1 when the download or the installed binary fails a check, 2 on
# usage errors. Kept compatible with the bash 3.2 shipped with macOS.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=scripts/lib/fetch-pinned.sh
source "${SCRIPT_DIR}/lib/fetch-pinned.sh"
# shellcheck source=scripts/pins/protoc.sh
source "${SCRIPT_DIR}/pins/protoc.sh"

dest=${1:-${RUNNER_TEMP:+${RUNNER_TEMP}/protoc}}
[[ -n "${dest}" ]] || usage_error "usage: $0 <dest-dir> (or set RUNNER_TEMP)"
platform=${PROTOC_PLATFORM:-$(host_platform)}
base_url=${PROTOC_BASE_URL:-${PROTOC_RELEASE_URL}}

protoc_release "${platform}" || usage_error "no pinned protoc for platform ${platform}"

work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT

fetch_pinned "${base_url}/${protoc_asset}" "${protoc_sha256}" "${work}/${protoc_asset}"

dest=$(make_absolute_dir "${dest}")
unzip -q -o "${work}/${protoc_asset}" -d "${dest}"
expect_version_output "${dest}/bin/protoc" "libprotoc ${PROTOC_VERSION}"
hand_over PROTOC "${dest}/bin/protoc" "${PROTOC_VERSION}"
