#!/usr/bin/env bash
# Usage: verify-binary.sh [file...]
#
# Checks built binaries before they are published, on the runner that built
# them, for what makes a release unusable on the user's machine: file format
# and architecture, linkage, dynamic dependencies, the newest glibc /
# libstdc++ / macOS required, exported entry points, the macOS code signature
# and the reported version. It never loads a shared library (no `ldd`).
#
# The settings are the verify-binary action's inputs (see README.md), passed
# as VERIFY_<INPUT> with the name upper-cased and dashes as underscores, e.g.
# max-glibc as VERIFY_MAX_GLIBC. Files come from the arguments, or one per
# line from VERIFY_FILES. VERIFY_PLATFORM overrides the detected <os>-<arch>,
# for tests: the version and signature checks only work on the platform the
# binary was built for.
#
# Exit status: 1 when a binary fails a check, 2 on usage errors.
# Kept compatible with the bash 3.2 shipped with macOS.
set -euo pipefail
# The settings hold globs and word lists that are split on purpose; nothing
# here relies on pathname expansion.
set -f

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

kind=${VERIFY_KIND-}
platform=${VERIFY_PLATFORM:-$(host_platform)}
linkage=${VERIFY_LINKAGE:-dynamic}
max_glibc=${VERIFY_MAX_GLIBC-}
max_glibcxx=${VERIFY_MAX_GLIBCXX-}
macos_target=${VERIFY_MACOS_DEPLOYMENT_TARGET-}
required_symbols=${VERIFY_REQUIRED_SYMBOLS-}
# A Rust std built as a shared library only loads next to the exact toolchain
# that built it, which no user has.
forbidden_deps="libstd-* ${VERIFY_FORBIDDEN_DEPS-}"
allowed_deps=${VERIFY_ALLOWED_DEPS-}
required_deps=${VERIFY_REQUIRED_DEPS-}
expected_version=${VERIFY_EXPECTED_VERSION-}
codesign_check=${VERIFY_CODESIGN:-true}

# True when dotted version $1 is greater than $2. Compared field by field in
# awk because `sort -V` is not available on every macOS release.
version_gt() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    na = split(a, x, "."); nb = split(b, y, "."); n = (na > nb) ? na : nb
    for (i = 1; i <= n; i++) {
      if ((x[i] + 0) > (y[i] + 0)) exit 0
      if ((x[i] + 0) < (y[i] + 0)) exit 1
    }
    exit 1
  }'
}

# max_version <prefix> <versions>: the highest <prefix>_x.y.z among <versions>.
max_version() {
  local prefix=$1 versions=$2 max='' version
  for version in ${versions}; do
    [[ "${version}" == "${prefix}"_[0-9]* ]] || continue
    version=${version#"${prefix}"_}
    if [[ -z "${max}" ]] || version_gt "${version}" "${max}"; then
      max=${version}
    fi
  done
  echo "${max}"
}

# matches_glob <word> <globs>: true when <word> matches one of the
# space-separated <globs>.
matches_glob() {
  local glob
  for glob in $2; do
    # shellcheck disable=SC2053
    [[ "$1" == ${glob} ]] && return 0
  done
  return 1
}

# check_deps <file> <dependency...>: the forbidden, allowed and required
# dependency rules, shared by ELF and Mach-O.
check_deps() {
  local file=$1 dep required
  shift
  echo "dynamic dependencies:"
  for dep in "$@"; do
    echo "  ${dep}"
    ! matches_glob "${dep##*/}" "${forbidden_deps}" || die "${file}: forbidden dynamic dependency: ${dep}"
    [[ -z "${allowed_deps}" ]] || matches_glob "${dep}" "${allowed_deps}" \
      || die "${file}: dynamic dependency outside allowed-deps: ${dep}"
  done
  for required in ${required_deps}; do
    for dep in "$@"; do
      [[ "${dep##*/}" == "${required}" ]] && continue 2
    done
    die "${file}: missing required dynamic dependency: ${required}"
  done
}

# check_symbols <file> <prefix> <exported>: every required symbol is among
# <exported>, one per line, each carrying <prefix>.
check_symbols() {
  local file=$1 prefix=$2 exported=$3 symbol
  for symbol in ${required_symbols}; do
    grep -qxF -- "${prefix}${symbol}" <<<"${exported}" || die "${file}: missing exported symbol: ${symbol}"
    echo "exported: ${symbol}"
  done
}

check_elf() {
  local file=$1 description=$2 elf_type dynamic elf_kind needed versions glibc glibcxx
  [[ "${description}" == *"ELF 64-bit LSB"*"${elf_arch}"* ]] || die "${file}: not a ${elf_arch} ELF file"
  # The ELF header and the PIE flag tell executables from libraries; `file`
  # cannot always, as older releases call a PIE executable a shared object.
  elf_type=$(LC_ALL=C readelf -h "${file}" | awk '$1 == "Type:" { print $2 }')
  dynamic=$(LC_ALL=C readelf -d "${file}")
  case "${elf_type}" in
    EXEC) elf_kind=executable ;;
    DYN) grep -Eq '\(FLAGS_1\).*[[:space:]]PIE([[:space:]]|$)' <<<"${dynamic}" && elf_kind=executable || elf_kind=shared-library ;;
    *) elf_kind=other ;;
  esac
  [[ "${elf_kind}" == "${kind}" ]] || die "${file}: not an ELF ${kind} (found: ${elf_kind})"
  if [[ "${linkage}" == static ]]; then
    [[ "${description}" == *"statically linked"* || "${description}" == *"static-pie linked"* ]] \
      || die "${file}: not statically linked"
  else
    [[ "${description}" == *"dynamically linked"* ]] || die "${file}: not dynamically linked"
    needed=$(sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p' <<<"${dynamic}")
    # shellcheck disable=SC2086 # one soname per word
    check_deps "${file}" ${needed}
    # Every imported symbol repeats its version; compare each version once.
    versions=$(LC_ALL=C readelf -V "${file}" | { grep -oE '(GLIBC|GLIBCXX)_[0-9][0-9.]*' || true; } | sort -u)
    glibc=$(max_version GLIBC "${versions}")
    glibcxx=$(max_version GLIBCXX "${versions}")
    echo "requires glibc ${glibc:-unknown}, libstdc++ ${glibcxx:-none}"
    # An executable always calls into libc, so requiring no version at all
    # means the file is not the program that will run (a wrapper or a stub,
    # say). A library may only call libstdc++ directly.
    [[ -n "${glibc}" || "${kind}" == shared-library ]] || die "${file}: no GLIBC symbol version found"
    ! version_gt "${glibc}" "${max_glibc}" || die "${file}: requires glibc ${glibc}, above max-glibc ${max_glibc}"
    [[ -z "${max_glibcxx}" ]] || ! version_gt "${glibcxx}" "${max_glibcxx}" \
      || die "${file}: requires libstdc++ GLIBCXX_${glibcxx}, above max-glibcxx ${max_glibcxx}"
  fi
  # A versioned export is listed as name@@VERSION; the version is not part of
  # the name a loader asks for.
  [[ -z "${required_symbols}" ]] \
    || check_symbols "${file}" '' "$(nm -D --defined-only "${file}" | awk '{ sub(/@.*/, "", $NF); print $NF }')"
}

