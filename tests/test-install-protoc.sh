#!/usr/bin/env bash
# Tests for scripts/install-protoc.sh. The offline cases serve fake archives
# from file:// URLs; set PROTOC_TEST_ONLINE=1 to also install the real pinned
# release.
set -euo pipefail

# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=scripts/lib/fetch-pinned.sh
source "${SCRIPTS_DIR}/lib/fetch-pinned.sh"
# shellcheck source=scripts/pins/protoc.sh
source "${SCRIPTS_DIR}/pins/protoc.sh"
install="${SCRIPTS_DIR}/install-protoc.sh"
version=${PROTOC_VERSION}
# Only the cases that check the hand-over write to these.
export GITHUB_ENV='' GITHUB_OUTPUT=''

# make_archive <reported-version> <zip>: a protoc release archive whose
# binary reports <reported-version>, so the cases run offline on any host.
make_archive() {
  rm -rf "${work}/fake"
  mkdir -p "${work}/fake/bin"
  printf '#!/bin/sh\necho "libprotoc %s"\n' "$1" >"${work}/fake/bin/protoc"
  chmod +x "${work}/fake/bin/protoc"
  (cd "${work}/fake" && zip -q -r "$2" bin)
}

# copy_pinned_to <zip>: a copy of the scripts whose pin table pins <zip> as the
# linux-x86_64 release served from ${work}; prints the copied installer.
copy_pinned_to() {
  local copy
  copy="${work}/scripts-$(sha256_of "$1")"
  rm -rf "${copy}"
  cp -R "${SCRIPTS_DIR}" "${copy}"
  cp "$1" "${work}/protoc-${version}-linux-x86_64.zip"
  cat >"${copy}/pins/protoc.sh" <<PINS
PROTOC_VERSION=${version}
PROTOC_RELEASE_URL=file://${work}
protoc_release() {
  protoc_asset=protoc-${version}-linux-x86_64.zip
  protoc_sha256=$(sha256_of "$1")
}
PINS
  echo "${copy}/install-protoc.sh"
}

make_archive "${version}" "${work}/fake.zip"

# Every supported platform has its own pin: the fake archive under that
# platform's asset name must fail the real checksum before anything is
# extracted.
for pinned in linux-x86_64:linux-x86_64 linux-aarch64:linux-aarch_64 darwin-arm64:osx-aarch_64; do
  platform=${pinned%%:*}
  asset=protoc-${version}-${pinned#*:}.zip
  cp "${work}/fake.zip" "${work}/${asset}"
  expect_status 1 "a tampered ${platform} archive" \
    env PROTOC_PLATFORM="${platform}" PROTOC_BASE_URL="file://${work}" bash "${install}" "${work}/out-${platform}"
  grep -Fq "checksum mismatch for ${asset}" "${work}/out" || fail "${platform} did not select ${asset}: $(cat "${work}/out")"
  [[ ! -e "${work}/out-${platform}/bin/protoc" ]] || fail "a tampered ${platform} archive was extracted"
done

pinned_install=$(copy_pinned_to "${work}/fake.zip")
: >"${work}/github_env"
: >"${work}/github_output"
expect_status 0 "a verified archive" \
  env GITHUB_ENV="${work}/github_env" GITHUB_OUTPUT="${work}/github_output" PROTOC_PLATFORM=linux-x86_64 \
  bash "${pinned_install}" "${work}/out-ok"
[[ -x "${work}/out-ok/bin/protoc" ]] || fail "protoc was not extracted"
grep -Fxq "PROTOC=${work}/out-ok/bin/protoc" "${work}/github_env" || fail "PROTOC was not exported to GITHUB_ENV"
grep -Fxq "path=${work}/out-ok/bin/protoc" "${work}/github_output" || fail "the path output was not written"
grep -Fxq "version=${version}" "${work}/github_output" || fail "the version output was not written"

# Without a destination it installs under RUNNER_TEMP, as in a workflow.
mkdir -p "${work}/runner-temp"
expect_status 0 "the default destination" \
  env RUNNER_TEMP="${work}/runner-temp" PROTOC_PLATFORM=linux-x86_64 bash "${pinned_install}"
[[ -x "${work}/runner-temp/protoc/bin/protoc" ]] || fail "the default destination is not RUNNER_TEMP/protoc"

# The installed binary must report the pinned version.
make_archive 1.0 "${work}/wrong.zip"
expect_status 1 "a binary reporting another version" \
  env PROTOC_PLATFORM=linux-x86_64 bash "$(copy_pinned_to "${work}/wrong.zip")" "${work}/out-wrong"

expect_status 1 "a failed download" \
  env PROTOC_PLATFORM=linux-x86_64 PROTOC_BASE_URL="file://${work}/missing" bash "${install}" "${work}/out-missing"
expect_status 2 "an unsupported platform" \
  env PROTOC_PLATFORM=windows-x86_64 bash "${install}" "${work}/out-win"
expect_status 2 "neither a destination nor RUNNER_TEMP" \
  env -u RUNNER_TEMP PROTOC_PLATFORM=linux-x86_64 bash "${install}"

if [[ "${PROTOC_TEST_ONLINE:-0}" == 1 ]]; then
  expect_status 0 "installing the pinned release" bash "${install}" "${work}/out-real"
  [[ "$("${work}/out-real/bin/protoc" --version 2>/dev/null)" == "libprotoc ${version}" ]] \
    || fail "installed protoc is not version ${version}"
else
  echo "SKIP: online install (set PROTOC_TEST_ONLINE=1)"
fi

finish install-protoc
