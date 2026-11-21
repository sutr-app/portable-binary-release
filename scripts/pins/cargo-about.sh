# shellcheck shell=bash disable=SC2034 # the variables are read by install-cargo-about.sh
# The cargo-about release install-cargo-about.sh installs. Only Linux is
# pinned: a license listing does not depend on the platform it is generated
# on, and the musl builds run on any Linux distribution.
#
# Kept compatible with the bash 3.2 shipped with macOS.

# Update together with every SHA-256 below.
CARGO_ABOUT_VERSION=0.9.3
CARGO_ABOUT_RELEASE_URL=https://github.com/EmbarkStudios/cargo-about/releases/download/${CARGO_ABOUT_VERSION}

# cargo_about_release <platform>: sets cargo_about_target and
# cargo_about_sha256 for an <os>-<arch> platform; fails for an unpinned one.
cargo_about_release() {
  case "$1" in
    linux-x86_64)
      cargo_about_target=x86_64-unknown-linux-musl
      cargo_about_sha256=3ad1e94ea1e63d69d1961f4fb15ccbbe9575d906111f96d2cb4dce6df48f71b4
      ;;
    linux-aarch64)
      cargo_about_target=aarch64-unknown-linux-musl
      cargo_about_sha256=eb4d9ff6ebd2518152a8308729431a04b3836e71d2bd5ead7aea69f91a71162e
      ;;
    *)
      return 1
      ;;
  esac
}
