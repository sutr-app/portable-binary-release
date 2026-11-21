#!/usr/bin/env bash
# Tests for scripts/verify-binary.sh against binaries compiled here with the
# host's real tools, so each CI platform checks what the stubbed tests can
# only imitate. Skipped when no C compiler is installed.
set -euo pipefail

# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPTS_DIR}/lib/common.sh"

if ! command -v cc >/dev/null; then
  echo "SKIP: verify-binary-native (no C compiler)"
  exit 0
fi

platform=$(host_platform)
case "${platform}" in
  linux-*) ext=so cflags=() system_deps='libc.so.6 ld-linux-*' ssl=libssl.so.3 ;;
  darwin-arm64) ext=dylib cflags=(-mmacosx-version-min=14.0) system_deps='/usr/lib/*' ssl=libssl.3.dylib ;;
  *) echo "SKIP: verify-binary-native (unsupported host ${platform})"; exit 0 ;;
esac

cat >"${work}/plugin.c" <<'SRC'
#include <stdio.h>
void *load_plugin(void) { puts("load"); return 0; }
void free_plugin(void *p) { (void)p; }
SRC
cat >"${work}/partial.c" <<'SRC'
void *load_plugin(void) { return 0; }
SRC
echo 'void stub(void) {}' >"${work}/stub.c"
echo 'not a binary' >"${work}/not-a-lib.${ext}"

cc -shared -fPIC "${cflags[@]}" -o "${work}/libplugin.${ext}" "${work}/plugin.c"
cc -shared -fPIC "${cflags[@]}" -o "${work}/libpartial.${ext}" "${work}/partial.c"
mkdir -p "${work}/bin" "${work}/old"
cc "${cflags[@]}" -DVERSION='"1.2.3"' -o "${work}/bin/server" "${TESTS_DIR}/fixtures/server.c"
cc "${cflags[@]}" -DVERSION='"1.2.2"' -o "${work}/old/server" "${TESTS_DIR}/fixtures/server.c"

# with_dep <dependency-name> <out>: the plugin linked against a stand-in
# library named like <dependency-name>, which stays a dynamic dependency.
with_dep() {
  local name=$1 out=$2
  if [[ "${ext}" == so ]]; then
    cc -shared -fPIC -Wl,-soname,"${name}" -o "${work}/${name}" "${work}/stub.c"
    cc -shared -fPIC -o "${work}/${out}" "${work}/plugin.c" -Wl,--no-as-needed "${work}/${name}" -Wl,--as-needed
  else
    cc -dynamiclib "${cflags[@]}" -install_name "@rpath/${name}" -o "${work}/${name}" "${work}/stub.c"
    cc -shared -fPIC "${cflags[@]}" -o "${work}/${out}" "${work}/plugin.c" "${work}/${name}"
  fi
}

with_dep "${ssl}" "libwith-ssl.${ext}"
with_dep libstd-0123456789abcdef."${ext}" "libwith-rust-std.${ext}"

# Limits loose enough for the fixtures; individual cases tighten one of them.
base=(VERIFY_PLATFORM="${platform}" VERIFY_MAX_GLIBC=99.0 VERIFY_MAX_GLIBCXX=99.0 VERIFY_MACOS_DEPLOYMENT_TARGET=14.0)
plugin=("${base[@]}" VERIFY_KIND=shared-library VERIFY_REQUIRED_SYMBOLS='load_plugin free_plugin')
server=("${base[@]}" VERIFY_KIND=executable VERIFY_EXPECTED_VERSION=1.2.3)

expect_verify 0 "a plugin exporting its symbols and linking only system libraries" \
  "${plugin[@]}" VERIFY_ALLOWED_DEPS="${system_deps}" -- "${work}/libplugin.${ext}"
expect_verify 1 "a plugin missing free_plugin" "${plugin[@]}" -- "${work}/libpartial.${ext}"
expect_verify 1 "a file that is not a binary" "${plugin[@]}" -- "${work}/not-a-lib.${ext}"
expect_verify 1 "a forbidden dependency" \
  "${plugin[@]}" VERIFY_FORBIDDEN_DEPS='libssl*' -- "${work}/libwith-ssl.${ext}"
expect_verify 1 "a dependency outside the allowed list" \
  "${plugin[@]}" VERIFY_ALLOWED_DEPS="${system_deps}" -- "${work}/libwith-ssl.${ext}"
expect_verify 1 "Rust std as a shared library" "${plugin[@]}" -- "${work}/libwith-rust-std.${ext}"
expect_verify 0 "a required dependency present" \
  "${plugin[@]}" VERIFY_REQUIRED_DEPS="${ssl}" -- "${work}/libwith-ssl.${ext}"
expect_verify 1 "a required dependency missing" \
  "${plugin[@]}" VERIFY_REQUIRED_DEPS="${ssl}" -- "${work}/libplugin.${ext}"
expect_verify 0 "an executable reporting the release version" "${server[@]}" -- "${work}/bin/server"
expect_verify 1 "an executable reporting another version" "${server[@]}" -- "${work}/old/server"
expect_verify 1 "a shared library checked as an executable" \
  "${base[@]}" VERIFY_KIND=executable -- "${work}/libplugin.${ext}"

if [[ "${ext}" == so ]]; then
  # puts() pulls in a versioned GLIBC_2.x symbol, so 2.0 is always exceeded.
  expect_verify 1 "a glibc requirement above the floor" \
    "${plugin[@]}" VERIFY_MAX_GLIBC=2.0 -- "${work}/libplugin.so"
  if command -v c++ >/dev/null; then
    printf '#include <iostream>\nextern "C" void *load_plugin() { std::cout << "load"; return nullptr; }\nextern "C" void free_plugin(void *) {}\n' \
      >"${work}/cxxplugin.cpp"
    c++ -shared -fPIC -o "${work}/libcxxplugin.so" "${work}/cxxplugin.cpp"
    expect_verify 0 "a C++ plugin within the libstdc++ floor" "${plugin[@]}" -- "${work}/libcxxplugin.so"
    expect_verify 1 "a libstdc++ requirement above the floor" \
      "${plugin[@]}" VERIFY_MAX_GLIBCXX=3.3 -- "${work}/libcxxplugin.so"
  else
    echo "SKIP: libstdc++ cases (no C++ compiler)"
  fi
else
  cc -shared -fPIC -mmacosx-version-min=15.0 -o "${work}/libnewer.dylib" "${work}/plugin.c"
  expect_verify 1 "a minimum macOS above the deployment target" "${plugin[@]}" -- "${work}/libnewer.dylib"
  cp "${work}/libplugin.dylib" "${work}/libbroken.dylib"
  # Flip bytes inside __TEXT so the ad-hoc signature no longer matches.
  printf '\xff\xff\xff\xff' | dd of="${work}/libbroken.dylib" bs=1 seek=4096 conv=notrunc 2>/dev/null
  expect_verify 1 "a broken code signature" "${plugin[@]}" -- "${work}/libbroken.dylib"
fi

finish verify-binary-native
