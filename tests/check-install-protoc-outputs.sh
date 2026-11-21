#!/usr/bin/env bash
# Usage: check-install-protoc-outputs.sh <path-output> <version-output> [expected-path]
#
# Run by the CI after the install-protoc action: its outputs, the exported
# PROTOC and the installed binary must agree.
set -euo pipefail

path=$1 version=$2 expected_path=${3-}
[[ -z "${expected_path}" || "${path}" == "${expected_path}" ]] || { echo "path output ${path}, expected ${expected_path}" >&2; exit 1; }
[[ "${PROTOC-}" == "${path}" ]] || { echo "PROTOC is '${PROTOC-}', expected ${path}" >&2; exit 1; }
reported=$("${path}" --version)
[[ "${reported}" == "libprotoc ${version}" ]] || { echo "${path} reports '${reported}', expected 'libprotoc ${version}'" >&2; exit 1; }
echo "OK: ${reported} at ${path}"
