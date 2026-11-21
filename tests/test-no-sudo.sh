#!/usr/bin/env bash
# The actions run on shared self-hosted runners where sudo is not allowed, so
# neither the scripts nor the action and public workflow definitions may call
# it. Comments may mention it.
set -euo pipefail

# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# uses_sudo <file>: true when a non-comment part of <file> calls sudo.
uses_sudo() {
  sed -E 's/(^|[[:space:]])#.*$//' "$1" | grep -Eq '(^|[^[:alnum:]_-])sudo([^[:alnum:]_-]|$)'
}

cd "${ROOT_DIR}"
while IFS= read -r file; do
  ! uses_sudo "${file}" || fail "${file} calls sudo"
done < <(find scripts .github ./*/action.yml -type f 2>/dev/null)

# The check itself must fire, and must not trip over a comment.
printf '#!/bin/sh\n# runs without sudo\nsudo true\n' >"${work}/calls.sh"
uses_sudo "${work}/calls.sh" || fail "a sudo call was not detected"
printf '#!/bin/sh\n# runs without sudo\ntrue\n' >"${work}/mentions.sh"
! uses_sudo "${work}/mentions.sh" || fail "a comment mentioning sudo was reported"

finish no-sudo
