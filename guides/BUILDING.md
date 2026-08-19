# BUILDING — ビルド環境の詳細

ビルド環境を保守する開発者向けの文書です。ツールチェーンの固定バージョン、チェックサム検証の仕組み、フォントの差し替え手順をまとめています。執筆ルールは [WRITING.md](WRITING.md) を、全体像は [README](../README.md) を参照してください。

## ビルドの仕組み

ビルドはすべて Docker コンテナ内で実行されます。ホストに必要なのは Docker と GNU make だけで、pandoc / typst / plantuml とフォントは `Dockerfile` が固定バージョン+チェックサム検証でイメージに焼き込みます。

- `Makefile` の `DOCKER_TAG` は `Dockerfile` の内容(+検証系オーバーライド)から自動導出される内容ハッシュです。`Dockerfile` を変更すると自動的に別タグになり、次回ビルドで再構築が走ります。**手動のバージョンバンプは不要**です。
- `docker run` は `--user $(id -u):$(id -g)` で実行されます。`build/` 配下の生成物がホストユーザー所有になり、root 所有で消せなくなる事故を防ぎます。
- `Makefile` がビルド対象の導出と検証を行い、ビルド本体はコンテナ内の `scripts/container-build.sh` が担います。

### ビルドの流れと build/ のレイアウト

`make pdf` はコンテナ内で次の順に実行されます。

1. `scripts/lint.sh` によるビルド対象 Markdown の簡易チェック。
2. 改訂履歴の別ファイルがあれば変換(`revisions.md` は `scripts/revisions-md2yaml.sh` で YAML へ)。
3. 参照されている PlantUML 図を `scripts/puml2svg.sh` で SVG へ変換(`-tsvg -failfast2 -config template/plantuml.config -pipe`。mtime 比較で変更分のみ。参照の抽出はコードフェンス除外付きの `scripts/list-diagram-refs.sh`)。
4. pandoc で Markdown → Typst ソースへ変換(`--template template/template.typ`)。
5. `typst compile --root . --font-path /opt/fonts --ignore-system-fonts` で PDF 化。

生成物の配置は次のとおりです。いずれも git 対象外で、`make clean` で削除できます。

| パス | 内容 |
| --- | --- |
| `build/<name>.pdf` | 最終成果物 |
| `build/obj/` | 中間生成物(pandoc が生成した `.typ`、改訂履歴の変換 YAML) |
| `build/diagrams/` | PlantUML から変換した SVG |

## 固定バージョン一覧

| ツール | バージョン | 導入元 |
| --- | --- | --- |
| pandoc | 3.10(ベースイメージ `pandoc/core:3.10.0.0`) | Docker Hub(4 桁のイミュータブルタグ) |
| Typst | 0.15.0 | GitHub Releases の musl 静的ビルド(sha256 検証) |
| PlantUML | 1.2026.6 | Maven Central の jar(sha256 検証) |
| Source Han Serif JP | 2.003R(Regular / Bold) | Adobe 公式リポジトリのリリースタグ(sha256 検証) |
| Source Han Sans JP | 2.005R(Medium / Bold) | Adobe 公式リポジトリのリリースタグ(sha256 検証) |
| Source Han Code JP | 2.012R(Regular / Bold) | Adobe 公式リポジトリのリリースタグ(sha256 検証) |

## Typst バイナリのチェックサム検証

`Dockerfile` は GitHub Releases から Typst の tar.xz を取得し、sha256 を検証してから導入します。

- **アーキテクチャの自動判定**: ビルド引数 `TYPST_ARCH` が空なら `uname -m` から `x86_64-unknown-linux-musl` / `aarch64-unknown-linux-musl` を自動選択します。この 2 つ以外は明示指定が必要です。
- **焼き込み sha256**(Typst 0.15.0):
  - x86_64: `59b207df01be2dab9f13e80f73d04d7ff8273ffd46b3dd1b9eef5c60f3eeabea`
  - aarch64: `cdf50ffc7b8ba759ed02200632eda3d78eb8b99aacb6611f4f75684990647620`
- **上書き**: 他アーキテクチャやバージョン変更時は `TYPST_ARCH` / `TYPST_SHA256` ビルド引数で指定します。`make pdf TYPST_SHA256=<sha256>` のように make 変数でも渡せます(この値は `DOCKER_TAG` のハッシュにも含まれます)。
- **検証スキップ**: `ALLOW_UNVERIFIED=1` で検証を省略できます(非推奨。焼き込み値が古くなった場合の脱出ハッチ)。

sha256 の取得ワンライナー:

```sh
curl -fsSL "https://github.com/typst/typst/releases/download/v0.15.0/typst-x86_64-unknown-linux-musl.tar.xz" | sha256sum
```

## PlantUML jar のチェックサム検証

PlantUML は Maven Central の jar を取得します。jar はアーキテクチャ非依存かつイミュータブルなので、`PLANTUML_VERSION` と `PLANTUML_SHA256` の固定だけで決定的に導入できます。現在の固定値は `1.2026.6` / `e620ae095a2ba0134d3c33fd5ae34ff01e785f3df1796c0898802b8761a033a8` です。バージョンを上げる場合は両方のビルド引数(または `Dockerfile` の既定値)を差し替えます。

## ベースイメージの digest 固定

ベースイメージは `pandoc/core:3.10.0.0` です。4 桁タグは実体が固定されますが、さらに digest で固定したい場合は次の手順で上書きします。

```sh
docker pull pandoc/core:3.10.0.0
docker inspect --format '{{index .RepoDigests 0}}' pandoc/core:3.10.0.0
```

