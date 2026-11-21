#!/usr/bin/env bash
# Runs every tests/test-*.sh and fails when any of them fails.
set -uo pipefail

status=0
for test in "$(dirname "${BASH_SOURCE[0]}")"/test-*.sh; do
  bash "${test}" || status=1
done
exit "${status}"
