# BUILDING — ビルド環境の詳細

本書は `template-jp-document` のビルド環境(Docker イメージの構成、バージョン固定、フォント)に関する詳細をまとめたものです。日々のビルドコマンドと執筆ルールは `README.md` を参照してください。

## ビルドの仕組み

すべてのビルド(`make pdf` / `make watch`)は Docker コンテナ内で実行されます。必要なのは Docker と make のみで、pandoc / typst / plantuml / フォントをローカルへインストールする必要はありません。イメージは初回の `make pdf` で自動構築されます。`Makefile` の `DOCKER_TAG` は `Dockerfile` の内容(+検証系オーバーライド)から自動導出される内容ハッシュのため、ツールチェーンを変更した場合も手動でバンプする必要はなく、変更後の初回ビルドで自動的に別タグとして再構築されます(タグが変わらない限り、既存イメージが再利用され再構築はスキップされます)。

`docker run` には `--user $(id -u):$(id -g)` を付与しているため、`build/` 配下に生成されるファイルはホスト側の実行ユーザー所有になります(コンテナ内で root 所有になる問題を避けるため)。

## 固定バージョン

イメージに導入されるツールチェーンは次のとおりです(`Dockerfile` で固定)。

| ツール | バージョン | 導入方法 |
|---|---|---|
| pandoc | 3.10 | `pandoc/core:3.10` ベースイメージ |
| typst  | 0.15.0 | 公式 GitHub Releases の musl 静的ビルド(sha256 検証) |
| plantuml | 1.2026.6 | Maven Central の jar(sha256 検証) |
| フォント | 下記「フォント」節の表 | Adobe 公式リポジトリのリリースタグ(sha256 検証) |

バージョンが異なると、見出し番号の折り返しや表の罫線など細部のレンダリングが変わる可能性があります。バージョンを上げる場合は `Dockerfile` の該当値を更新してください(`Makefile` の `DOCKER_TAG` は `Dockerfile` の内容ハッシュのため自動的に別タグになり、手動更新は不要です)。CI のビルド結果(生成 PDF のアーティファクト)で見た目の回帰を確認してください。

### Typst バイナリのチェックサム検証

`Dockerfile` は Typst の実行バイナリを GitHub Releases から取得し、sha256 で必ず検証します。ダウンロードしたバイナリが一致しない場合(改ざん・破損・バージョン不一致)はビルドが**エラーで停止**します。

`TYPST_ARCH` を指定しない場合、`Dockerfile` は `RUN` 内で `uname -m` からアーキテクチャを自動判定します(`x86_64` → `x86_64-unknown-linux-musl`、`aarch64` / `arm64` → `aarch64-unknown-linux-musl`)。この 2 アーキテクチャには既定の sha256(`TYPST_SHA256_X86_64` / `TYPST_SHA256_AARCH64`)が `Dockerfile` に焼き込み済みのため、x86_64 でも Apple Silicon 等の aarch64 でも `make pdf` で何も指定する必要はありません。

それ以外のアーキテクチャ、または自動判定を上書きしたい場合は `TYPST_ARCH` ビルド引数を明示指定してください。焼き込み値がないアーキテクチャの場合は対応する `TYPST_SHA256` もあわせて必要です(例: `docker build --build-arg TYPST_ARCH=<対応するターゲット triple> --build-arg TYPST_SHA256=<対応するsha256> .`)。

参考: v0.15.0 の musl 静的ビルドの sha256(GitHub Releases のアセットダイジェスト。`Dockerfile` の焼き込み値と一致):

| アーキテクチャ | sha256 |
|---|---|
| `x86_64-unknown-linux-musl`(自動判定対象。`Dockerfile` に設定済み) | `59b207df01be2dab9f13e80f73d04d7ff8273ffd46b3dd1b9eef5c60f3eeabea` |
| `aarch64-unknown-linux-musl`(自動判定対象。`Dockerfile` に設定済み) | `cdf50ffc7b8ba759ed02200632eda3d78eb8b99aacb6611f4f75684990647620` |

sha256 の取得方法(ワンライナー。URL のバージョン・アーキテクチャは適宜読み替え):

```sh
curl -fsSL "https://github.com/typst/typst/releases/download/v0.15.0/typst-x86_64-unknown-linux-musl.tar.xz" | sha256sum
```

取得した値を指定してビルドする:

```sh
make pdf TYPST_SHA256=<取得したsha256>
```

チェックサム検証なしでビルドする場合(非推奨。検証値を用意できない例外的な場合のみ。焼き込み済みの既定値による検証もスキップされます):

```sh
make pdf ALLOW_UNVERIFIED=1
```

### PlantUML jar のチェックサム検証

`Dockerfile` は PlantUML の jar を Maven Central(`repo1.maven.org`)から取得し、焼き込み済みの sha256 で必ず検証します。Maven Central の成果物はイミュータブル(同一バージョンの再 push 不可)で、jar はアーキテクチャ非依存のため、バージョンと sha256 の固定だけで決定的に導入できます。

