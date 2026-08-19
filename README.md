# japanese-spec-template

日本語の仕様書を Markdown で書き、A4 縦の PDF に仕上げるテンプレートです。Markdown には文書の構造だけを書きます。フォント・配色・レイアウトなどの体裁は Typst テーマ(`template/spec.typ`)が自動で適用します。

## クイックスタート

必要なものは Docker と GNU make だけです(Windows は WSL2 を想定。Ubuntu なら `sudo apt install make` で導入できます)。pandoc や Typst のインストールは不要で、ビルドはすべて Docker コンテナ内で実行されます。

まず同梱サンプルをビルドして、動作と仕上がりを確認します。

```sh
make example    # examples/ のサンプル 2 種をビルド(初回は Docker イメージ構築で数分)
```

`build/sample-spec.pdf` と `build/wareki-api-spec.pdf` ができれば成功です。

自分の原稿は、見本を `docs/` にコピーして書き始めます。

```sh
# 単一ファイルで始める場合
cp examples/wareki-api-spec.md docs/my-spec.md
cp examples/wareki-api-spec.revisions.md docs/my-spec.revisions.md   # 改訂履歴も使うなら

# 章ごとにファイルを分ける場合
cp -r examples/sample-spec docs/my-spec
```

編集したらビルドします。PDF は `build/my-spec.pdf` に出力されます。

```sh
make pdf SRC=docs/my-spec.md   # 章分割なら make pdf SRC=docs/my-spec
```

Markdown が初めての方は [guides/GETTING-STARTED.md](guides/GETTING-STARTED.md) から読んでください。

## make コマンド一覧

| コマンド | 説明 |
| --- | --- |
| `make pdf SRC=docs/foo.md` | 単一 Markdown ファイルをビルド |
| `make pdf SRC=docs/foo` | 章別ファイル分割ディレクトリをビルド |
| `make example` | 同梱サンプル 2 種をビルド |
| `make pdf-all` | `docs/` 配下のビルド対象を自動発見して全件ビルド |
| `make watch SRC=docs/foo.md` | 保存のたびに自動リビルド(Ctrl-C で終了) |
| `make fonts` | エディタ内プレビュー用にフォントを `.fonts/` へ書き出す |
| `make lint` | `docs/` と `examples/` の Markdown を簡易 lint |
| `make test` | lint スクリプト自体の回帰テスト |
| `make clean` | `build/` を削除 |
| `make help` | コマンド一覧を表示(引数なしの `make` も同じ) |

`pdf` と `watch` は `SRC` の指定が必須です。`SRC` のパスにスペースは使えません。単一ファイルの `SRC` には `.md` 拡張子が必要です。いずれも違反時は明確なエラーで停止します。

## 仕組み

ビルドは Markdown → Pandoc(Typst バックエンド)→ Typst → PDF の 2 段変換です。中心にあるのは、構造と美観の分離です。

- **構造は Markdown に**。見出し・表・コード・脚注だけを書き、スタイル記述は書きません。
- **美観は `template/spec.typ` に一元化**。見た目を変えたいときはここだけを直します。
- Markdown で原理的に表現できないもの(表のセル結合など)に限り、生 Typst のエスケープハッチを使えます。

pandoc / typst / plantuml とフォントは、固定バージョン+チェックサム検証で Docker イメージに同梱されます。誰がどの環境でビルドしても同じ見た目の PDF になります。

## ディレクトリ構成

```
docs/       原稿を置く場所(ビルド・lint の対象)
examples/   見本(コピー元。原則書き換えない)
template/   spec.typ(テーマ本体)、template.typ(Pandoc との橋渡し)、plantuml.config
assets/     diagrams/(PlantUML ソース)、images/(図版)、typst-highlight.tmTheme
scripts/    ビルド・lint スクリプト
guides/     執筆リファレンス・入門・ビルド環境の各ガイド
build/      生成物(git 対象外。make clean で削除)
```

`examples/` は各ガイドから実例として参照されているため、残しておくことを推奨します。削除する場合は `Makefile` の `example` ターゲットと CI のサンプルビルドもあわせて削除してください(残したまま `examples/` だけ消すと `make example` と CI が失敗します)。

## 章別ファイル分割

大きな文書は章ごとにファイルを分けられます。`SRC` にディレクトリを指定してください。

```
docs/my-spec/
├── 00-meta.md              フロントマター専用(必須)
├── 10-introduction.md      章ファイル(ファイル名の辞書順が章順)
├── 20-requirements.md
└── revisions.md            改訂履歴の別ファイル(任意)
```

