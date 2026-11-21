# portable-binary-release

[日本語版はこちら](README.ja.md)

Composite GitHub Actions for releasing native binaries that run on the
platforms you promise to support:

- install build tools at a pinned version, verified by SHA-256, with no root
  privileges, so shared self-hosted runners can use them
- check a built binary before it is published: file format and architecture,
  the newest glibc / libstdc++ / macOS it requires, its dynamic dependencies,
  exported symbols, code signature and reported version

| Action | What it does |
|---|---|
| [`install-protoc`](#install-protoc) | Installs the pinned `protoc` and exports `PROTOC` |
| [`install-cargo-about`](#install-cargo-about) | Installs the pinned `cargo-about` and exports `CARGO_ABOUT` |
| [`verify-binary`](#verify-binary) | Checks built binaries before they are published |

The actions run on GitHub Actions and on compatible runners. Their logic lives
in plain bash scripts under `scripts/`, which also run on their own.

## Usage

Pin an action to the commit of a release tag, and keep the tag in a comment so
that dependency bots can update both:

```yaml
- uses: sutr-app/portable-binary-release/install-protoc@<commit SHA of v1.0.0> # v1.0.0
```

Each release is tested on Linux x86_64, Linux aarch64 and macOS arm64 by the
CI of this repository. Take a new release only after that run has passed for
the commit of its tag.

### install-protoc

Installs the protoc release pinned in `scripts/pins/protoc.sh` for the
runner's platform (Linux x86_64, Linux aarch64 or macOS arm64) and exports
`PROTOC` with its path for the later steps (read by `prost-build` and others).
The download is verified against the pinned SHA-256; nothing is extracted
unless it matches.

| Input | Default | Description |
|---|---|---|
| `dest` | `$RUNNER_TEMP/protoc` | Directory to install into |

| Output | Description |
|---|---|
| `path` | Path of the installed `protoc` |
| `version` | The installed version |

```yaml
- uses: sutr-app/portable-binary-release/install-protoc@<SHA> # v1.0.0
- run: cargo build --release   # prost-build finds protoc through PROTOC
```

### install-cargo-about

Installs the cargo-about release pinned in `scripts/pins/cargo-about.sh` on a
Linux runner (x86_64 or aarch64; the musl builds run on any distribution) and
exports `CARGO_ABOUT` with its path. Like `install-protoc`, the download is
verified against the pinned SHA-256 first.

| Input | Default | Description |
|---|---|---|
| `dest` | `$RUNNER_TEMP/cargo-about` | Directory to install into |

| Output | Description |
|---|---|
| `path` | Path of the installed `cargo-about` |
| `version` | The installed version |

### Tool versions

The pinned tool versions are part of this repository's release: a newer
protoc or cargo-about comes with a new release of the actions, not through an
input. To install the same tools on a development machine, check out the
release your workflows pin:

```sh
git clone --branch v1.0.0 https://github.com/sutr-app/portable-binary-release
bash portable-binary-release/scripts/install-protoc.sh "$HOME/.local/protoc"
export PROTOC="$HOME/.local/protoc/bin/protoc"
bash portable-binary-release/scripts/install-cargo-about.sh "$HOME/.local/cargo-about"   # Linux
```

### verify-binary

Checks built binaries before anything is published, for what would make a
release unusable on the user's machine. Run it on the platform the binaries
were built for (it runs them to check the version, and checks the macOS code
signature there); it never loads a shared library.

| Input | Default | Description |
|---|---|---|
| `files` | (required) | Files to check, one per line |
| `kind` | (required) | `shared-library` or `executable` |
| `linkage` | `dynamic` | `dynamic` or `static` (Linux). `static` accepts static-pie and skips the glibc checks |
| `max-glibc` | | Highest GLIBC symbol version allowed. Required for dynamic Linux binaries; an executable requiring no GLIBC version at all fails |
| `max-glibcxx` | | Highest GLIBCXX symbol version allowed, checked when set |
| `macos-deployment-target` | | Highest minimum macOS (`minos`) allowed. Required on macOS |
| `required-symbols` | | Space-separated C symbols that must be exported |
| `forbidden-deps` | | Space-separated globs matched against each dependency's file name. `libstd-*` (Rust std as a shared library) is always forbidden |
| `allowed-deps` | | Space-separated globs every dependency must match: the soname on Linux, the install name on macOS. A dylib's own install name is not a dependency |
| `required-deps` | | Space-separated dependency file names that must be present |
| `expected-version` | | For executables: `<file> --version` must print `<file name> <expected-version>` |
| `verify-codesign` | `true` | Check the code signature (macOS) |

The platform (`linux-x86_64`, `linux-aarch64` or `darwin-arm64`) is the
runner's. On Linux it needs `file` and binutils (`readelf`, `nm`); on macOS
the Xcode command line tools (`otool`, `nm`, `codesign`).

A plugin loaded with `dlopen`:

```yaml
- uses: sutr-app/portable-binary-release/verify-binary@<SHA> # v1.0.0
  with:
    files: target/release/libmy_plugin.so
    kind: shared-library
    max-glibc: '2.39'
    max-glibcxx: '3.4.33'
    required-symbols: load_plugin free_plugin
    forbidden-deps: 'libssl* libcrypto*'
```

A server linking glibc dynamically, several binaries at once:

```yaml
- uses: sutr-app/portable-binary-release/verify-binary@<SHA> # v1.0.0
  with:
    files: |
      dist/my-server
      dist/my-worker
    kind: executable
    max-glibc: '2.39'
    allowed-deps: 'libc.so.6 libm.so.6 libgcc_s.so.1 ld-linux-*'
    expected-version: ${{ steps.version.outputs.version }}
```

A statically linked (musl) server:

```yaml
- uses: sutr-app/portable-binary-release/verify-binary@<SHA> # v1.0.0
  with:
    files: dist/my-server
    kind: executable
    linkage: static
    expected-version: ${{ steps.version.outputs.version }}
```

On macOS, pass `macos-deployment-target` (the same value as
`MACOSX_DEPLOYMENT_TARGET` at build time) and, for executables,
`allowed-deps: '/usr/lib/* /System/Library/*'` to allow only system
libraries.

## Versioning

Releases follow semantic versioning:

- removing an input or changing its meaning is a major release
- adding an action or an input is a minor release
- updating a pinned tool follows the kind of the tool's own update: a major
  protoc update can change the generated code, so it is a major release here
- fixes are patch releases

## License

[MIT](LICENSE)