| バージョン | sha256 |
|---|---|
| 1.2026.6(既定。`Dockerfile` に設定済み) | `e620ae095a2ba0134d3c33fd5ae34ff01e785f3df1796c0898802b8761a033a8` |

バージョンを変更する場合は、`Dockerfile` の `PLANTUML_VERSION` / `PLANTUML_SHA256` を更新してください。sha256 の取得方法:

```sh
curl -fsSL "https://repo1.maven.org/maven2/net/sourceforge/plantuml/plantuml/<version>/plantuml-<version>.jar" | sha256sum
```

### ベースイメージ(pandoc/core)の digest 固定

`Dockerfile` は既定で `pandoc/core:3.10` をタグ指定で使用しています。タグはリポジトリ側で再 push されうるため、より厳密な決定性が必要な場合は digest を固定してください。

```sh
docker pull pandoc/core:3.10
docker inspect --format '{{index .RepoDigests 0}}' pandoc/core:3.10
# 例: pandoc/core@sha256:<digest>
```

取得した digest を `PANDOC_IMAGE` ビルド引数として指定します(`docker build` を直接呼ぶか、`Makefile` の `docker-build` ターゲットに引数を追加してください)。

```sh
docker build --build-arg PANDOC_IMAGE=pandoc/core@sha256:<digest> -t jp-spec-builder .
```

## フォント

