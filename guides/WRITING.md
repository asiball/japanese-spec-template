# WRITING — 執筆リファレンス

原稿を書く開発者向けのリファレンスです。記法の早見表、このテンプレート特有のルール、メタデータの一覧、生 Typst の定番レシピをまとめています。Markdown 自体に不慣れな方は先に [GETTING-STARTED.md](GETTING-STARTED.md) を、ビルド環境の内部は [BUILDING.md](BUILDING.md) を、全体像は [README](../README.md) を参照してください。

仕上がりのイメージは、`make example` でビルドされる `build/sample-spec.pdf` と原稿(`examples/`)を突き合わせるのが早道です。

## 記法早見表

| 書きたいもの | 書き方 | PDF での見え方 |
| --- | --- | --- |
| 章 | `# はじめに` | 「1 はじめに」。章ごとに自動改ページ |
| 節 | `## 目的` | 「1.1 目的」 |
| 項 | `### 前提条件` | 「1.1.1 前提条件」 |
| 小見出し | `#### 補足`(H4 以降) | 番号なしのゴシック小見出し |
| 番号なしの章(付録) | `# 付録A: 用語集 {.unnumbered}` | 番号なし。改ページと目次収載は維持 |
| 太字 | `**必須**` | 太字 |
| 斜体 | `*強調*` | ゴシック体。和文フォントにイタリックがないため |
| 表+キャプション | パイプ表の直後の行に `: キャプション文` | ヘッダ網掛け+上下罫線+「表 1 キャプション文」 |
| コードブロック | ` ```python ` 〜 ` ``` `(言語名を指定) | 等幅フォント+低彩度ハイライト |
| インラインコード | `` `to_wareki()` `` | 等幅+薄い枠 |
| 脚注 | 本文に `[^id]`、任意の場所に `[^id]: 説明` | ページ下部に脚注 |
| 定義リスト | `用語` の次行に `: 説明` | 太字の用語+字下げした説明 |
| 引用 | `> 引用文` | 左罫線+淡い背景 |
| 画像 | `![キャプション](/assets/images/foo.png){width=70%}` | 図番号付きの図 |
| PlantUML 図 | `![キャプション](/build/diagrams/foo.svg){width=75%}` | 図番号付きの図。ソースは `.puml` |
| 相互参照(見出し) | 見出しに `{#sec-id}`、本文に `` `@sec-id`{=typst} `` | 「1章」「1.1節」形式の番号リンク |
| 相互参照(図・表) | 図は `{#fig-id}`、表はキャプション行末に `{#tbl-id}` | 「図 1」「表 1」形式の番号リンク |
| 改ページ | ` ```{=typst} ` 内に `#pagebreak()` | その位置で改ページ |
| セル結合 | 生 Typst の `table.cell(colspan:, rowspan:)` | 結合されたセル |
| 横向きページ | 生 Typst の `#page(flipped: true)[...]` | そのページだけ横向き(A4 横) |

## 一般的な Markdown との違い(ハマりどころ)

このテンプレートの出力先は HTML ではなく Typst 経由の PDF です。Web 向けの Markdown の癖が通用しない箇所がいくつかあります。

- **見出しに手動で番号を振らない**。`# 1. はじめに` と書くと自動採番と二重になり「1 1. はじめに」になります。`# 1. foo` / `## 1.1. foo` / `## (1) foo` / `# 第1章 foo` の形式は lint がエラーで止めます。`## 2.5 系` のような数字始まりは手動採番の疑いとして警告のみ出ます(バージョン表記など正当なら無視してかまいません)。
- **スタイル記述を書かない**。フォント・色・余白の指定は禁止です。体裁はすべて `template/spec.typ` が適用します。見た目を変えたいときは Markdown ではなく `spec.typ` を直します。lint は生 Typst 内の `set text(` などの装飾コードにも警告を出します。
- **HTML タグは無効**。出力が Typst のため `<br>` や `<b>` などはタグが無視され、中のテキストだけが残ります。改行はブロックを分ける、強調は `**太字**` を使うなど、Markdown の記法で表現してください。
- **画像・図はルート絶対パス必須**。`![...](/assets/images/foo.png)` のようにリポジトリルートからの `/` 始まりで書きます。相対パスの図参照や `.puml` の直接参照は lint がエラーにします。参照先が存在しない場合もエラーです。
- **フロントマターの `title:` は必須**。欠落・空値は lint がエラーで止めます(表紙とヘッダに使われるため)。
- **脚注 ID は文書全体で一意に**。章別ファイル分割では、章ファイル間で `[^id]:` の ID が重複すると連結時に衝突します(lint が警告します)。
- **括弧の使い分け**。和文中の括弧は全角、英数字のみを囲む場合は半角を使います。コードブロック・インラインコードの中は対象外です。

