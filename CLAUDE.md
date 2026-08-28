# CLAUDE.md

このリポジトリで Markdown 仕様書を執筆・ビルドする AI エージェント向けの手引きです。人間向けの詳しい説明は `README.md` を、執筆記法のリファレンスは `guides/WRITING.md` を、ビルド環境の詳細は `guides/BUILDING.md` を、Markdown に不慣れな利用者向けの手引きは `guides/GETTING-STARTED.md` を参照してください。

**ディレクトリの役割**: 利用者の原稿は `docs/` に置く。`examples/` は見本(コピー元・実例参照用)であり、原則として書き換えない。

## ビルドコマンド

```sh
make pdf SRC=docs/foo.md      # 単一 Markdown ファイルをビルド(SRC 必須)
make pdf SRC=docs/foo         # 章別ファイル分割ディレクトリをビルド(下記参照。SRC 必須)
make example                  # 同梱サンプル 2 種(章別ファイル分割・単一ファイル)をビルド
make pdf-all                  # docs/ 配下のビルド対象を自動発見して全件ビルド
make watch SRC=docs/foo.md    # 執筆中の自動リビルド(保存するたびに再ビルド。Ctrl-C で終了。SRC 必須)
make fonts                    # エディタ内 Typst プレビュー(Tinymist)用にイメージ内のフォントを .fonts/ へ書き出す
make lint                     # docs/ と examples/ の Markdown(単一ファイル+章別ファイル分割)の簡易 lint のみを実行
make test                     # scripts/lint.sh 自体の回帰テスト(scripts/test-lint.sh)を実行
make clean                    # build/ を削除
```

ビルドはすべて Docker コンテナ内で実行される(pandoc / typst / plantuml とフォントはイメージ内に固定バージョン+チェックサム検証で導入。ローカルへのインストールは不要で、Docker と make だけが必要)。`Makefile` の `DOCKER_TAG` は `Dockerfile` の内容(+検証系オーバーライド)から自動導出される内容ハッシュのため、ツールチェーンやフォントの固定バージョンを変更しても手動でバンプする必要はない(`Dockerfile` を変更すれば自動的に別タグになり、利用者側の次回ビルドで再構築が走る)。`make pdf` は次の順で実行されます(検証は `Makefile`、ビルド本体はコンテナ内の `scripts/container-build.sh`)。

