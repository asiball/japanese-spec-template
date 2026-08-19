# template-jp-document

Markdown で構造だけを書き、体裁の作り込みは Typst テーマに任せる、日本語仕様書のためのドキュメントテンプレートです。最終成果物は A4 縦の PDF です。

## クイックスタート

必要なのは **Docker と GNU make** の 2 つだけです(Docker 本体の導入は [公式ドキュメント](https://docs.docker.com/get-started/get-docker/)参照)。Linux / macOS で動作します。Windows では WSL2 上での利用を想定しています(Windows 標準では make が入っていないため。WSL2 の Ubuntu なら `sudo apt install make` で導入できます)。

この 2 つが使える環境なら、追加のインストールなしで同梱サンプルをビルドできます(初回はビルド環境の構築で数分かかります。2 回目以降はキャッシュが効きます)。

```sh
make example      # 同梱サンプル 2 種(章別ファイル分割・単一ファイル)をビルド → build/*.pdf
```

pandoc / typst / plantuml とフォントは、すべて Docker イメージ内に固定バージョン+チェックサム検証で導入されます。ローカルへのインストールが不要なだけでなく、実行環境によらず同じ見た目の PDF が得られます(詳細は [guides/BUILDING.md](guides/BUILDING.md))。

自分の仕様書は、見本を `docs/` にコピーして書き始めます。

```sh
cp examples/wareki-api-spec.md docs/my-spec.md   # 単一ファイル方式(短め〜中規模の文書)
# 見本の改訂履歴も使う場合(別ファイル。本体だけコピーすると改訂履歴ページが出ない)
cp examples/wareki-api-spec.revisions.md docs/my-spec.revisions.md
make pdf SRC=docs/my-spec.md
```

章の多い文書は章別ファイル分割方式(`cp -r examples/sample-spec docs/my-spec`)が使えます(下記「章別ファイル分割」参照)。執筆時の約束事と記法の早見表は [guides/WRITING.md](guides/WRITING.md) を、Markdown に不慣れな方向けの手引きは [guides/GETTING-STARTED.md](guides/GETTING-STARTED.md) を参照してください。

## 目次

- [コンセプト](#コンセプト)
- [ディレクトリ構成](#ディレクトリ構成)
- [使い方](#使い方)
- [章別ファイル分割](#章別ファイル分割)
- [執筆中の自動更新(make watch)](#執筆中の自動更新make-watch)
- [エディタ内での Typst プレビュー](#エディタ内での-typst-プレビュー)
- [執筆ルール(要点)](#執筆ルール要点)
- [レビュー・納品の運用(推奨)](#レビュー納品の運用推奨)
- [ビルド環境の詳細](#ビルド環境の詳細)
- [ライセンス](#ライセンス)

## コンセプト

- **Markdown → Pandoc(Typst バックエンド)→ Typst → PDF** という 2 段変換でビルドします。
- Markdown 側は見出し・表・リスト・コードブロックといった「構造」だけを記述します。フォント・配色・余白・罫線などの「美観」は一切書きません。
- 美観に関する定義はすべて `template/spec.typ` に一元化されています。デザインを変えたいときはこのファイルだけを見ればよい、という状態を保つのがこのテンプレートの目的です。
- Markdown 標準の記法では表現できないもの(セル結合を伴う表など)に限り、Pandoc の生 Typst 記法(エスケープハッチ)を使うことを許容します。

ビルドの流れ(すべて Docker コンテナ内で実行されます):

```mermaid
flowchart LR
    subgraph repo["原稿とテーマ(Git 管理)"]
        MD["Markdown<br/>(構造のみ)"]
        REV["改訂履歴<br/>revisions.md"]
        PUML["図のソース<br/>assets/diagrams/*.puml"]
        SPEC["template/spec.typ<br/>(見た目の定義)"]
    end
    subgraph docker["Docker コンテナ(ツールチェーンとフォントを固定バージョンで同梱)"]
        PANDOC["pandoc"]
        PLANTUML["plantuml"]
        TYPST["typst"]
    end
    PDF["build/#lt;name#gt;.pdf"]

    MD --> PANDOC
    REV --> PANDOC
    PUML --> PLANTUML
    PANDOC -- ".typ(構造)" --> TYPST
    SPEC -- "show/set ルール(見た目)" --> TYPST
    PLANTUML -- "SVG" --> TYPST
    TYPST --> PDF
```

なぜこの構成か: Pandoc は Markdown の構造解析と柔軟な形式変換に強く、Typst は組版(段組・見出し番号・和文禁則・シンタックスハイライト)に強い、という役割分担です。LaTeX と比べて Typst はビルドが高速で、テーマ定義が素直な関数ベースの Typst コードで書けるため、体裁の一元管理と保守がしやすくなっています。

## ディレクトリ構成

```
.
├── docs/                             自分の仕様書(原稿)の置き場所。ビルド・lint の対象
├── examples/                         コピー元・参照用の見本(原則書き換えない)
│   ├── sample-spec/                  サンプル仕様書(章別ファイル分割の実例。下記「章別ファイル分割」参照)
│   │   ├── 00-meta.md                フロントマター専用ファイル(revisions をフロントマターに直接書く方式の実例)
│   │   └── 01-introduction.md 〜 99-appendix.md
│   │                                 章ファイル(ファイル名の辞書順が章順)
│   ├── wareki-api-spec.md            サンプル仕様書(単一ファイル方式。API リファレンス型のレイアウト実例)
│   └── wareki-api-spec.revisions.md  改訂履歴を別ファイル化した実例(guides/WRITING.md の「改訂履歴の別ファイル化」参照)
├── template/
│   ├── spec.typ                      テーマ本体。美観に関する定義はすべてここに集約
│   ├── template.typ                  Pandoc 用 Typst テンプレート(構造の橋渡しのみ)
│   └── plantuml.config               全 PlantUML 図に共通適用する設定(図中フォントの指定など)
├── assets/
│   ├── diagrams/                     PlantUML ソース(.puml)の置き場所。ビルド時に SVG へ自動変換(guides/WRITING.md の「図の挿入」参照)
│   ├── images/                       Markdown 本文から参照する図版(PNG/JPG/SVG)
│   └── typst-highlight.tmTheme       コードブロックのシンタックスハイライト配色(低彩度パレット)
├── scripts/
│   ├── container-build.sh            ビルド本体(`make pdf` / `make watch` が Docker コンテナ内で実行)
│   ├── lint.sh                       docs/ と examples/ の Markdown の簡易 lint(`make lint` とビルド時に実行)
│   ├── test-lint.sh                  lint.sh の回帰テスト(`make test` から実行)
│   ├── revisions-md2yaml.sh          改訂履歴の Markdown パイプ表 → YAML 変換(ビルド時に自動実行)
│   ├── puml2svg.sh                   PlantUML → SVG 変換(ビルド時に自動実行)
│   └── list-diagram-refs.sh          Markdown が参照する図の列挙(Makefile が変換対象の決定に使用)
├── guides/                           人間向けの詳細ガイド
│   ├── WRITING.md                    執筆リファレンス(記法の早見表・図・メタデータ・改訂履歴・生 Typst レシピ)
│   ├── GETTING-STARTED.md            非技術者向けクイックスタート(Markdown 初心者の PM・品証向け)
│   └── BUILDING.md                   ビルド環境の詳細(Docker・バージョン固定・チェックサム検証・フォント差し替え)
├── .vscode/                          VS Code の推奨拡張と Tinymist の設定(任意。下記「エディタ内での Typst プレビュー」参照)
├── .github/workflows/build.yml       CI(PR ごとに lint・lint.sh の回帰テスト・サンプルビルド・docs/ の自動ビルド検証を実行)
├── Dockerfile                        ビルド環境(pandoc / typst / plantuml とフォントを固定バージョンで同梱。guides/BUILDING.md 参照)
├── .dockerignore                     ビルドコンテキストの除外指定(Dockerfile は COPY を行わないため全除外)
├── Makefile                          ビルドコマンド一式
├── README.md                         このファイル
├── CLAUDE.md                         AI エージェント向けの執筆・ビルドガイド
└── LICENSE                           ライセンス(MIT。「ライセンス」節を参照)
```

`docs/` が利用者の原稿置き場、`examples/` がコピー元・参照用の見本です。`examples/` 配下は README・guides/ 配下のガイド・CLAUDE.md から実例として参照されているため、書き換えずに残しておくことを推奨します(サンプルを削除する場合は、`Makefile` の `example` ターゲットと CI(`.github/workflows/build.yml`)のサンプルビルド 2 ステップが `examples/` を直接参照しているため、あわせて削除してください。残したまま `examples/` だけ消すと `make example` と CI が失敗します)。

`docs/` に文書を置けば、設定変更なしで CI(`make pdf-all`。PR・main への push・週次の定期実行で起動)がビルド検証し、生成された PDF をワークフローのアーティファクトから取得できます。ビルド対象外の作業ファイル(下書き・共有素材など)は `_` 始まりの名前(例: `docs/_drafts/`、`docs/_memo.md`)にすると `make pdf-all` の対象外になります(それ以外の規約に合わない `.md` は、無言でビルド対象から漏れるのを防ぐためエラーで停止します)。

### テンプレート本体の更新の取り込み

`docs/`(原稿)と `assets/`(図版)以外 — `template/` / `scripts/` / `Makefile` / `Dockerfile` / `.github/` / `guides/` — は、利用者が原則編集しない共通基盤です。このテンプレートを複製して書き始めた後にテンプレート本体側のバグ修正・改善を取り込みたい場合は、基盤ファイルだけを上書き取得します。

```sh
git remote add upstream <テンプレートリポジトリの URL>   # 最初の 1 回だけ
git fetch upstream
git checkout upstream/main -- template/ scripts/ Makefile Dockerfile .github/ guides/
```

`template/spec.typ` を自分でカスタマイズしている場合は上書きされるため、先に差分を確認してから取り込んでください。

## 使い方

```sh
make pdf SRC=docs/foo.md        # 単一 Markdown ファイルをビルド(SRC は必須)
make pdf SRC=docs/foo           # 章別ファイル分割ディレクトリをビルド(下記「章別ファイル分割」参照)
make example                    # 同梱サンプル 2 種(章別ファイル分割・単一ファイル)をビルド
make pdf-all                    # docs/ 配下のビルド対象を自動発見して全件ビルド
make watch SRC=docs/foo.md      # 任意の Markdown / ディレクトリを自動リビルド(執筆中の常時起動用。下記「執筆中の自動更新」参照)
make fonts                      # エディタ内プレビュー用にフォントを .fonts/ へ書き出す(下記「エディタ内での Typst プレビュー」参照)
make lint                       # docs/ と examples/ の Markdown(単一ファイル+章別ファイル分割)の簡易 lint のみを実行
make test                       # scripts/lint.sh 自体の回帰テストを実行(原稿の執筆では通常使わない)
make clean                      # build/ を削除
make help                       # 上記コマンド一覧を表示(引数なしの make も同じ)
```

**注意**: `SRC` を省略すると `make pdf` / `make watch` は案内付きのエラーで停止します(同梱サンプルのビルドは `make example` を使ってください)。`SRC` のパスにスペースは使えません(Make の引数分割の制約のため)。スペースを含むパスを指定すると `make pdf` / `make watch` は明確なエラーメッセージで停止します(章別ファイル分割のディレクトリパス、およびその中の章ファイル名も対象です)。また、単一ファイルの `SRC` は `.md` 拡張子が必須です(改訂履歴の自動検出が `<name>.md` → `<name>.revisions.md` という命名規約に依存するため。`.md` 以外を指定すると明確なエラーで停止します)。

`make pdf` は次の段階を実行します(検証は `Makefile`、ビルド本体は Docker コンテナ内の `scripts/container-build.sh`)。

1. `SRC` の存在確認(章別ファイル分割の場合は `00-meta.md` と章ファイルの有無、参照されている `.puml` の有無)と改訂履歴ファイルの併存チェックを行う(イメージ構築より先に、安価な検証でエラー停止できるようにしている)。続けて Docker イメージを用意する(未構築・ツールチェーン変更時のみ実体の構築が走る)。
2. `scripts/lint.sh` でビルド対象の Markdown を簡易チェック(`make lint` 単体は docs/ と examples/ の `*.md` 全件 + 章別ファイル分割ディレクトリすべてが対象。改訂履歴ファイル `*.revisions.md` / `*.revisions.yaml` / `revisions.md` / `revisions.yaml` は仕様書本文ではないため対象外)。行末が CRLF(Windows のエディタが保存する改行)の原稿もそのまま検査できます。
   - **エラー(ビルド停止)**: 見出しの手動採番(`# 1. foo` / `## 2) foo` / `## 1.1. foo` / `## 1．foo` / `## (1) foo` のような「番号+ドット/括弧」形式、`# 第1章 foo` / `# 1章 foo` のような「(第)N章/節/項」形式)、YAML フロントマターの `title:` 欠落・空、章別ファイル分割時に 00-meta.md 以外の章ファイルへ YAML フロントマターが混入していること、PlantUML 参照の不備(`.puml` の直接画像参照、`/build/diagrams/<name>.svg` 形式(ルート絶対パス)以外の図の参照、参照に対応する `assets/diagrams/<name>.puml` の不存在)、`/assets/` 配下の参照先ファイル・フロントマターの `logo:` が指す画像の不存在。
   - **警告(ビルド継続)**: 見出しが数字で始まる(`## 2.5 系` のようなバージョン表記など、上記エラーパターンには一致しないが手動採番の疑いがあるケース)、生 Typst(` ```{=typst} `)ブロック内の装飾コード検出、章別ファイル分割時に同一ディレクトリ内の複数章ファイルで脚注定義 ID(`[^id]:`)が重複していること。
3. ビルド対象の Markdown が参照している PlantUML 変換図(`/build/diagrams/*.svg`)に対応するソース(`assets/diagrams/<name>.puml`)を `scripts/puml2svg.sh` で変換する(変更されたものだけを再変換。図を参照していない文書では何もしない)。
4. `pandoc --from markdown --to typst --standalone --template template/template.typ` で Markdown を Typst ソースに変換(`build/obj/<name>.typ` に出力)。章別ファイル分割の場合は 00-meta.md を含む章ファイル一覧(ファイル名の辞書順)を複数の入力として pandoc に渡す(pandoc は複数入力ファイルを連結して 1 文書として処理する)。改訂履歴を別ファイル化している場合は、`revisions.md`(または `<name>.revisions.md`)を YAML に変換したうえで(YAML 方式ならそのまま)`--metadata-file` も付与される(guides/WRITING.md の「改訂履歴の別ファイル化」参照)。
5. `typst compile --root . --font-path /opt/fonts --ignore-system-fonts` で PDF を生成(`build/<name>.pdf`)。フォントはイメージに焼き込まれたものを参照する([guides/BUILDING.md](guides/BUILDING.md) の「フォント」節参照)。

`build/` 配下は、最終成果物と中間生成物をサブフォルダで分けています。

```
build/
├── <name>.pdf          最終成果物
├── obj/                中間生成物(pandoc が生成した .typ、改訂履歴の変換 YAML)
└── diagrams/           PlantUML から変換された SVG
```

いずれもビルドのたびに再生成できる生成物であり、Git の管理対象ではありません(`build/` ごと gitignore 済み。`make clean` で削除できます)。

## 章別ファイル分割

1 ファイルの Markdown が長くなってきた場合、`SRC` にディレクトリを指定することで、章ごとにファイルを分けて書けます。

```sh
make pdf SRC=docs/my-spec       # docs/my-spec/ を章別ファイル分割として扱う
```

### ディレクトリ規約

```
docs/my-spec/
├── 00-meta.md              フロントマター専用(必須)
├── 01-introduction.md      章ファイル(ファイル名の辞書順が章順)
├── 02-overview.md
├── ...
└── 99-appendix.md
```

- **`00-meta.md`**: フロントマター専用ファイル。**必須**。存在しない場合、`make pdf` は明確なエラーで停止します(章ファイルだけを置いて `00-meta.md` を忘れたディレクトリは、`make pdf-all` もビルド対象として検出できないためエラーで停止します。黙って未ビルドのまま CI が緑になるのを防ぐためです)。`title` などのメタデータ([guides/WRITING.md](guides/WRITING.md) の「メタデータ(YAML フロントマター)一覧」参照)をここに書きます。本文(見出しや段落)はここには書かず、章ファイル側に書いてください。
- **`[0-9][0-9]-*.md`**: 章ファイル。**ファイル名の辞書順がそのまま章の並び順**になります(`00-meta.md` 自身もこのパターンに一致するため、常に先頭に来ます)。1 つ以上必要です(`00-meta.md` のみでは `make pdf` がエラーで停止します)。
- **`revisions.md`(推奨)/ `revisions.yaml`(代替)**: 改訂履歴。数字プレフィックスを持たないため章ファイルの glob には含まれません。単一ファイル方式の `<name>.revisions.md` / `<name>.revisions.yaml` と同じ変換・併存エラー・`--metadata-file` の仕組みがそのまま使えます(guides/WRITING.md の「改訂履歴の別ファイル化」参照)。

### 運用上の注意

- **番号は飛ばして振ってよい**: `01-`, `02-`, `03-` と連番にせず、`10-`, `20-`, `30-` のように間隔を空けて振っておくと、後から章を挿入したいときに既存ファイルをリネームせずに済みます(例: `10-` と `20-` の間に `15-` を挿入)。
- **フロントマターは 00-meta.md にのみ書く**: pandoc は複数の入力ファイルを連結する際、**後方のファイルのフロントマターが前方を上書きする**という合成規則を持ちます。章ファイルにフロントマター(`---` で始まるブロック)を書いてしまうと、00-meta.md で設定した `title` などが後続の章ファイルによって意図せず上書き・消去される事故につながります。`scripts/lint.sh` は 00-meta.md 以外の章ファイルの先頭行が `---` の場合にエラーでビルドを停止し、この事故を未然に防ぎます。
- **脚注定義 ID は分割全体で一意にする**: `[^id]: 説明` の `id` が複数の章ファイルで重複していると、pandoc が連結した際に脚注が衝突します。`scripts/lint.sh` は同一ディレクトリ内の章ファイル間で脚注定義 ID が重複している場合に警告します(ビルドは継続するので、`id` をユニークな名前(例: `[^ch2-note1]`)にリネームしてください)。
- 章の自動採番・章をまたぐ相互リンク・脚注・表番号・表紙/目次は、単一ファイル方式と同様にすべて自動で正しく動作します(内部的には pandoc が全章ファイルを 1 つの文書として処理するため)。
- `make watch SRC=docs/my-spec` は監視対象の章ファイル一覧をポーリングのたびに再導出します。**監視中に章ファイルを追加・削除しても `make watch` の再起動は不要です**(次のポーリングで自動的に反映されます)。

`examples/sample-spec/` が章別ファイル分割の実例、`examples/wareki-api-spec.md` が単一ファイル方式の実例です。

## 執筆中の自動更新(`make watch`)

執筆中に「保存するたびに手動で `make pdf` を打つ」手間を省くため、`make watch` は次を行います。

```sh
make watch SRC=docs/foo.md      # 単一 Markdown ファイルを監視
make watch SRC=docs/foo         # 章別ファイル分割ディレクトリを監視
```

1. まず通常の `make pdf` 相当を 1 回実行する(lint・初回ビルドを含む)。以降の監視もすべて同じ Docker コンテナ内で動きますが、リポジトリはマウントで共有されるため、ホスト側のエディタでの編集がそのまま検知されます。
2. `typst watch` をバックグラウンドで起動する。`build/obj/<name>.typ` や `template/*.typ`(見た目を変更したとき)の変更を検知して自動的に PDF を再コンパイルする。
3. フォアグラウンドで監視対象のファイルを 1 秒間隔でポーリングし、変更を検知するたびに lint →(改訂履歴が `.revisions.md` / `revisions.md` の場合は YAML 変換)→ PlantUML 図の再変換(変更分のみ)→ pandoc の再実行、という順で `build/obj/<name>.typ` を再生成する(再生成された `.typ` は上記の `typst watch` が拾って PDF に反映する)。監視対象の原稿一覧(章別ファイル分割なら章ファイル一覧)・参照図の `.puml` 一覧は、ポーリングのたびに動的に再導出される。監視対象は、原稿本体(単一ファイルならそのファイル、章別ファイル分割なら現時点の全章ファイル)・別ファイル化した改訂履歴・参照中の図に対応する `.puml`・`template/plantuml.config` です。章別ファイル分割の場合、章ファイルを 1 つだけ編集して保存しても、この仕組みにより全章ファイルが再度 pandoc に渡され `.typ` 全体が再生成されます。**章ファイルの追加・削除や、Markdown に図の参照を新しく追加した場合も、`make watch` を再起動せずに次のポーリングで自動的に検知されます**(一覧を毎回再導出し、前回との差分も再生成のトリガーにするため)。

**動作上の注意**:

- Markdown の lint エラーや pandoc の変換エラーが発生しても `make watch` 自体は停止しません。エラーメッセージを表示したうえで監視を継続し、ファイルを修正して保存すると次のポーリングで自動的に再試行します。
- 終了するときは **Ctrl-C** を押してください。バックグラウンドの `typst watch` プロセスも一緒に終了します。
- PDF ビューア側の自動リロード(ファイルが更新されたら開いているビューアが再読み込みする機能)は本テンプレートの範囲外で、お使いの PDF ビューアの対応状況に依存します(自動リロードに対応したビューアであれば、`make watch` が生成する `build/<name>.pdf` を開いたままにしておくと更新が反映されます)。**Microsoft Edge など自動リロードしないビューアを使っている場合は、PDF を開き直す代わりに下記「エディタ内での Typst プレビュー」を使うと、保存するたびに VS Code 内で仕上がりを確認できます。**
- 内部実装(`scripts/container-build.sh` の watch モード)は POSIX sh のみで書かれており、`inotifywait` / `fswatch` のような追加ツールには依存しません。

## エディタ内での Typst プレビュー

PDF ビューアを開き直さずに仕上がりを確認したい場合は、VS Code の [Tinymist Typst](https://marketplace.visualstudio.com/items?itemName=myriad-dreamin.tinymist) 拡張のライブプレビューを `make watch` と組み合わせます。`make watch` は原稿を保存するたびに中間生成物 `build/obj/<name>.typ` を再生成するので、この `.typ` を Tinymist のプレビューで開いておけば、保存のたびにエディタ内のプレビューが再描画されます(PDF を経由しません)。

### 準備(最初の 1 回だけ)

1. VS Code でこのリポジトリのルートをワークスペースとして開きます(`/assets/images/...` などのルート絶対パスの参照が、ビルドの `--root .` と同じくワークスペースルート基準で解決されるようにするためです)。
2. `make fonts` を実行してフォントを書き出します。ビルドで使うフォントは Docker イメージ内(`/opt/fonts`)にしかなく、拡張に同梱された Typst からは参照できないため、イメージから `.fonts/`(git 管理対象外)へ取り出します。`.vscode/settings.json` の `tinymist.fontPaths` がこのディレクトリを指しているため、設定変更は不要です。**書き出す前は和文が代替フォントで表示され、ビルド結果と見た目が一致しません。**
3. 推奨拡張の通知から **Tinymist Typst** をインストールします(`.vscode/extensions.json` に登録済み)。

### 使い方

`make watch SRC=docs/foo.md` を起動したままにします。プレビュー対象の `.typ` の名前は `SRC` から決まり、初回ビルドで生成されます(`docs/foo.md` → `build/obj/foo.typ`、章別ファイル分割 `docs/my-spec` → `build/obj/my-spec.typ`)。この `.typ` を VS Code で開き、エディタ右上のプレビューアイコン(またはコマンドパレットで「Typst Preview」)からプレビューを開始して、原稿の隣に並べておきます。保存から反映までは数秒かかります(`make watch` が 1 秒間隔のポーリングで pandoc を再実行するため)。

**注意**:

- **成果物の PDF はあくまで `make pdf` / `make watch`(コンテナ内の Typst)が生成するものです**。プレビューは拡張に同梱された Typst でコンパイルされるためバージョンが一致するとは限らず、細部が異なる可能性があります。納品前の最終確認は必ず `build/<name>.pdf` で行ってください。
- プレビューに表示されるのは pandoc が生成した `.typ` なので、**編集するのは常に `docs/*.md` 側**です。`build/obj/*.typ` を直接編集しても次の再生成で失われます。
- **プレビューが更新されないときは `make watch` のターミナルを確認してください**。lint や pandoc がエラーになると `.typ` が再生成されず、プレビューは古い内容のまま変化しません。
- フォントを差し替えたとき(`Dockerfile` のフォント導入レイヤーを変更したとき)は、`make fonts` を実行し直してください。

## 執筆ルール(要点)

- **Markdown は構造のみ**を書きます。太字・表・コードブロック・脚注など Markdown 標準の記法だけを使い、フォント指定・色・余白などスタイルに関する記述は書きません(見た目はすべて `template/spec.typ` が自動適用します)。
- **見出しに手動で番号を振りません**。`# はじめに` と書けば「1 はじめに」のように自動採番されます(自分で番号を書くと二重になります。付録など番号を振らない章は `{.unnumbered}` を付けます)。
- **図はソースだけを Git 管理します**。画像は `assets/images/` に、PlantUML は `assets/diagrams/<name>.puml` に置き、SVG への変換はビルドに任せます(生成 SVG はコミットしません)。

記法の一覧(見出し・表・図・脚注・相互参照の早見表、一般的な Markdown との違い、メタデータ一覧、改訂履歴の別ファイル化、生 Typst レシピ)は **[guides/WRITING.md](guides/WRITING.md)** にまとめています。

## レビュー・納品の運用(推奨)

Word の変更履歴・コメント往復の代替として、次の運用を推奨します。

- **レビューは Git(PR)差分で行うのを基本とする**。Markdown はテキストなので、通常のコードレビューと同じ流れで行数単位の差分・コメント・提案を扱えます。
- **非技術者や社外レビュアーには PDF 注釈の往復も可**とする。Git に不慣れなレビュアー向けの代替経路であり、両方を強制する必要はありません。
- **納品時は元 Markdown 一式を PDF と併せて納める**。Markdown 一式(`docs/` 配下の原稿・参照している `assets/images/` / `assets/diagrams/` 配下の図版)を PDF と一緒に渡しておくと、受領側でのテキストの二次利用や、版間の差分確認がしやすくなります。PlantUML の図はソース(`.puml`)が原本です(受領側が画像ファイルとして必要とする場合は、ビルドで生成される `build/diagrams/` の SVG を添えてください)。
- **改訂履歴(`revisions`)の `changes` は章節番号レベルで具体的に書く**。「表現を修正」のような曖昧な記述ではなく、「4.2 共通エラー仕様に `STOCKTAKE_CONFLICT` を追加」のように、どの節の何を変えたかが分かる粒度で書いてください。受領側が改訂内容を PDF の目次・見出し番号と突き合わせて追えるようになります。

## ビルド環境の詳細

ビルド環境の構築・固定に関する詳細は [guides/BUILDING.md](guides/BUILDING.md) にまとめています。

- Docker イメージの構成(pandoc / typst / plantuml / フォントの固定バージョンとチェックサム検証)
- ベースイメージの digest 固定
- ビルドの決定性(同じ Markdown から同じ見た目の PDF を得るための対策)・CI での検証
- フォントの詳細と別フォントへの差し替え手順
- コードブロックのシンタックスハイライト配色の変更
- 既知の制約・注意点

**参考(非サポート)**: Docker を使えない環境でも、[guides/BUILDING.md](guides/BUILDING.md) の表と同じバージョンの pandoc / typst / plantuml とフォント一式を自前で用意すれば、`make pdf` がコンテナ内で実行しているビルド本体(`scripts/container-build.sh`)を `FONT_DIR=<フォントの場所>` を指定して直接実行し、ローカルでビルドすることも可能です。バージョン・フォントの差による見た目の変化はサポート対象外です。

## ライセンス

このリポジトリに含まれるファイルは、リポジトリ直下の `LICENSE`(MIT License)に従います。

フォントはリポジトリに同梱せず、Docker イメージの構築時に Adobe の公式リポジトリから取得します(sha256 検証付き)。フォント自体は [SIL Open Font License 1.1](https://scripts.sil.org/OFL) の下で配布されているもので、ライセンス条文はイメージ内の `/opt/fonts/` にフォントと併置されます。フォントの一覧・ファミリー名・差し替え手順は [guides/BUILDING.md](guides/BUILDING.md) の「フォント」節を参照してください。
