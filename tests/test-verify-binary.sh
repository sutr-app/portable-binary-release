#!/usr/bin/env bash
# Tests for scripts/verify-binary.sh. `file`, `readelf`, `nm`, `otool` and
# `codesign` are replaced by stubs, so every platform branch runs on any host;
# the fixture "binary" is a script that answers --version.
set -euo pipefail

# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
STUB_DIR="${work}/stubs"

mkdir -p "${STUB_DIR}"
cat >"${work}/stubs/file" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "${FAKE_FILE_KIND}"
STUB
cat >"${work}/stubs/readelf" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  -h)
    printf '  Type:                              %s\n' "${FAKE_ELF_TYPE:-DYN (Shared object file)}"
    ;;
  -d)
    for library in ${FAKE_NEEDED}; do
      printf ' 0x0000000000000001 (NEEDED)             Shared library: [%s]\n' "${library}"
    done
    [[ -z "${FAKE_PIE:-}" ]] || printf ' 0x000000006ffffffb (FLAGS_1)            Flags: NOW PIE\n'
    ;;
  -V)
    printf "Version needs section '.gnu.version_r' contains 2 entries:\n"
    for version in ${FAKE_VERSIONS}; do
      printf '  0x0000: Name: %s  Flags: none  Version: 2\n' "${version}"
    done
    ;;
esac
STUB
cat >"${work}/stubs/nm" <<'STUB'
#!/usr/bin/env bash
for symbol in ${FAKE_SYMBOLS}; do
  printf '0000000000001000 T %s\n' "${symbol}"
done
STUB
cat >"${work}/stubs/otool" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  -L) printf '%s:\n%b' "$2" "${FAKE_OTOOL_LIBS}" ;;
  -D) printf '%s:\n' "$2"; [[ -z "${FAKE_OTOOL_ID:-}" ]] || printf '%s\n' "${FAKE_OTOOL_ID}" ;;
  -l)
    printf '    cmd LC_BUILD_VERSION\n  platform 1\n    minos %s\n      sdk 15.0\n' "${FAKE_MINOS}"
    # Real binaries list many load commands after LC_BUILD_VERSION; a reader
    # that stops early must not turn the writer's SIGPIPE into a failure.
    [[ -z "${FAKE_OTOOL_PADDING:-}" ]] || yes '      cmd LC_SEGMENT_64' | head -n 200000
    ;;
esac
STUB
cat >"${work}/stubs/codesign" <<'STUB'
#!/usr/bin/env bash
exit "${FAKE_CODESIGN_STATUS:-0}"
STUB
chmod +x "${work}/stubs/"*

# The expected --version output starts with the file name.
server="${work}/server"
cat >"${server}" <<'FIXTURE'
#!/usr/bin/env bash
[[ "$*" == --version ]] || exit 64
echo "${FAKE_SERVER_NAME:-$(basename "$0")} ${FAKE_SERVER_VERSION:-1.2.3}"
FIXTURE
chmod +x "${server}"
cp "${server}" "${work}/worker"
plugin="${work}/libplugin.so"
: >"${plugin}"

elf_exe='ELF 64-bit LSB pie executable, x86-64, version 1 (SYSV), dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2, for GNU/Linux 4.4.0'
elf_exe_arm='ELF 64-bit LSB pie executable, ARM aarch64, version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux-aarch64.so.1'
elf_static='ELF 64-bit LSB pie executable, x86-64, version 1 (SYSV), static-pie linked, not stripped'
elf_lib='ELF 64-bit LSB shared object, x86-64, version 1 (SYSV), dynamically linked, not stripped'
runtimes='libc.so.6 libm.so.6 libgcc_s.so.1 libstdc++.so.6 ld-linux-*.so.*'
glibc_libs='libstdc++.so.6 libgcc_s.so.1 libm.so.6 libc.so.6 ld-linux-x86-64.so.2'
glibc_versions='GLIBC_2.2.5 GLIBC_2.17 GLIBC_2.39 GLIBCXX_3.4 GLIBCXX_3.4.32 CXXABI_1.3 GCC_3.0'
symbols='load_plugin free_plugin'

linux_server=(VERIFY_PLATFORM=linux-x86_64 VERIFY_KIND=executable VERIFY_MAX_GLIBC=2.39 VERIFY_MAX_GLIBCXX=3.4.33 FAKE_PIE=1
  VERIFY_ALLOWED_DEPS="${runtimes}" VERIFY_EXPECTED_VERSION=1.2.3
  FAKE_FILE_KIND="${elf_exe}" FAKE_NEEDED="${glibc_libs}" FAKE_VERSIONS="${glibc_versions}")
musl_server=(VERIFY_PLATFORM=linux-x86_64 VERIFY_KIND=executable VERIFY_LINKAGE=static VERIFY_EXPECTED_VERSION=1.2.3 FAKE_PIE=1
  FAKE_FILE_KIND="${elf_static}")
