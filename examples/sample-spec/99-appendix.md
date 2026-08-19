# 付録A: エスケープハッチの例 {.unnumbered}

本付録は、本 API の仕様そのものに加えて、本テンプレート（`japanese-spec-template`）が提供する生 Typst 記法（エスケープハッチ）のデモを兼ねる。本文の内容として必須ではないが、実例として本書に残している。

本書はほとんどの内容を素の Markdown で記述しているが、セル結合を伴う表など Markdown 標準の記法では表現できない場合に限り、Pandoc の生 Typst 記法（`` ```{=typst} `` フェンス）を用いてよい。乱用は禁物であり、あくまで最終手段として使うこと。

次の表は、ロケーション別の棚卸結果をセル結合で表現した例である。

```{=typst}
#figure(
  table(
    columns: (15%, 20%, 12%, 53%),
    align: (center + horizon, center + horizon, center + horizon, left + horizon),
    table.header([倉庫], [ロケーション], [差異数], [備考]),
    table.hline(),
    table.cell(rowspan: 2)[第1倉庫],
    [WH1-A-001], [-2], [棚卸時に破損品を発見],
    [WH1-A-002], [0], [差異なし],
    table.cell(rowspan: 2)[第2倉庫],
    [WH2-B-014], [+5], [入庫未登録分を確認],
    [WH2-B-015], [-1], [所在不明],
  ),
  caption: [棚卸差異一覧（ロケーション別）],
  kind: table,
)
```

上記のように、生 Typst ブロック内では `table.cell(rowspan: ...)` によるセル結合のみを書けばよく、罫線やヘッダの配色といった見た目は `spec.typ` の `show table: ...` が自動的に適用する。これは `template/template.typ` が `#import "/template/spec.typ": *` によってテーマの定義一式を取り込んでいるためであり、色定数（`accent-color` など）やヘルパー関数も必要であればそのまま参照できる。