## 見出しレベルの運用

- **H1 = 章**。章ごとに自動で改ページされ、濃紺の罫線付きの章扉になります。
- **H2 = 節**、**H3 = 項**。H3 まで「1.1.1」形式で自動採番されます。
- **H4 以降 = 番号なしの小見出し**。採番されず、目次にも載りません。
- 付録など番号を振りたくない章には `{.unnumbered}` を付けます。採番だけが外れ、改ページと目次収載は維持されます。

## 図の挿入

### 画像ファイル(PNG / JPG / SVG)

画像は `assets/images/` に置き、ルート絶対パスで参照します。alt テキストがそのままキャプションになり、図番号は自動で振られます。幅は `{width=70%}` のように指定します。

```markdown
![在庫管理システムの構成概要](/assets/images/system-overview.png){width=70%}
```

### PlantUML 図(シーケンス図・状態遷移図など)

PlantUML はソースだけを Git 管理し、SVG への変換はビルドに任せます。

1. ソースを `assets/diagrams/<name>.puml` に置く。
2. Markdown からは**変換後のパス** `/build/diagrams/<name>.svg` を画像参照する(`<name>` はソースと同名)。

```markdown
![在庫引当作成の処理シーケンス](/build/diagrams/reservation-sequence.svg){width=75%}
```

ビルドは参照からソースを名前の 1:1 対応で逆引きし、変更のあった図だけを自動変換します。**生成された SVG をコミットしてはいけません**。`.puml` を直接画像参照すると lint がエラーで止めます。

一度ビルドすれば参照先の SVG が実在するため、VS Code 標準の Markdown プレビューでも図が表示されます(clone 直後や `make clean` 直後はビルドするまで壊れた画像アイコンになりますが異常ではありません)。`.puml` の執筆には PlantUML 拡張(jebbs.plantuml。`.vscode/extensions.json` に推奨登録済み)のサイドプレビューが便利です。

図中フォント・配色などの共通デザインは `template/plantuml.config` が全図に適用されます。個々の図に固有の `skinparam` は各 `.puml` に書いてかまいません。実例は `examples/sample-spec/` にあります: `04-api-spec.md` + `assets/diagrams/reservation-sequence.puml`(シーケンス図)、`03-requirements.md` + `assets/diagrams/reservation-states.puml`(状態遷移図)。

## メタデータ(YAML フロントマター)

文書の先頭(章別ファイル分割では `00-meta.md` のみ)に書きます。

| キー | 必須 | 内容 |
| --- | --- | --- |
| `title` | 必須 | 文書タイトル。表紙と各ページのヘッダに表示。欠落は lint エラー |
| `subtitle` | 任意 | 副題。表紙のタイトル下に表示 |
| `docnumber` | 任意 | 文書番号。表紙とヘッダ右端に表示 |
| `version` | 任意 | 版数。表紙の書誌情報に表示 |
| `date` | 任意 | 発行日。表紙の書誌情報に表示 |
| `author` | 任意 | 作成者。表紙の書誌情報と PDF メタデータに反映 |
| `organization` | 任意 | 組織名。表紙のタイトル上に表示 |
| `logo` | 任意 | 表紙ロゴ画像のルート絶対パス(例: `/assets/images/logo.png`)。高さは `spec.typ` の `logo-height`(12mm)固定。存在しないパスは lint エラー |
| `revisions` | 任意 | 改訂履歴の配列。別ファイル化を推奨(次節参照) |

記入例:

```yaml
---
title: "在庫管理API 仕様書"
subtitle: "REST API 設計仕様"
docnumber: "SPEC-2026-001"
version: "1.2"
date: "2026-07-14"
author: "山田太郎"
organization: "株式会社サンプル"
---
```

## 改訂履歴の別ファイル化

改訂履歴が長くなったら、フロントマターの `revisions` から別ファイルへ切り出せます。**置くだけで Makefile が自動検出**し、pandoc の `--metadata-file` に反映します。