check_macho() {
  local file=$1 description=$2 self deps load_commands minos
  case "${kind}" in
    shared-library) [[ "${description}" == *"Mach-O 64-bit dynamically linked shared library arm64"* ]] \
      || die "${file}: not an arm64 Mach-O dylib" ;;
    executable) [[ "${description}" == *"Mach-O 64-bit executable arm64"* ]] \
      || die "${file}: not an arm64 Mach-O executable" ;;
  esac
  # A dylib lists its own install name first; it is not a dependency.
  self=$(otool -D "${file}" | tail -n +2)
  deps=$(otool -L "${file}" | tail -n +2 | awk '{ print $1 }' | { grep -vxF -- "${self:-/}" || true; })
  # shellcheck disable=SC2086 # install names contain no whitespace
  check_deps "${file}" ${deps}
  # Captured and fed without a pipe: an awk exiting at the first match would
  # SIGPIPE the writer, which pipefail turns into a silent failure.
  load_commands=$(otool -l "${file}")
  minos=$(awk '$1 == "minos" { print $2; exit }' <<<"${load_commands}")
  echo "minimum macOS: ${minos:-unknown}"
  [[ -n "${minos}" ]] || die "${file}: no LC_BUILD_VERSION minos found"
  ! version_gt "${minos}" "${macos_target}" \
    || die "${file}: requires macOS ${minos}, above macos-deployment-target ${macos_target}"
  if [[ "${codesign_check}" != false ]]; then
    codesign -v --verbose=2 "${file}" || die "${file}: code signature is invalid"
  fi
  [[ -z "${required_symbols}" ]] || check_symbols "${file}" _ "$(nm -gU "${file}" | awk '{ print $NF }')"
}

files=("$@")
if [[ "${#files[@]}" -eq 0 && -n "${VERIFY_FILES-}" ]]; then
  while IFS= read -r line; do
    [[ -z "${line}" ]] || files+=("${line}")
  done <<<"${VERIFY_FILES}"
fi
[[ "${#files[@]}" -gt 0 ]] || usage_error "no files to check: set files (VERIFY_FILES) or pass them as arguments"
case "${kind}" in
  shared-library | executable) ;;
  *) usage_error "kind (VERIFY_KIND) must be shared-library or executable: '${kind}'" ;;
esac
case "${linkage}" in
  dynamic | static) ;;
  *) usage_error "linkage (VERIFY_LINKAGE) must be dynamic or static: '${linkage}'" ;;
esac
elf_arch=
case "${platform}" in
  linux-x86_64) elf_arch=x86-64 ;;
  linux-aarch64) elf_arch="ARM aarch64" ;;
  darwin-arm64)
    [[ -n "${macos_target}" ]] \
      || usage_error "macos-deployment-target (VERIFY_MACOS_DEPLOYMENT_TARGET) must be set on ${platform}"
    ;;
  *) usage_error "unsupported platform: ${platform}" ;;
esac
[[ -z "${elf_arch}" || "${linkage}" == static || -n "${max_glibc}" ]] \
  || usage_error "max-glibc (VERIFY_MAX_GLIBC) must be set for a dynamically linked ${platform} binary"
[[ -z "${expected_version}" || "${kind}" == executable ]] \
  || usage_error "expected-version (VERIFY_EXPECTED_VERSION) applies to executables only"

for file in "${files[@]}"; do
  [[ -f "${file}" ]] || usage_error "no such file: ${file}"
  [[ -z "${expected_version}" || -x "${file}" ]] || usage_error "not executable: ${file}"
  description=$(file -b "${file}")
  echo "${file}: ${description}"
  if [[ -n "${elf_arch}" ]]; then
    check_elf "${file}" "${description}"
  else
    check_macho "${file}" "${description}"
  fi
  # A bare file name would be looked up on PATH instead of run from here.
  if [[ -n "${expected_version}" ]]; then
    [[ "${file}" == */* ]] && run=${file} || run=./${file}
    expect_version_output "${run}" "$(basename "${file}") ${expected_version}"
  fi
  echo "OK: ${file} (${platform})"
done
