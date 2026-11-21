#!/usr/bin/env bash
# Tests for scripts/install-cargo-about.sh. The offline cases serve fake
# archives from file:// URLs; set CARGO_ABOUT_TEST_ONLINE=1 to also install
# the real pinned release.
set -euo pipefail

# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=scripts/lib/fetch-pinned.sh
source "${SCRIPTS_DIR}/lib/fetch-pinned.sh"
# shellcheck source=scripts/pins/cargo-about.sh
source "${SCRIPTS_DIR}/pins/cargo-about.sh"
install="${SCRIPTS_DIR}/install-cargo-about.sh"
version=${CARGO_ABOUT_VERSION}
# Only the cases that check the hand-over write to these.
export GITHUB_ENV='' GITHUB_OUTPUT=''

# make_archive <target> <reported-version>: a release archive for <target>
# whose binary reports <reported-version>; prints its path.
make_archive() {
  local stage="cargo-about-${version}-$1"
  rm -rf "${work}/fake"
  mkdir -p "${work}/fake/${stage}"
  printf '#!/bin/sh\necho "cargo-about %s"\n' "$2" >"${work}/fake/${stage}/cargo-about"
  chmod +x "${work}/fake/${stage}/cargo-about"
  tar -C "${work}/fake" -czf "${work}/${stage}.tar.gz" "${stage}"
  echo "${work}/${stage}.tar.gz"
}

# copy_pinned_to <archive>: a copy of the scripts whose pin table pins
# <archive> as the linux-x86_64 release served from ${work}; prints the copied
# installer.
copy_pinned_to() {
  local copy
  copy="${work}/scripts-$(sha256_of "$1")"
  rm -rf "${copy}"
  cp -R "${SCRIPTS_DIR}" "${copy}"
  cat >"${copy}/pins/cargo-about.sh" <<PINS
CARGO_ABOUT_VERSION=${version}
CARGO_ABOUT_RELEASE_URL=file://${work}
cargo_about_release() {
  cargo_about_target=x86_64-unknown-linux-musl
  cargo_about_sha256=$(sha256_of "$1")
}
PINS
  echo "${copy}/install-cargo-about.sh"
}

# Every supported platform has its own pin: a fake archive under that
# platform's asset name must fail the real checksum before anything is
# extracted.
for pinned in linux-x86_64:x86_64-unknown-linux-musl linux-aarch64:aarch64-unknown-linux-musl; do
  platform=${pinned%%:*}
  archive=$(make_archive "${pinned#*:}" "${version}")
  expect_status 1 "a tampered ${platform} archive" \
    env CARGO_ABOUT_PLATFORM="${platform}" CARGO_ABOUT_BASE_URL="file://${work}" bash "${install}" "${work}/out-${platform}"
  grep -Fq "checksum mismatch for $(basename "${archive}")" "${work}/out" \
    || fail "${platform} did not select $(basename "${archive}"): $(cat "${work}/out")"
  [[ ! -e "${work}/out-${platform}/cargo-about" ]] || fail "a tampered ${platform} archive was extracted"
done

pinned_install=$(copy_pinned_to "$(make_archive x86_64-unknown-linux-musl "${version}")")
: >"${work}/github_env"
: >"${work}/github_output"
expect_status 0 "a verified archive" \
  env GITHUB_ENV="${work}/github_env" GITHUB_OUTPUT="${work}/github_output" CARGO_ABOUT_PLATFORM=linux-x86_64 \
  bash "${pinned_install}" "${work}/out-ok"
[[ -x "${work}/out-ok/cargo-about" ]] || fail "cargo-about was not installed"
grep -Fxq "CARGO_ABOUT=${work}/out-ok/cargo-about" "${work}/github_env" || fail "CARGO_ABOUT was not exported to GITHUB_ENV"
grep -Fxq "path=${work}/out-ok/cargo-about" "${work}/github_output" || fail "the path output was not written"
grep -Fxq "version=${version}" "${work}/github_output" || fail "the version output was not written"

mkdir -p "${work}/runner-temp"
expect_status 0 "the default destination" \
  env RUNNER_TEMP="${work}/runner-temp" CARGO_ABOUT_PLATFORM=linux-x86_64 bash "${pinned_install}"
[[ -x "${work}/runner-temp/cargo-about/cargo-about" ]] || fail "the default destination is not RUNNER_TEMP/cargo-about"

expect_status 1 "a binary reporting another version" \
  env CARGO_ABOUT_PLATFORM=linux-x86_64 \
  bash "$(copy_pinned_to "$(make_archive x86_64-unknown-linux-musl 0.1.0)")" "${work}/out-wrong"

expect_status 1 "a failed download" \
  env CARGO_ABOUT_PLATFORM=linux-x86_64 CARGO_ABOUT_BASE_URL="file://${work}/missing" bash "${install}" "${work}/out-missing"
# The license listing is generated on Linux; the musl builds run on any
# distribution.
expect_status 2 "macOS, which has no pinned release" \
  env CARGO_ABOUT_PLATFORM=darwin-arm64 bash "${install}" "${work}/out-darwin"
expect_status 2 "neither a destination nor RUNNER_TEMP" \
  env -u RUNNER_TEMP CARGO_ABOUT_PLATFORM=linux-x86_64 bash "${install}"

if [[ "${CARGO_ABOUT_TEST_ONLINE:-0}" == 1 ]]; then
  expect_status 0 "installing the pinned release" bash "${install}" "${work}/out-real"
  [[ "$("${work}/out-real/cargo-about" --version 2>/dev/null)" == "cargo-about ${version}" ]] \
    || fail "installed cargo-about is not version ${version}"
else
  echo "SKIP: online install (set CARGO_ABOUT_TEST_ONLINE=1)"
fi

finish install-cargo-about
