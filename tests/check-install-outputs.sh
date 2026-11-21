#!/usr/bin/env bash
# Usage: check-install-outputs.sh <env-name> <path-output> <expected-version-line> [expected-path]
#
# Run by the CI after an install-* action: its path output, the variable it
# exports (<env-name>) and what the installed binary reports for --version
# must agree.
set -euo pipefail

name=$1 path=$2 expected=$3 expected_path=${4-}
fail() {
  echo "FAIL: $*" >&2
  exit 1
}
[[ -z "${expected_path}" || "${path}" == "${expected_path}" ]] || fail "path output ${path}, expected ${expected_path}"
[[ "${!name-}" == "${path}" ]] || fail "${name} is '${!name-}', expected ${path}"
reported=$("${path}" --version)
[[ "${reported}" == "${expected}" ]] || fail "${path} reports '${reported}', expected '${expected}'"
echo "OK: ${reported} at ${path}"