得られた `pandoc/core@sha256:...` を `Dockerfile` の `ARG PANDOC_IMAGE` の既定値に書き換えます(`Dockerfile` の変更で `DOCKER_TAG` が変わり、次回ビルドで自動的に再構築されます)。手動の `docker build` なら `--build-arg PANDOC_IMAGE=pandoc/core@sha256:...` でも指定できます。

## フォント

フォントは Adobe 公式リポジトリ(adobe-fonts)のリリースタグの raw URL から取得し、sha256 検証のうえ `/opt/fonts` に焼き込みます。ライセンスは SIL OFL 1.1 で、再配布条件に従いライセンス文書も `/opt/fonts` に併置します(リポジトリにはフォントを同梱しません)。各ファイルの取得 URL と sha256 は `Dockerfile` のフォント導入レイヤーに一覧で書かれています。

| ファイル | 用途 | Typst 上のファミリー名 | ウェイト |
| --- | --- | --- | --- |
| SourceHanSerifJP-Regular.otf / -Bold.otf | 本文(明朝) | `Source Han Serif JP` | Regular / Bold |
| SourceHanSansJP-Medium.otf / -Bold.otf | 見出し・表・UI 要素(ゴシック) | `Source Han Sans JP` | Medium / Bold |
| SourceHanCodeJP-Regular.otf / -Bold.otf | コード(等幅) | `Source Han Code JP R` | Regular / Bold |

**注意**: Source Han Code JP は、Typst では `Source Han Code JP R` でないと解決できません。フォント内部の name テーブルで実際にマッチするファミリー名が `Source Han Code JP R` であり、Typst は末尾の "R" / "B" を weight として自動分離しないためです(`template/spec.typ` の `font-code` のコメント参照)。CJK フォントは表面上のファミリー名と Typst が解決する名前が食い違うことがあるので、差し替え時は必ず実際の name テーブルを確認してください(`fontTools` で確認できます)。

PlantUML 図の中のフォントは `template/plantuml.config` の `defaultFontName`(現在 `Source Han Sans JP`)が指定します。Typst が SVG 内のテキストを `--font-path` から解決するため、ここも Typst が解決できるファミリー名でなければなりません。

fontconfig のキャッシュはイメージ構築時に `fc-cache -f` で焼き込みます。実行時は `--user` 指定のため `/var/cache/fontconfig` にも `$HOME` にも書き込めず、キャッシュがないと PlantUML(Java/AWT)の実行のたびにフォント走査が走るためです。PlantUML の文字幅計測を PDF 描画と同じフォントで行わないと、ラベル幅と箱のサイズがずれます。

### 別フォントへの差し替え手順

1. `Dockerfile` のフォント導入レイヤーを差し替える(取得 URL と sha256 の一覧)。
2. 新フォントの name テーブルで、Typst が解決できるファミリー名を確認する。
3. `template/spec.typ` のフォント定数(`font-serif` / `font-sans` / `font-code`)と `template/plantuml.config` の `defaultFontName` を変更する。
4. `make pdf` を実行し、`unknown font family` の警告が出ないことを確認する(`Dockerfile` の変更でイメージは自動再構築されます)。
5. エディタ内 Typst プレビューの利用者は `make fonts` を実行し直す(`.fonts/` は毎回作り直され、旧フォントは残りません)。

## ビルドの決定性

誰がどの環境でビルドしても同じ PDF になるよう、次を徹底しています。

- 全ツールチェーンとフォントのバージョンピン+sha256 検証。
- `typst compile` は `--ignore-system-fonts` で実行し、ホストやイメージのシステムフォントの混入を防ぐ(参照は `/opt/fonts` のみ)。
- PDF メタデータの日付は `template/spec.typ` で `date: none` に固定(既定の auto はビルド時刻を埋め込み、同一入力でもバイト単位で一致しなくなるため)。
- CI(`.github/workflows/build.yml`)が PR・main への push・週次(月曜 0:00 UTC)に `make test` → `make lint` → サンプル 2 種の `make pdf` → `make pdf-all` を通し検証。Docker イメージは `Dockerfile` のハッシュをキーにキャッシュされ、main での実行が各 PR ブランチへのキャッシュ供給源になります。週次実行はキャッシュを使わずフル構築し、依存の取得元消失を検知します。

## シンタックスハイライト

コードブロックの配色は `assets/typst-highlight.tmTheme`(低彩度の独自テーマ)です。既定のハイライトは彩度が高く紙面から浮くため差し替えています。コードブロックの背景色はテーマではなく `template/spec.typ` 側(`code-bg`)が描画します。

## 既知の制約

- **Typst 0.15 系が前提**。テンプレート(`template/spec.typ`)は同梱バージョンの Typst でのみ検証しています。
- **Docker 必須**。非サポートの参考情報として、同じバージョンのツールチェーンとフォントを自前で用意すれば、`scripts/container-build.sh` を直接実行できます。`Makefile` が設定する環境変数も自前で与えます。

  ```sh
  NAME=my-spec SRC_INPUTS=docs/my-spec.md FONT_DIR=/path/to/fonts \
    sh scripts/container-build.sh
  ```

  Ubuntu の apt の pandoc は Typst ライターが古く非対応です。
- **イメージ構築時のみネットワークが必要**(Typst / PlantUML / フォントの取得)。構築後のビルドはオフラインで動きます。
- **apk の graphviz はバージョン未固定**。PlantUML のレイアウト(クラス図・状態遷移図など)に使われますが、Alpine のパッケージ版をそのまま導入しており、ベースイメージ更新で変わりえます。
