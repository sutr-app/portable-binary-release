# shellcheck shell=bash
# Shared by every script behind the actions: error exits, the platform name
# the actions use, and hand-over to later workflow steps.
#
# Kept compatible with the bash 3.2 shipped with macOS.

# die <message>: a check failed.
die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

# usage_error <message>: the caller passed something wrong.
usage_error() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 2
}

# host_platform: the running host as <os>-<arch> (linux-x86_64,
# linux-aarch64, darwin-arm64).
host_platform() {
  printf '%s-%s\n' "$(uname -s | tr '[:upper:]' '[:lower:]')" "$(uname -m)"
}

# export_github_env <name> <value>: make <name> available to later steps of a
# GitHub Actions job; a no-op elsewhere.
export_github_env() {
  if [[ -n "${GITHUB_ENV-}" ]]; then
    echo "$1=$2" >>"${GITHUB_ENV}"
  fi
}

# set_step_output <name> <value>: set an output of the current step (the
# action's outputs map to it); a no-op elsewhere.
set_step_output() {
  if [[ -n "${GITHUB_OUTPUT-}" ]]; then
    echo "$1=$2" >>"${GITHUB_OUTPUT}"
  fi
}