フォントはリポジトリに同梱せず、イメージの構築時に Adobe の公式 GitHub リポジトリ(リリースタグの raw URL)から取得し、sha256 検証のうえ `/opt/fonts` に配置します。タグ付きコミットのファイルはイミュータブルなので、これで決定的に導入できます。[SIL Open Font License 1.1](https://scripts.sil.org/OFL) のライセンス文書も同じ場所に併置されます。

| ファイル | 用途 | Typst 上のファミリー名 | ウェイト | 取得元(リポジトリ@タグ) |
|---|---|---|---|---|
| `SourceHanSerifJP-Regular.otf` | 本文(明朝) | `Source Han Serif JP` | Regular (400) | `source-han-serif@2.003R` |
| `SourceHanSerifJP-Bold.otf` | 本文太字 | `Source Han Serif JP` | Bold (700) | `source-han-serif@2.003R` |
| `SourceHanSansJP-Medium.otf` | 見出し・表・UI(ゴシック) | `Source Han Sans JP` | Medium (500) | `source-han-sans@2.005R` |
| `SourceHanSansJP-Bold.otf` | 見出し太字 | `Source Han Sans JP` | Bold (700) | `source-han-sans@2.005R` |
| `SourceHanCodeJP-Regular.otf` | コード(等幅) | `Source Han Code JP R` | Regular (400) | `source-han-code-jp@2.012R` |
| `SourceHanCodeJP-Bold.otf` | コード太字 | `Source Han Code JP R` | Bold (700) | `source-han-code-jp@2.012R` |

各ファイルの取得 URL と sha256 は `Dockerfile` のフォント導入レイヤーに一覧で書かれています(検証に失敗するとイメージ構築はエラーで停止します)。

**注意(重要)**: `SourceHanCodeJP-*.otf` の OpenType name テーブル上のファミリー名は `Source Han Code JP` ですが、Typst のフォントマッチングでは `Source Han Code JP R` を指定しないと解決できません(末尾の `R`/`B` が weight として自動分離されないため)。同様に `Source Han Sans JP Medium` は `Source Han Sans JP`(ファミリー名からウェイト語が自動的に取り除かれる)として解決されます。フォントを差し替える際は、`fontTools` などで name テーブルを確認し、`template/spec.typ` 冒頭の `font-serif` / `font-sans` / `font-code` の値を実際に解決できるファミリー名に合わせて修正してください。

**図中テキストのフォントについて**: 全 PlantUML 図には `template/plantuml.config` が共通適用され、図中テキストのフォントを本文と同じ `Source Han Sans JP` に指定しています。生成される SVG はテキストをアウトライン化せずフォント名参照のまま保持し、Typst が `/opt/fonts`(`--font-path`)から解決して描画するため、最終 PDF のフォントは実行環境に依存しません。またイメージには `/opt/fonts` を参照する fontconfig 設定を焼き込んであり、PlantUML(Java)によるテキスト幅の計測も同じフォントで行われます(計測フォントが異なると、ラベル幅と図形サイズがずれることがあります)。

fontconfig のキャッシュはイメージ構築時に `fc-cache -f` で焼き込んでいます。ビルドは `docker run --user $(id -u)` で実行され、実行時は `/var/cache/fontconfig` にも `$HOME` にも書き込めないため、キャッシュがないと PlantUML の実行のたびにフォント走査が発生します(`Fontconfig error: No writable cache directories` の警告も出ます)。フォントを差し替える場合も、この `fc-cache` 実行はフォント導入レイヤーの末尾に残してください。

### 別フォントへの差し替え手順(例: UDEV Gothic など)

1. `Dockerfile` のフォント導入レイヤーの一覧(URL と sha256)を、新しいフォントの取得先に差し替える。ライセンス文書の取得もあわせて差し替える(Web 配布されていないフォントを使う場合は、取得の代わりに `COPY` で `/opt/fonts` へ配置する形に変えてもよい)。
2. `fontTools` 等で正しいファミリー名を確認する(`Source Han Code JP` の例のように、見かけと実際の解決名が異なることがあるため、必ず実際にコンパイルして確認すること)。
3. `template/spec.typ` 冒頭の `font-serif` / `font-sans` / `font-code` を新しいファミリー名に書き換える。PlantUML 図を使っている場合は `template/plantuml.config` の `defaultFontName` もあわせて書き換える(図中テキストも Typst が同じ仕組みでフォント解決するため)。
4. `make pdf` を実行し、`Typst warning: unknown font family: ...` が出ないことを確認する(`Makefile` の `DOCKER_TAG` は `Dockerfile` の内容ハッシュのため、`Dockerfile` を変更した時点で自動的に再構築される。PlantUML 図がある場合は図中テキストの描画も確認する)。
5. エディタ内 Typst プレビュー(README の「エディタ内での Typst プレビュー」節)を使っている場合は、`make fonts` を実行し直して `.fonts/` を新しいフォントで書き出し直す。

## ビルドの決定性について

同じ Markdown から常に同じ PDF(バイト単位ではなく見た目単位)を再現できるよう、次の対策をしています。

- **バージョンピン**: pandoc(ベースイメージ)・typst・plantuml・フォントのすべてを `Dockerfile` で固定し、typst / plantuml / フォントは sha256 検証付きで取得しています。PlantUML はバージョンによって図のレイアウトが微妙に変わるため、図の見た目も含めてイメージのバージョン固定が効きます。
- **`--ignore-system-fonts`**: `typst compile` に必ず付与し、実行環境にインストールされているフォントの影響を受けないようにしています。フォントはイメージ内の `/opt/fonts`(`--font-path`)のみを参照します。
- **`date: none`**: `spec-doc` 内部で PDF のドキュメントメタデータの `date` は常に `none` に設定しています(ビルド実行時刻を PDF に埋め込まない)。表紙に表示される発行日は YAML メタデータの `date` フィールド(文字列)であり、ビルド時刻とは無関係です。
- **CI での検証**: GitHub Actions(`.github/workflows/build.yml`)が PR のたびに `make pdf` で同梱サンプル 2 種(章別ファイル分割・単一ファイル)をビルドし、固定ツールチェーンの取得(ベースイメージのタグ・typst / plantuml / フォントの sha256 検証を含む)から PDF 生成までを通しで検証します。生成された PDF はワークフローのアーティファクトとしてダウンロードでき、PR 上で見た目を確認できます。main への push でも同じワークフローを実行します(Actions のキャッシュは既定ブランチで作られたものだけが他ブランチから読めるため、main での実行が Docker イメージキャッシュの供給源になります)。

## シンタックスハイライト

コードブロックのシンタックスハイライト配色は `assets/typst-highlight.tmTheme`(TextMate 形式の配色テーマ)で定義しています。既定のハイライト配色は彩度の高い色(赤紫・鮮緑等)を含み、本テンプレートの青系を基調とした紙面の規律から浮いてしまうため、低彩度のパレットに差し替えています。`template/spec.typ` 側で `set raw(theme: "/assets/typst-highlight.tmTheme")` として読み込んでいます(`--root .` 前提のルート相対パス)。コードブロックの背景色(`code-bg`)はテーマではなく `spec.typ` 側で描画しているため、テーマファイル自体には背景色を指定していません。配色を変更したい場合はこの tmTheme ファイルを編集してください。

## 既知の制約・注意点

- 本テンプレートは Typst 0.15 系の構文を前提としています。
- ビルドには Docker が必須です。Docker なしのローカルビルドは非サポートですが、上記の表と同じバージョンのツールとフォントを自前で用意すれば `scripts/container-build.sh` を直接実行して再現できます(README の「ビルド環境の詳細」の参考欄参照)。なお、Ubuntu の apt が提供する pandoc(24.04 時点で 3.1.3)は Typst ライターが古く、このテンプレートが前提とする出力(表キャプション・`table.header`・`{.unnumbered}`・脚注など)に対応していません。
- イメージの構築時にはネットワークアクセス(Docker Hub・GitHub・Maven Central)が必要です。構築後のビルド実行はオフラインで動作します。
- `pandoc/core` ベースイメージは既定でタグ(`pandoc/core:3.10`)固定であり、digest 固定ではありません。より厳密な決定性が必要な場合は上記「ベースイメージ(pandoc/core)の digest 固定」の手順に従い `PANDOC_IMAGE` を digest 指定に切り替えてください。