linux_plugin=(VERIFY_PLATFORM=linux-x86_64 VERIFY_KIND=shared-library VERIFY_MAX_GLIBC=2.39 VERIFY_MAX_GLIBCXX=3.4.33
  VERIFY_REQUIRED_SYMBOLS="${symbols}" VERIFY_FORBIDDEN_DEPS='libssl* libcrypto*'
  FAKE_FILE_KIND="${elf_lib}" FAKE_NEEDED='libc.so.6 libgcc_s.so.1 libcuda.so.1' FAKE_VERSIONS='GLIBC_2.34'
  FAKE_SYMBOLS="${symbols} other")

system_libs='\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0)\n\t/System/Library/Frameworks/Metal.framework/Versions/A/Metal (compatibility version 1.0.0)\n'
darwin_server=(VERIFY_PLATFORM=darwin-arm64 VERIFY_KIND=executable VERIFY_MACOS_DEPLOYMENT_TARGET=11.0
  VERIFY_ALLOWED_DEPS='/usr/lib/* /System/Library/*' VERIFY_EXPECTED_VERSION=1.2.3
  FAKE_FILE_KIND='Mach-O 64-bit executable arm64' FAKE_OTOOL_LIBS="${system_libs}" FAKE_MINOS=11.0)
dylib_id='@rpath/libplugin.dylib'
darwin_plugin=(VERIFY_PLATFORM=darwin-arm64 VERIFY_KIND=shared-library VERIFY_MACOS_DEPLOYMENT_TARGET=14.0
  VERIFY_REQUIRED_SYMBOLS="${symbols}" VERIFY_ALLOWED_DEPS='/usr/lib/* /System/Library/*'
  FAKE_FILE_KIND='Mach-O 64-bit dynamically linked shared library arm64'
  FAKE_OTOOL_LIBS="\t${dylib_id} (compatibility version 0.0.0)\n${system_libs}" FAKE_OTOOL_ID="${dylib_id}"
  FAKE_MINOS=14.0 FAKE_SYMBOLS="_load_plugin _free_plugin")

# Accepted binaries.
expect_verify 0 "a glibc server within the floor" "${linux_server[@]}" -- "${server}"
expect_verify 0 "several files at once, each reporting its own name" "${linux_server[@]}" -- "${server}" "${work}/worker"
expect_verify 0 "files listed one per line in VERIFY_FILES" "${linux_server[@]}" VERIFY_FILES="${server}"$'\n'"${work}/worker" --
expect_verify 0 "an aarch64 server" "${linux_server[@]}" VERIFY_PLATFORM=linux-aarch64 FAKE_FILE_KIND="${elf_exe_arm}" \
  FAKE_NEEDED='libc.so.6 ld-linux-aarch64.so.1' -- "${server}"
expect_verify 0 "glibc versions compared numerically (2.9 < 2.39)" "${linux_server[@]}" FAKE_VERSIONS='GLIBC_2.9 GLIBC_2.34' -- "${server}"
expect_verify 0 "a C library without GLIBCXX" "${linux_server[@]}" FAKE_VERSIONS='GLIBC_2.34' -- "${server}"
expect_verify 0 "a static musl server" "${musl_server[@]}" -- "${server}"
expect_verify 0 "a non-PIE executable" "${linux_server[@]}" FAKE_PIE= FAKE_ELF_TYPE='EXEC (Executable file)' -- "${server}"
# Older `file` releases describe a PIE executable as a shared object; the
# ELF header and the PIE flag decide.
expect_verify 0 "a PIE executable that file calls a shared object" "${linux_server[@]}" FAKE_FILE_KIND="${elf_lib}" -- "${server}"
# A file name without a directory must run from the working directory, not
# be looked up on PATH.
cd "${work}"
expect_verify 0 "a relative file name" "${linux_server[@]}" -- server
cd - >/dev/null
expect_verify 0 "a plugin with its symbols and allowed dependencies" "${linux_plugin[@]}" -- "${plugin}"
expect_verify 0 "a plugin with a required dependency" "${linux_plugin[@]}" VERIFY_REQUIRED_DEPS=libcuda.so.1 -- "${plugin}"
# nm -D prints the version of a versioned export after "@@".
expect_verify 0 "exports carrying a symbol version" "${linux_plugin[@]}" FAKE_SYMBOLS='load_plugin@@PLUGIN_1 free_plugin@@PLUGIN_1' -- "${plugin}"
# A library may call nothing versioned in libc directly (only libstdc++, say).
expect_verify 0 "a library with no glibc version requirement" "${linux_plugin[@]}" FAKE_VERSIONS='GLIBCXX_3.4' -- "${plugin}"
expect_verify 0 "a macOS server linking only system libraries" "${darwin_server[@]}" -- "${server}"
expect_verify 0 "load commands listed long after minos" "${darwin_server[@]}" FAKE_OTOOL_PADDING=1 -- "${server}"
expect_verify 0 "a macOS plugin, its own install name is not a dependency" "${darwin_plugin[@]}" -- "${plugin}"
expect_verify 0 "an unsigned binary when signing is not checked" "${darwin_server[@]}" FAKE_CODESIGN_STATUS=1 VERIFY_CODESIGN=false -- "${server}"

