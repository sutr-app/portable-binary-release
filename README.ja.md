# portable-binary-release

[English](README.md)

ネイティブバイナリを、対応を約束した環境で動く状態でリリースするための composite GitHub Actions です。

- ビルドに使うツールを、版を固定し SHA-256 を検証したうえで、root 権限なしで導入する。共有の self-hosted runner でも使える
- ビルドしたバイナリを公開する前に検査する (今後のリリースで追加)

| action | 内容 |
|---|---|
| [`install-protoc`](#install-protoc) | 版を固定した `protoc` を導入し、`PROTOC` を設定する |

各 action は GitHub Actions と、その互換の runner で動きます。処理の本体は `scripts/` 配下の bash スクリプトで、単体でも実行できます。

## 使い方

action はリリースタグのコミットで固定し、タグはコメントに残します。依存関係の更新ボットが、SHA とタグの両方を更新できるようにするためです。

```yaml
- uses: sutr-app/portable-binary-release/install-protoc@<v0.1.0 のコミットの SHA> # v0.1.0
```

各リリースは、このリポジトリの CI で Linux x86_64、Linux aarch64、macOS arm64 の上で検査されます。新しいリリースは、そのタグが指すコミットの CI が成功したことを確かめてから取り込んでください。

### install-protoc

`scripts/pins/protoc.sh` に固定した版の protoc を、runner のプラットフォーム (Linux x86_64、Linux aarch64、macOS arm64) 用に導入し、後続の step のためにそのパスを `PROTOC` に設定します (`prost-build` などが読む)。ダウンロードしたファイルは固定した SHA-256 で検証し、一致しなければ何も展開しません。

| 入力 | 既定 | 内容 |
|---|---|---|
| `dest` | `$RUNNER_TEMP/protoc` | 導入先のディレクトリ |

| 出力 | 内容 |
|---|---|
| `path` | 導入した `protoc` のパス |
| `version` | 導入した版 |

```yaml
- uses: sutr-app/portable-binary-release/install-protoc@<SHA> # v0.1.0
- run: cargo build --release   # prost-build は PROTOC から protoc を見つける
```

protoc の版は、このリポジトリのリリースの一部です。新しい protoc は入力で指定するのではなく、action の新しいリリースとして提供します。

開発環境に同じ protoc を入れるには、workflow で固定している版を取得して実行します。

```sh
git clone --branch v0.1.0 https://github.com/sutr-app/portable-binary-release
bash portable-binary-release/scripts/install-protoc.sh "$HOME/.local/protoc"
export PROTOC="$HOME/.local/protoc/bin/protoc"
```

## 版の付け方

semantic versioning に従います。

- 入力の削除や意味の変更は major
- 入力の追加は minor
- 固定しているツールの更新は、ツール側の更新の区分に合わせる。protoc の major 更新は生成されるコードを変えうるので、ここでも major にする
- 修正は patch

## ライセンス

[MIT](LICENSE)
