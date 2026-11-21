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

# expect_hand_over <env-name> <path>: the installer run just before exported
# <env-name>=<path> to ${work}/github_env and set the path output in
# ${work}/github_output. reset_hand_over empties both before a run.
reset_hand_over() {
  : >"${work}/github_env"
  : >"${work}/github_output"
}
expect_hand_over() {
  grep -Fxq "$1=$2" "${work}/github_env" || fail "$1 was not exported as $2: $(cat "${work}/github_env")"
  grep -Fxq "path=$2" "${work}/github_output" || fail "the path output is not $2: $(cat "${work}/github_output")"
}

# finish <name>: exit non-zero when any check failed.
finish() {
  [[ "${failures}" -eq 0 ]] || exit 1
  echo "PASS: $1"
}

# expect_verify <status> <description> [VAR=value...] -- <file...>: run
# scripts/verify-binary.sh with the given settings, with STUB_DIR (when set)
# first on PATH, and expect <status>.
expect_verify() {
  local expected=$1 description=$2 settings=()
  shift 2
  while [[ "$1" != -- ]]; do
    settings+=("$1")
    shift
  done
  shift
  expect_status "${expected}" "${description}" \
    env ${STUB_DIR:+PATH="${STUB_DIR}:${PATH}"} ${settings[@]+"${settings[@]}"} \
    bash "${SCRIPTS_DIR}/verify-binary.sh" "$@"
}