# Linux rejections.
expect_verify 1 "an aarch64 binary for linux-x86_64" "${linux_server[@]}" FAKE_FILE_KIND="${elf_exe_arm}" -- "${server}"
expect_verify 1 "a shared object where an executable is expected" "${linux_server[@]}" FAKE_PIE= -- "${server}"
expect_verify 1 "an executable where a shared library is expected" "${linux_plugin[@]}" FAKE_PIE=1 -- "${plugin}"
expect_verify 1 "a non-PIE executable where a shared library is expected" "${linux_plugin[@]}" FAKE_ELF_TYPE='EXEC (Executable file)' -- "${plugin}"
expect_verify 1 "a static binary where dynamic linking is required" "${linux_server[@]}" FAKE_FILE_KIND="${elf_static}" -- "${server}"
expect_verify 1 "a dynamic binary where static linking is required" "${musl_server[@]}" FAKE_FILE_KIND="${elf_exe}" -- "${server}"
expect_verify 1 "a dependency outside the allowed list" "${linux_server[@]}" FAKE_NEEDED="${glibc_libs} libz.so.1" -- "${server}"
expect_verify 1 "a forbidden dependency" "${linux_plugin[@]}" FAKE_NEEDED='libc.so.6 libssl.so.3' -- "${plugin}"
expect_verify 1 "Rust std as a shared library, always forbidden" "${linux_plugin[@]}" FAKE_NEEDED='libc.so.6 libstd-0123abcd.so' -- "${plugin}"
expect_verify 1 "a missing required dependency" "${linux_plugin[@]}" VERIFY_REQUIRED_DEPS=libcudart.so.12 -- "${plugin}"
expect_verify 1 "glibc newer than the floor" "${linux_server[@]}" FAKE_VERSIONS='GLIBC_2.17 GLIBC_2.40' -- "${server}"
expect_verify 1 "libstdc++ newer than the floor" "${linux_server[@]}" FAKE_VERSIONS='GLIBC_2.39 GLIBCXX_3.4.34' -- "${server}"
expect_verify 1 "an executable with no glibc version requirement at all" "${linux_server[@]}" FAKE_VERSIONS='GCC_3.0' -- "${server}"
expect_verify 1 "a missing exported symbol" "${linux_plugin[@]}" FAKE_SYMBOLS='load_plugin other' -- "${plugin}"
expect_verify 1 "another version" "${linux_server[@]}" FAKE_SERVER_VERSION=1.2.4 -- "${server}"
expect_verify 1 "another program's name" "${linux_server[@]}" FAKE_SERVER_NAME=worker -- "${server}"

# macOS rejections.
expect_verify 1 "a non-system dependency" "${darwin_server[@]}" \
  FAKE_OTOOL_LIBS="${system_libs}"'\t/opt/homebrew/lib/libsqlite3.dylib (compatibility version 9.0.0)\n' -- "${server}"
expect_verify 1 "a forbidden dependency on macOS" "${darwin_plugin[@]}" VERIFY_ALLOWED_DEPS= VERIFY_FORBIDDEN_DEPS='libssl*' \
  FAKE_OTOOL_LIBS="${system_libs}"'\t@rpath/libssl.3.dylib (compatibility version 3.0.0)\n' -- "${plugin}"
expect_verify 1 "minos above the deployment target" "${darwin_server[@]}" FAKE_MINOS=14.0 -- "${server}"
expect_verify 1 "no minos" "${darwin_server[@]}" FAKE_MINOS= -- "${server}"
expect_verify 1 "an invalid code signature" "${darwin_server[@]}" FAKE_CODESIGN_STATUS=1 -- "${server}"
expect_verify 1 "an x86_64 Mach-O" "${darwin_server[@]}" FAKE_FILE_KIND='Mach-O 64-bit executable x86_64' -- "${server}"
expect_verify 1 "a missing exported symbol on macOS" "${darwin_plugin[@]}" FAKE_SYMBOLS='_load_plugin' -- "${plugin}"

# Usage errors.
expect_verify 2 "no files" "${linux_server[@]}" --
expect_verify 2 "a missing file" "${linux_server[@]}" -- "${work}/missing"
expect_verify 2 "no kind" "${linux_server[@]}" VERIFY_KIND= -- "${server}"
expect_verify 2 "an unknown kind" "${linux_server[@]}" VERIFY_KIND=archive -- "${server}"
expect_verify 2 "an unknown linkage" "${linux_server[@]}" VERIFY_LINKAGE=mixed -- "${server}"
expect_verify 2 "an unknown platform" "${linux_server[@]}" VERIFY_PLATFORM=windows-x86_64 -- "${server}"
expect_verify 2 "dynamic Linux without max-glibc" "${linux_server[@]}" VERIFY_MAX_GLIBC= -- "${server}"
expect_verify 2 "macOS without a deployment target" "${darwin_server[@]}" VERIFY_MACOS_DEPLOYMENT_TARGET= -- "${server}"
expect_verify 2 "an expected version for a shared library" "${linux_plugin[@]}" VERIFY_EXPECTED_VERSION=1.2.3 -- "${plugin}"
chmod -x "${work}/worker"
expect_verify 2 "an expected version for a file that is not executable" "${linux_server[@]}" -- "${work}/worker"

finish verify-binary