1. `SRC` の存在確認(章別ファイル分割の場合は `00-meta.md` と章ファイルの有無、参照図に対応する `.puml` の有無)と改訂履歴ファイルの併存チェックを行い、続けて Docker イメージを用意する(未構築・ツールチェーン変更時のみ実体の構築が走る)。
2. `scripts/lint.sh` でビルド対象の Markdown を簡易チェックする(`make lint` は docs/ と examples/ の `*.md` 全件 + 章別ファイル分割ディレクトリすべてが対象。ただし改訂履歴ファイル `*.revisions.md` / `<name>/revisions.md` は仕様書本文ではないため lint.sh 側で除外される。`*.revisions.yaml` / `revisions.yaml` も対象外)。行末が CRLF の原稿もそのまま検査できる(行末の CR は読み込み時に落とす)。
   - **エラー(ビルド停止)**: 見出しの手動採番(`# 1. foo` / `## 2) foo` / `## 1.1. foo` / `## 1．foo` / `## (1) foo` のような「番号+ドット/括弧」、`# 第1章 foo` / `# 1章 foo` のような「(第)N章/節/項」)、YAML フロントマターの `title:` 欠落・空、章別ファイル分割時に `00-meta.md` 以外の章ファイルへ YAML フロントマターが混入していること(後方ファイルが前方を上書きする合成規則による事故防止。下記「章別ファイル分割」参照)、PlantUML 参照の不備(`.puml` の直接画像参照、`/build/diagrams/<name>.svg` 形式以外の図の参照、参照に対応する `assets/diagrams/<name>.puml` の不存在)、`/assets/` 配下の参照先ファイル・フロントマターの `logo:` が指す画像の不存在、注記ボックス(`::: info` 等の fenced div)のフェンス不一致(閉じフェンス `:::` のない開始フェンス、開始フェンスのない閉じフェンス。pandoc は div として認識せず `:::` をそのまま本文に印字するため)。
   - **警告(ビルド継続)**: 見出しが数字で始まる(`## 2.5 系` 等。上記エラーパターンに一致しない、手動採番の疑いがあるだけのケース)、生 Typst(` ```{=typst} `)ブロック内の装飾コード(`set text(` 等)、章別ファイル分割時に同一ディレクトリ内の章ファイル間で脚注定義 ID(`[^id]:`)が重複していること、注記ボックスの種類が `info` / `warning` / `error` 以外であること(`scripts/admonitions.lua` が変換せず装飾なしのブロックになる)、`:::` で始まるが開始フェンスとして認識されない行(種類名の後に文字が続く等)。
3. ビルド対象が画像参照している PlantUML 変換図(`/build/diagrams/*.svg`。参照の抽出は `scripts/list-diagram-refs.sh` がコードフェンス除外付きで行う)について、名前の 1:1 対応で逆引きしたソース(`assets/diagrams/<name>.puml`)を `scripts/puml2svg.sh` で変換する(変更分のみ。図を参照しない文書では plantuml 不要)。全図に `template/plantuml.config`(図中フォント・配色などの共通デザイン)が `-config` として共通適用される。
4. `pandoc --from markdown --to typst --standalone --template template/template.typ -o build/obj/<name>.typ <SRC_INPUTS>`。`<SRC_INPUTS>` は単一ファイルモードでは `SRC` 1 個、章別ファイル分割モードでは `00-meta.md` を含む章ファイル一覧(ファイル名の辞書順)。pandoc は複数の入力ファイルを連結して 1 文書として処理でき、章の自動採番・ファイル横断リンク・脚注・表番号・表紙/目次のいずれも単一ファイルと同様に正しく動作する。改訂履歴の別ファイルがある場合は `--metadata-file` が自動付与される: `revisions.md`(単一ファイルモードでは `docs/<name>.revisions.md`。推奨。Markdown パイプ表)なら `scripts/revisions-md2yaml.sh` が `build/obj/<name>.revisions.yaml` へ変換してから、`revisions.yaml`(単一ファイルモードでは `docs/<name>.revisions.yaml`。代替)ならそのまま渡される。**両方が存在するとエラーで停止する**。`SRC` に `.revisions.md` / `.revisions.yaml` そのものを指定してもエラーで停止する。
5. `typst compile --root . --font-path /opt/fonts --ignore-system-fonts build/obj/<name>.typ build/<name>.pdf`(フォントはイメージに焼き込まれたものを参照する)。

`build/` 配下のレイアウト: 最終成果物の PDF は `build/` 直下、中間生成物(`.typ` / 改訂履歴の変換 YAML)は `build/obj/`、PlantUML から変換した SVG は `build/diagrams/` に置かれる。

CI(`.github/workflows/build.yml`)も PR・main への push・週次の定期実行で同じ `make pdf` を使い、examples のサンプル 2 種(章別ファイル分割・単一ファイル)をビルド検証し、続けて `make pdf-all` で docs/ 配下の利用者の文書をビルド検証する(テンプレート時点では docs/ が空のため no-op)。`make pdf-all` は `docs/_` 始まりのディレクトリ・ファイルを対象外とし(下書き・共有素材の置き場)、それ以外の規約に合わない `.md`・`docs/<name>.md` と `docs/<name>/` の同名衝突はエラーで停止する。

`SRC` のパスにスペースは使えない(Make の引数分割の制約のため)。スペースを含むパスを指定すると `make pdf` / `make watch` は明確なエラーメッセージで停止する(章別ファイル分割のディレクトリパス、およびその中の章ファイル名も対象)。単一ファイルの `SRC` は `.md` 拡張子が必須(改訂履歴の自動検出が `<name>.md` → `<name>.revisions.md` という命名規約に依存するため。`.md` 以外はエラーで停止する)。

`make watch` は Docker コンテナ内で `scripts/container-build.sh` が watch モードで動き続ける(リポジトリはマウント共有のため、ホスト側エディタの編集がそのまま検知される)。構成は (a) 初回 `make pdf` 相当を実行 → (b) `typst watch` をバックグラウンド起動(`.typ` / `template/*.typ` の変更を自動検知)→ (c) `<SRC_INPUTS>`(と改訂履歴の別ファイル・参照図に対応する `.puml`・`template/plantuml.config`)を 1 秒間隔でポーリングし、変更を検知したら lint →(`.revisions.md` / `revisions.md` があれば YAML 変換)→ PlantUML 図の再変換(変更分のみ)→ pandoc を再実行して `.typ` を再生成する、という三段構成。章別ファイル分割の場合、章ファイルを 1 つ編集して保存するだけで `<SRC_INPUTS>` 全体が pandoc に再度渡され `.typ` 全体が再生成される(監視対象の章ファイル一覧・参照図の `.puml` 一覧はポーリングのたびに動的に再導出されるため、章ファイルの新規追加・削除や図参照の増減があっても `make watch` の再起動は不要)。lint / 変換 / pandoc がエラーになっても watch 自体は停止せず継続する(修正して保存すれば次のポーリングで再試行される)。Ctrl-C で `typst watch` の子プロセスごと終了する。詳細は README の「執筆中の自動更新とプレビュー」節を参照。

`.vscode/` と `make fonts` は、`make watch` が再生成する `build/obj/<name>.typ` を VS Code の Tinymist 拡張でライブプレビューするための設定とフォント書き出し(詳細は README の「執筆中の自動更新とプレビュー」節)。プレビューは拡張同梱の Typst でコンパイルされるため、見た目の最終確認は `build/<name>.pdf` で行う。

## 章別ファイル分割

`SRC` にディレクトリを指定すると(例: `docs/my-spec`)、章ごとに分けた複数の Markdown ファイルを 1 文書としてビルドできる。ディレクトリ規約:

- **`00-meta.md`**: フロントマター専用・必須。ここにのみ `title` 等のメタデータを書く(章ファイルだけを置いて `00-meta.md` を忘れたディレクトリは `make pdf-all` がエラーで停止する。無言でビルド対象から漏れるのを防ぐため)。
- **`[0-9][0-9]-*.md`**: 章ファイル。ファイル名の辞書順が章順(`00-meta.md` は自然に先頭に来る)。1 つ以上必須。後から章を挿入しやすいよう `10-`, `20-`, `30-` のように番号を飛ばして振る運用も可。
- **`revisions.md`(推奨)/ `revisions.yaml`(代替)**: 単一ファイルモードの `<name>.revisions.md` / `<name>.revisions.yaml` と同じ仕組み(guides/WRITING.md の「改訂履歴の別ファイル化」参照)。

**フロントマターは 00-meta.md にのみ書くこと**。Pandoc は複数入力ファイルを連結する際、後方ファイルのフロントマターが前方を上書きするため、章ファイルにフロントマターを混入させると `title` 等が意図せず上書き・消去される(`scripts/lint.sh` がこれをエラーで検出する)。脚注定義 ID(`[^id]:`)は分割全体で一意にすること(重複すると連結時に衝突する。`scripts/lint.sh` が警告で検出する)。

実例: `examples/sample-spec/` が章別ファイル分割、`examples/wareki-api-spec.md` が単一ファイル方式。

## 執筆 → ビルド → 確認 → 修正のループ

1. `docs/*.md` を編集する(構造のみ。スタイル記述は禁止。詳細は guides/WRITING.md 参照)。
2. `make pdf` を実行する。
3. **Typst のエラーを読む**:
   - `typst compile` が失敗したら、エラーメッセージの該当行を `build/obj/<name>.typ` で直接開いて確認する。これは Pandoc が生成した Typst ソースなので、Markdown のどの記述がどの Typst コードに対応するかを突き合わせながら原因を特定する。
   - `unknown font family: ...` という警告/エラーが出た場合は、`template/spec.typ` の `font-serif` / `font-sans` / `font-code` に指定しているファミリー名と、イメージ内 `/opt/fonts` のフォント(`Dockerfile` のフォント導入レイヤーが取得する)の実際の name テーブルが一致しているか確認する(`fontTools` で確認できる)。CJK フォントは表面上のファミリー名と Typst が実際に解決するファミリー名が異なることがある(例: `Source Han Code JP` ではなく `Source Han Code JP R` でないと解決できない)。
   - Typst の構文エラー(`expected comma` 等)は行番号が付かないことがある。疑わしい箇所を最小構成に切り出して単体コンパイルすると原因を特定しやすい。
4. **PDF を目視確認する**。可能であれば PNG に書き出して確認する:
   ```sh
   # ビルドに使うイメージ内の typst でページごとの PNG を得られる
   docker run --rm --user $(id -u):$(id -g) -v "$PWD":/work -w /work jp-spec-builder:latest \
     typst compile --root . --font-path /opt/fonts --ignore-system-fonts \
     --format png --ppi 150 build/obj/<name>.typ 'build/<name>-{p}.png'
   ```
   確認観点: 表紙のレイアウト崩れ、改訂履歴・目次のページ番号、見出しの採番が二重になっていないか(下記の注意参照)、表のヘッダ網掛け・罫線、コードブロックの等幅フォント、和文の禁則・justify、ヘッダ/フッタが表紙に出ていないか、フォント未解決による代替フォント(明朝でない文字など)、表紙タイトルの泣き別れ(1 文字だけの行)、章末の数行・表・コード片だけが孤立したほぼ白紙のページ(本文の編集で吸収する)、同種の表の幅が揃っているか(列幅はパイプテーブル区切り行のダッシュ比率で統一できる)。
5. 崩れがあれば `template/spec.typ` (見た目) または Markdown 本文(構造)を修正し、3〜4 を再度回す。

## 執筆ルールの要点

- **Markdown は構造のみ**。フォント指定・色・余白などのスタイル記述は書かない。すべて `template/spec.typ` が担う。
- **見出しに手動で番号を振らない**。`# はじめに` と書けば `1 はじめに` のように自動採番される。`# 1. はじめに` のように自分で番号を書くと、Typst の自動採番と二重になって `1 1. はじめに` のような表示になってしまう(実際に起きたバグなので特に注意)。
- 見出しレベル: H1=章(章ごとに自動改ページ)、H2=節、H3=項、H4 以降=番号なし小見出し。
- **付録など番号を振らない章には `{.unnumbered}` を付ける**(例: `# 付録A: エスケープハッチの例 {.unnumbered}`)。自動採番の対象外になるが、改ページ・目次への収載は維持される。
- 表・コードブロック・脚注は Markdown 標準の記法をそのまま使う。表の網掛け・罫線・キャプション書式は自動適用される(キャプション自体は表の直後の行に `: キャプション文` と書く)。`*強調*`(斜体)は和文にイタリックがないためゴシック体で表示される。
- **相互参照**: 見出しに `{#sec-id}` で ID を付け、本文から `` `@sec-id`{=typst} `` で参照すると「1章」「1.1節」形式の番号付きリンクになる(番号を表示しない H4 以降・`{.unnumbered}` 見出しへの参照は見出しテキストのリンクになる)。図は画像参照の属性(`{#fig-id}`)、表はキャプション行の末尾(`: キャプション文 {#tbl-id}`)に ID を付けると同様に「図 1」「表 1」形式で参照できる(guides/WRITING.md の「よく使う生 Typst レシピ」参照)。
- **図**: 画像ファイル(PNG/JPG/SVG)は `assets/images/` に置き `![キャプション](/assets/images/foo.png){width=70%}` のようにルート絶対パスで参照する。シーケンス図・状態遷移図などは PlantUML ソースを `assets/diagrams/<name>.puml` に置き、**変換後の SVG パスを画像参照する**(`![キャプション](/build/diagrams/<name>.svg){width=75%}`。`<name>` はソースと同名)。SVG への変換はビルドが参照からソースを逆引きして自動で行うため、生成 SVG をコミットしてはいけない(管理対象はソースのみ。`.puml` の直接画像参照は lint がエラーにする)。図中フォント等の共通設定は `template/plantuml.config` に書く。実例: `examples/sample-spec/04-api-spec.md` + `assets/diagrams/reservation-sequence.puml`(シーケンス図)、`examples/sample-spec/03-requirements.md` + `assets/diagrams/reservation-states.puml`(状態遷移図)。
- 和文中の括弧は全角括弧、英数字のみを囲む場合は半角括弧を使う(コードブロック・インラインコード内は対象外)。
- **改訂履歴(`revisions`)が長くなったら別ファイルに切り出せる**。推奨は `docs/<name>.revisions.md`(章別ファイル分割の場合は `docs/<name>/revisions.md`)という Markdown パイプ表(列は「版数|日付|作成者|改訂内容」の 4 列固定、1 改訂 = 1 行、セル内に生の `|` は不可)。代替として `docs/<name>.revisions.yaml` / `docs/<name>/revisions.yaml`(トップレベルに `revisions:` 配列)も使える。いずれも置くだけで `Makefile` が自動検出して pandoc の `--metadata-file` に反映する(`examples/wareki-api-spec.md` + `examples/wareki-api-spec.revisions.md` が単一ファイルモードの実例)。`.revisions.md` と `.revisions.yaml` の併存はビルドエラーになる。Pandoc の合成規則上、フロントマター側の `revisions` が `--metadata-file` 側を常に上書きするため、**`revisions` はフロントマター・別ファイルのいずれか 1 箇所にのみ書く**(推奨: `.revisions.md` / `revisions.md`)。詳細は guides/WRITING.md の「改訂履歴の別ファイル化」節を参照。

## エスケープハッチの判断基準

生 Typst(` ```{=typst} ` フェンス)は次のように判断する。

- **使ってよい**: セル結合(`table.cell(colspan:, rowspan:)`)など、Markdown 標準の記法では原理的に表現できないもの。
- **使うべきでない**: 見た目の微調整、Markdown で表現できる内容(それは `spec.typ` 側の show/set ルールを直すべき)。
- 生 Typst ブロック内では `template/spec.typ` の色定数・フォント定数・ヘルパー関数を `accent-color` などとしてそのまま参照できる(`template/template.typ` が `#import "/template/spec.typ": *` している)。table を生 Typst で書く場合も、罫線やヘッダ網掛けは `spec.typ` の `show table: ...` が自動適用するので、通常は `#table(...)` を素直に書けば十分(手動で block 装飾を重ねる必要はない)。

## コメントの方針(Makefile / scripts / template を修正するとき)

コメントには、保守に必要な制約と「なぜこの実装でなければならないか」だけを書く。変更の経緯・修正履歴・以前の実装との比較・レビュー対応の説明は書かない(経緯は git のコミット履歴に残す)。過去のレビューで経緯説明のコメントが増えすぎて整理した経緯があるため、特に注意する。

## 見た目を変更したいとき

`template/spec.typ` のみを編集する。主な構成:

- 冒頭: 色定数(`accent-color` 等)・フォント定数(`font-serif` / `font-sans` / `font-code`)
- `cover-page`: 表紙
- `revision-history`: 改訂履歴表
- `doc-header` / `doc-footer`: 2 ページ目以降のヘッダ・フッタ
- `spec-doc`: メインエントリポイント。見出し・表・コード・リンク・引用などの show/set ルール一式と、表紙 → 改訂履歴 → 目次 → 本文(ページ番号 1 起算。改訂履歴と目次はそれぞれ独立したページ)という全体構成を持つ

`template/template.typ` は Pandoc のメタデータを `spec-doc(...)` の引数へ橋渡しするだけで、見た目に関する記述を追加してはいけない。

PlantUML 図の見た目(図中フォント・配色などの共通デザイン)だけは `template/plantuml.config` が担う(`spec.typ` は SVG の中身に関与できないため)。個々の図固有の `skinparam` は各 `.puml` に書いてよい。

フォント自体を差し替える場合は、`template/spec.typ` のフォント定数だけでなく `Dockerfile` のフォント導入レイヤー(取得 URL と sha256)と `template/plantuml.config` の `defaultFontName` もあわせて変更する(手順は guides/BUILDING.md の「フォント」節参照)。エディタ内 Typst プレビューを使っている場合は `make fonts` も実行し直す。
