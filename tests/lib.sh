# shellcheck shell=bash
# Shared by the tests/test-*.sh scripts: the repository paths, a scratch
# directory removed on exit, a failure counter and the final verdict.
#
# Kept compatible with the bash 3.2 shipped with macOS.

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "${TESTS_DIR}/.." && pwd)
# shellcheck disable=SC2034 # read by the tests sourcing this file
SCRIPTS_DIR="${ROOT_DIR}/scripts"

work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT

failures=0
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failures=$((failures + 1))
}

# expect_status <status> <description> <command...>: run the command and
# record a failure unless it exits with <status>. Its output goes to
# ${work}/out.
expect_status() {
  local expected=$1 description=$2 actual=0
  shift 2
  "$@" >"${work}/out" 2>&1 || actual=$?
  [[ "${actual}" == "${expected}" ]] \
    || fail "${description}: exit ${actual}, expected ${expected}: $(cat "${work}/out")"
}

# finish <name>: exit non-zero when any check failed.
finish() {
  [[ "${failures}" -eq 0 ]] || exit 1
  echo "PASS: $1"
}