- `00-meta.md`: フロントマター専用。必須。`title` 等のメタデータはここにだけ書く。
- 章ファイルは `[0-9][0-9]-*.md` で 1 つ以上必要。`10-`, `20-` と番号を飛ばして振ると、後から章を挿入しやすい。
- 改訂履歴は `revisions.md`(推奨)または `revisions.yaml`。両方を同時には置けません。

フロントマターを章ファイルに書いてはいけません。Pandoc は複数ファイルを連結する際、後方のフロントマターが前方を上書きするためです(lint がエラーで検出します)。

## 執筆中の自動更新とプレビュー

`make watch SRC=docs/my-spec.md` を起動しておくと、保存のたびに PDF が再ビルドされます。
lint やビルドのエラーが出ても watch は止まりません。修正して保存すれば再試行されます。
章ファイルの追加・削除も再起動なしで反映されます。終了は Ctrl-C です。

PDF ビューアが自動リロードに対応していれば、`build/<name>.pdf` を開いたままにするだけで更新が反映されます。Microsoft Edge など自動リロードしないビューアの場合は、次のエディタ内プレビューを使ってください。

VS Code では Tinymist 拡張でライブプレビューができます。`make fonts` でイメージ内のフォントを `.fonts/` へ書き出し(書き出す前は和文が代替フォントになり、見た目が一致しません)、`make watch` が再生成する `build/obj/<name>.typ` を開いてプレビューします(`docs/foo.md` → `build/obj/foo.typ`)。利用時の注意:

- リポジトリのルートをワークスペースとして開く(`/assets/...` などのルート絶対パスを解決するため)。
- 編集するのは常に `docs/` 側。`build/obj/*.typ` を直接編集しても次の再生成で失われる。
- プレビューが更新されないときは `make watch` のターミナルを確認する(lint や pandoc のエラーで `.typ` が再生成されていないことが多い)。
- プレビューは拡張同梱の Typst でコンパイルされるため、見た目の最終確認は `build/<name>.pdf` で行う。

## 執筆ルールの要点

- Markdown には構造だけを書く。スタイル記述は書かない。
- 見出しに手動で番号を振らない。自動採番と二重になり `1 1. はじめに` のような表示になる。
- 図は PlantUML ソース(`assets/diagrams/*.puml`)だけを Git 管理する。SVG への変換はビルドが自動で行うので、生成物はコミットしない。

記法の早見表・相互参照・メタデータ一覧・改訂履歴の書き方・生 Typst の例など、詳細は [guides/WRITING.md](guides/WRITING.md) を参照してください。

## CI

GitHub Actions が PR・main への push・週次の定期実行で `make pdf` を検証します。`docs/` に置いた文書は `make pdf-all` が自動でビルドし、生成された PDF はワークフローのアーティファクトから取得できます。`_` 始まりの名前(`docs/_drafts/` など)はビルド対象外なので、下書きや共有素材の置き場に使えます。それ以外の規約に合わない `.md` や、`docs/<name>.md` と `docs/<name>/` の同名衝突は、無言でビルド対象から漏れるのを防ぐためエラーで停止します。

## テンプレート更新の取り込み

このテンプレートを元に作ったリポジトリへ、テンプレート側の改善を取り込むには:

```sh
git remote add upstream <テンプレートのリポジトリ URL>
git fetch upstream
git checkout upstream/main -- template/ scripts/ Makefile Dockerfile .github/ guides/
```

`template/spec.typ` をカスタマイズしている場合は、上書き前に差分を確認してください。

## レビューと納品の運用(推奨)

- レビューは Git の差分(PR)を基本にする。Git に不慣れなレビュアーには PDF 注釈でもよい。
- 納品時は PDF だけでなく Markdown・図のソース一式も併せて納める。受領側が同じ手順で再生成・二次利用できるためです。
- 改訂履歴の内容は「3.2 節の表記を修正」のように章節番号レベルで具体的に書く。

## ドキュメント

- [guides/GETTING-STARTED.md](guides/GETTING-STARTED.md) — Markdown に不慣れな方向けの入門
- [guides/WRITING.md](guides/WRITING.md) — 執筆リファレンス(記法早見表・メタデータ一覧)
- [guides/BUILDING.md](guides/BUILDING.md) — ビルド環境の詳細(固定バージョン・フォント差し替え)

## ライセンス

このリポジトリは MIT ライセンスです([LICENSE](LICENSE))。
フォントはリポジトリに同梱せず、Docker イメージ構築時に取得します(SIL OFL 1.1。ライセンス条文はイメージ内 `/opt/fonts/` に併置されます)。
