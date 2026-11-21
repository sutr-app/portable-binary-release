# portable-binary-release

[English](README.md)

ネイティブバイナリを、対応を約束した環境で動く状態でリリースするための composite GitHub Actions です。

- ビルドに使うツールを、版を固定し SHA-256 を検証したうえで、root 権限なしで導入する。共有の self-hosted runner でも使える
- ビルドしたバイナリを公開する前に検査する: ファイル形式とアーキテクチャ、要求する glibc / libstdc++ / macOS の版、動的依存、export されたシンボル、コード署名、表示する版

| action | 内容 |
|---|---|
| [`install-protoc`](#install-protoc) | 版を固定した `protoc` を導入し、`PROTOC` を設定する |
| [`install-cargo-about`](#install-cargo-about) | 版を固定した `cargo-about` を導入し、`CARGO_ABOUT` を設定する |
| [`verify-binary`](#verify-binary) | ビルドしたバイナリを公開する前に検査する |

各 action は GitHub Actions と、その互換の runner で動きます。処理の本体は `scripts/` 配下の bash スクリプトで、単体でも実行できます。

## 使い方

action はリリースタグのコミットで固定し、タグはコメントに残します。依存関係の更新ボットが、SHA とタグの両方を更新できるようにするためです。

```yaml
- uses: sutr-app/portable-binary-release/install-protoc@<v1.0.0 のコミットの SHA> # v1.0.0
```

各リリースは、このリポジトリの CI で Linux x86_64、Linux aarch64、macOS arm64 の上で検査されます。新しいリリースは、そのタグが指すコミットの CI が成功したことを確かめてから取り込んでください。

### install-protoc

`scripts/pins/protoc.sh` に固定した版の protoc を、runner のプラットフォーム (Linux x86_64、Linux aarch64、macOS arm64) 用に導入し、後続の step のためにそのパスを `PROTOC` に設定します (`prost-build` などが読む)。ダウンロードしたファイルは固定した SHA-256 で検証し、一致しなければ何も展開しません。

| 入力 | 既定 | 内容 |
|---|---|---|
| `dest` | `$RUNNER_TEMP/protoc` | 導入先のディレクトリ。相対パスはワークスペース (`$GITHUB_WORKSPACE`) からの相対で、`PROTOC` と `path` には常に絶対パスを書き出す |

| 出力 | 内容 |
|---|---|
| `path` | 導入した `protoc` のパス |
| `version` | 導入した版 |

```yaml
- uses: sutr-app/portable-binary-release/install-protoc@<SHA> # v1.0.0
- run: cargo build --release   # prost-build は PROTOC から protoc を見つける
```

### install-cargo-about

`scripts/pins/cargo-about.sh` に固定した版の cargo-about を、Linux の runner (x86_64、aarch64。musl 版なのでディストリビューションを問わない) に導入し、そのパスを `CARGO_ABOUT` に設定します。`install-protoc` と同じく、先に固定した SHA-256 でダウンロードしたファイルを検証します。

| 入力 | 既定 | 内容 |
|---|---|---|
| `dest` | `$RUNNER_TEMP/cargo-about` | 導入先のディレクトリ。相対パスはワークスペース (`$GITHUB_WORKSPACE`) からの相対で、`CARGO_ABOUT` と `path` には常に絶対パスを書き出す |

| 出力 | 内容 |
|---|---|
| `path` | 導入した `cargo-about` のパス |
| `version` | 導入した版 |

### ツールの版

固定しているツールの版は、このリポジトリのリリースの一部です。新しい protoc や cargo-about は入力で指定するのではなく、action の新しいリリースとして提供します。開発環境に同じツールを入れるには、workflow で固定している版を取得して実行します。

```sh
git clone --branch v1.0.0 https://github.com/sutr-app/portable-binary-release
bash portable-binary-release/scripts/install-protoc.sh "$HOME/.local/protoc"
export PROTOC="$HOME/.local/protoc/bin/protoc"
bash portable-binary-release/scripts/install-cargo-about.sh "$HOME/.local/cargo-about"   # Linux
```

### verify-binary

公開する前にバイナリを検査します。対象は、利用者の環境でリリースが使えなくなる原因です。バイナリをビルドしたのと同じプラットフォームで実行してください (版の確認のためにバイナリを実行し、macOS のコード署名もその上で検査します)。共有ライブラリをロードすることはありません。

| 入力 | 既定 | 内容 |
|---|---|---|
| `files` | (必須) | 検査するファイル。1 行に 1 つ |
| `kind` | (必須) | `shared-library` または `executable` |
| `linkage` | `dynamic` | `dynamic` または `static` (Linux)。`static` は static-pie も受け付け、glibc の検査を行わない |
| `max-glibc` | | 許す GLIBC のシンボルの版の上限。Linux の動的リンクのバイナリでは必須。GLIBC の版を 1 つも要求しない実行ファイルは失敗にする |
| `max-glibcxx` | | 許す GLIBCXX のシンボルの版の上限。指定したときだけ検査する |
| `macos-deployment-target` | | 許す最低 macOS (`minos`) の上限。macOS では必須 |
| `required-symbols` | | export されていなければならない C のシンボル (空白区切り) |
| `forbidden-deps` | | 禁止する依存 (ファイル名に対する glob、空白区切り)。`libstd-*` (共有ライブラリの Rust std) は常に禁止する |
| `allowed-deps` | | すべての依存が一致しなければならない glob (空白区切り)。Linux では soname、macOS では install name と照合する。dylib 自身の install name は依存に含めない |
| `required-deps` | | 含まれていなければならない依存のファイル名 (空白区切り) |
| `expected-version` | | 実行ファイルのとき、`<file> --version` が `<ファイル名> <expected-version>` を出力すること |
| `verify-codesign` | `true` | コード署名を検査する (macOS) |

プラットフォーム (`linux-x86_64`、`linux-aarch64`、`darwin-arm64`) は runner のものです。Linux では `file` と binutils (`readelf`、`nm`)、macOS では Xcode のコマンドラインツール (`otool`、`nm`、`codesign`) を使います。

`dlopen` でロードする plugin:

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

glibc に動的リンクする server (複数のバイナリをまとめて検査する):

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

静的リンク (musl) の server:

```yaml
- uses: sutr-app/portable-binary-release/verify-binary@<SHA> # v1.0.0
  with:
    files: dist/my-server
    kind: executable
    linkage: static
    expected-version: ${{ steps.version.outputs.version }}
```

macOS では `macos-deployment-target` (ビルド時の `MACOSX_DEPLOYMENT_TARGET` と同じ値) を渡します。実行ファイルでは、`allowed-deps: '/usr/lib/* /System/Library/*'` でシステムのライブラリだけを許可できます。

## 版の付け方

semantic versioning に従います。

- 入力の削除や意味の変更は major
- action や入力の追加は minor
- 固定しているツールの更新は、ツール側の更新の区分に合わせる。protoc の major 更新は生成されるコードを変えうるので、ここでも major にする
- 修正は patch

## ライセンス

[MIT](LICENSE)
