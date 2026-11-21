# portable-binary-release

[日本語版はこちら](README.ja.md)

Composite GitHub Actions for releasing native binaries that run on the
platforms you promise to support:

- install build tools at a pinned version, verified by SHA-256, with no root
  privileges, so shared self-hosted runners can use them
- check a built binary before it is published (coming in a later release)

| Action | What it does |
|---|---|
| [`install-protoc`](#install-protoc) | Installs the pinned `protoc` and exports `PROTOC` |

The actions run on GitHub Actions and on compatible runners. Their logic lives
in plain bash scripts under `scripts/`, which also run on their own.

## Usage

Pin an action to the commit of a release tag, and keep the tag in a comment so
that dependency bots can update both:

```yaml
- uses: sutr-app/portable-binary-release/install-protoc@<commit SHA of v0.1.0> # v0.1.0
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
- uses: sutr-app/portable-binary-release/install-protoc@<SHA> # v0.1.0
- run: cargo build --release   # prost-build finds protoc through PROTOC
```

The protoc version is part of this repository's release: a newer protoc comes
with a new release of the action, not through an input.

To install the same protoc on a development machine, check out the release
your workflows pin:

```sh
git clone --branch v0.1.0 https://github.com/sutr-app/portable-binary-release
bash portable-binary-release/scripts/install-protoc.sh "$HOME/.local/protoc"
export PROTOC="$HOME/.local/protoc/bin/protoc"
```

## Versioning

Releases follow semantic versioning:

- removing an input or changing its meaning is a major release
- adding an input is a minor release
- updating a pinned tool follows the kind of the tool's own update: a major
  protoc update can change the generated code, so it is a major release here
- fixes are patch releases

## License

[MIT](LICENSE)