推奨は Markdown パイプ表です。ファイル名は単一ファイルなら `docs/<name>.revisions.md`、章別ファイル分割なら `docs/<name>/revisions.md` です。列は「版数|日付|作成者|改訂内容」の 4 列固定、1 改訂 = 1 行で、セル内に生の `|` は書けません(列数不一致はエラーで停止します)。

```markdown
| 版数 | 日付 | 作成者 | 改訂内容 |
|---|---|---|---|
| 1.0 | 2026-05-01 | 山田太郎 | 初版作成 |
| 1.1 | 2026-06-10 | 鈴木花子 | 3.2 節の表記を修正 |
```

代替として YAML 形式(`docs/<name>.revisions.yaml` / `docs/<name>/revisions.yaml`。トップレベルに `revisions:` 配列)も使えます。

注意点が 2 つあります。

- **`.revisions.md` と `.revisions.yaml` の両方を置くとビルドエラー**で停止します。どちらか一方だけにしてください。
- Pandoc の合成規則では**フロントマター側の `revisions` が別ファイル側を常に上書き**します。`revisions` はフロントマター・別ファイルのどちらか 1 箇所にのみ書いてください(推奨: 別ファイル)。

実例: `examples/wareki-api-spec.md` + `examples/wareki-api-spec.revisions.md`。

## エスケープハッチ(生 Typst)

Markdown で表現できないものに限り、` ```{=typst} ` フェンスで生 Typst を書けます。

- **使ってよい**: セル結合など、Markdown 標準の記法では原理的に表現できないもの。
- **使うべきでない**: 見た目の微調整、Markdown で書ける内容。それは `template/spec.typ` の show/set ルールを直すべき事案です。

生 Typst ブロック内では `spec.typ` の色定数(`accent-color` など)・フォント定数・ヘルパー関数をそのまま参照できます(`template/template.typ` が `#import "/template/spec.typ": *` しているため)。表を生 Typst で書く場合も、罫線・ヘッダ網掛けは `spec.typ` が自動適用するので、素直に `#table(...)` を書けば十分です。

## よく使う生 Typst レシピ

### 相互参照

見出しに `{#sec-id}` で ID を付け、本文からインライン生 Typst で参照します。

```markdown
## 引当仕様 {#sec-reservation}

詳細は `@sec-reservation`{=typst} を参照。
```

参照は「1章」「1.1節」「1.1.1項」形式の番号付きリンクになります。番号を表示しない見出し(H4 以降と `{.unnumbered}`)への参照は、見出しテキストそのもののリンクになります。

図は画像の属性に `{#fig-id}` を、表はキャプション行の末尾に `{#tbl-id}` を付けます。参照はどちらも同じ `` `@...`{=typst} `` です。

```markdown
![処理シーケンス](/build/diagrams/reservation-sequence.svg){#fig-seq width=75%}

: 引数一覧 {#tbl-args}

図は `@fig-seq`{=typst}、引数は `@tbl-args`{=typst} を参照。
```

「図 1」「表 1」形式の番号付きリンクになります。

### 改ページ

````markdown
```{=typst}
#pagebreak()
```
````

章(H1)は自動で改ページされるため、これは章の途中で区切りたい場合の手段です。

### 横向きページ

幅の広い表などを 1 ページだけ横向きにします。ブロックの中身は Markdown ではなく Typst 記法で書く必要があります。

````markdown
```{=typst}
#page(flipped: true)[
  #table(
    columns: (auto, auto, auto),
    table.header([列1], [列2], [列3]),
    [a], [b], [c],
  )
]
```
````

### セル結合

`table.cell(colspan: N)` / `table.cell(rowspan: N)` を使います。実例は `examples/sample-spec/99-appendix.md` と `examples/wareki-api-spec.md` の付録にあります。

````markdown
```{=typst}
#figure(
  table(
    columns: (20%, 30%, 50%),
    table.header([倉庫], [ロケーション], [備考]),
    table.hline(),
    table.cell(rowspan: 2)[第1倉庫],
    [WH1-A-001], [棚卸差異あり],
    [WH1-A-002], [差異なし],
  ),
  caption: [棚卸差異一覧],
  kind: table,
)
```
````

## 執筆中の確認

保存のたびに仕上がりを確認するには `make watch SRC=docs/<name>.md` を使います(章別ファイル分割なら `SRC` にディレクトリを指定)。詳しくは [README](../README.md) の「執筆中の自動更新とプレビュー」を参照してください。

提出前には `make lint` と対象文書の `make pdf` を実行し、最終的な見た目は `build/<name>.pdf` で確認してください。
