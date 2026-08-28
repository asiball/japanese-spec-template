// =============================================================================
// spec.typ — 日本語仕様書テンプレートのテーマ本体
//
// 美観に関する責務はすべてこのファイルに集約する。Markdown / Pandoc 側は
// 構造(見出し・表・コードなど)のみを担当し、見た目はここで一元管理する。
//
// エントリポイントは `spec-doc` 関数。template/template.typ から
// `#show: spec-doc.with(...)` の形で呼び出される。
// =============================================================================

// ---- 配色 -------------------------------------------------------------
#let accent-color = rgb("#1f4e79") // 濃紺(アクセント)
#let accent-soft = rgb("#4a6d8c") // やや明るい濃紺(補助テキスト等)
#let rule-gray = rgb("#c9c9c9") // 罫線グレー
#let header-gray = rgb("#8a8a8a") // ヘッダ/フッタの淡いグレー
#let body-text-gray = rgb("#4d4d4d") // 引用文などの本文グレー
#let table-header-bg = rgb("#eef1f5") // 表ヘッダの薄グレー地
#let code-bg = luma(248) // コードブロック背景
#let code-border = luma(222) // コードブロック枠線

// ---- フォント -----------------------------------------------------------
#let font-serif = "Source Han Serif JP" // 本文(明朝)
#let font-sans = "Source Han Sans JP" // 見出し・表・UI 要素(ゴシック)
// 注意: フォント内部の name テーブルでは "Source Han Code JP R" が実際に
// マッチするファミリー名(Typst は "R"/"B" を weight として自動分離しない)。
#let font-code = "Source Han Code JP R" // コード(等幅)

// ---- レイアウト用のマジックナンバー(命名定数) --------------------------
// 表紙タイトルの折り返しヒューリスティック(cover-page で使用)。
#let title-shrink-threshold = 16 // この文字数を超えたら小さいサイズにする
#let title-size-large = 26pt // 閾値以下(短いタイトル)のフォントサイズ
#let title-size-small = 22pt // 閾値超(長いタイトル)のフォントサイズ

// 小書きかな直後の字送り補正量(spec-doc の strong ショウルールで使用)。
#let small-kana-correction = -0.12em

// コードブロックをページ境界での分割(breakable)に切り替える行数の閾値
// (spec-doc の raw ショウルールで使用)。この行数以下のブロックは分割せず
// 丸ごと次ページへ送る。
#let code-breakable-min-lines = 20

// 脚注セパレータ罫線の幅(spec-doc の footnote 設定で使用)。
#let footnote-separator-width = 30%

// 図表(figure)と前後の本文との間隔(spec-doc の figure ショウルールで使用)。
// 本文の段落間隔(0.85em)のままだと図表が本文に埋もれるため広めに取る。
#let figure-spacing = 1.6em

// 表紙ロゴの描画高さ(cover-page で使用。横幅はアスペクト比に応じて自動)。
#let logo-height = 12mm

// ---- 和文組版グリッド ----------------------------------------------------
// Typst 既定の top-edge(グリフ実測)のままだと、欧文・インラインコード混在行
// で行送りが変動する。okumuralab/typst-js(MIT-0)の cjkheight(0.88em)に
// ならい和文の仮想ボディ高に合わせることで行送りを一定にする。
// 行送り = top-edge(0.88em) + leading(0.85em) = 1.73em(jsarticle と同じ)
#let cjk-top-edge = 0.88em

// =============================================================================
// 内部ユーティリティ
// =============================================================================

// content を平文文字列に変換する(document() の author 等は str を要求するため。
// template.typ の logo 橋渡しでも使う: Pandoc の変数展開はマークアップ用
// エスケープ(`_` → `\_` 等)を含むため、パスを文字列リテラルで受けると壊れる)
#let content-to-string(content) = {
  if type(content) == str {
    content
  } else if content.has("text") {
    content.text
  } else if content.has("children") {
    content.children.map(content-to-string).join("")
  } else if content.has("body") {
    content-to-string(content.body)
  } else if content == [ ] {
    " "
  } else {
    ""
  }
}

// 表紙・改訂履歴などで使う細い罫線
#let thin-rule(width: 100%, weight: 0.6pt, color: rule-gray) = {
  line(length: width, stroke: weight + color)
}

// 章(H1)扉に使う太めの濃紺罫線
#let accent-rule(width: 100%, weight: 1.1pt) = {
  line(length: width, stroke: weight + accent-color)
}

// Markdown の fenced div(`::: info` 等)から Lua フィルター経由で
// 呼び出す注記ボックス。色だけに依存せず、種類名も常に表示する。
#let admonition(kind: "info", body) = {
  let border-color = if kind == "warning" {
    rgb("#a06400")
  } else if kind == "error" {
    rgb("#a23434")
  } else {
    accent-color
  }
  let background-color = if kind == "warning" {
    rgb("#fff8e8")
  } else if kind == "error" {
    rgb("#fff2f2")
  } else {
    rgb("#f2f7fb")
  }
  let label = if kind == "warning" {
    [注意]
  } else if kind == "error" {
    [エラー]
  } else {
    [情報]
  }

  block(
    width: 100%,
    above: 1em,
    below: 1em,
    inset: (left: 1em, right: 1em, top: 0.75em, bottom: 0.75em),
    stroke: (left: 3pt + border-color),
    fill: background-color,
    breakable: true,
  )[
    #set par(first-line-indent: 0em, spacing: 0.55em)
    #block(below: 0.4em)[
      #text(font: font-sans, size: 9.5pt, weight: "bold", fill: border-color)[#label]
    ]
    #body
  ]
}

// =============================================================================
// 表紙
// =============================================================================
// logo はロゴ画像のパス文字列(ルート絶対パス。例: "/assets/logo.png")。
// 描画高さは logo-height で一元管理する(見た目の責務を spec.typ に集約)。
#let cover-page(
  title: none,
  subtitle: none,
  docnumber: none,
  version: none,
  date: none,
  author: none,
  organization: none,
  logo: none,
) = {
  // 上部: ページ物理上端に全幅で貼り付くブリード帯(余白の外、紙面の最上端)。
  set page(
    numbering: none,
    header: none,
    footer: none,
    background: place(top, rect(width: 100%, height: 8mm, fill: accent-color, inset: 0pt, outset: 0pt)),
  )

  v(1fr)

  // タイトル文字数に応じたフォントサイズ(長いタイトルの折り返しで
  // 1 文字だけが孤立する「泣き別れ」を軽減するヒューリスティック)
  let title-len = if title != none { content-to-string(title).clusters().len() } else { 0 }
  let title-size = if title-len > title-shrink-threshold { title-size-small } else { title-size-large }

  // タイトルブロック(中央。ページのやや上(光学中心)に来るよう、
  // 前後の v(1fr) / v(1.4fr) で余白配分を調整している)
  align(center)[
    #if logo != none {
      block(below: 1.2em)[#image(logo, height: logo-height)]
    }
    #if organization != none {
      block(below: 2em)[
        #set text(font: font-sans, size: 11pt, fill: accent-soft, weight: "medium")
        #organization
      ]
    }
    #block(below: 0.9em)[
      #set par(justify: false, linebreaks: "optimized", leading: 0.45em)
      #set text(font: font-sans, size: title-size, weight: "bold")
      #title
    ]
    #if subtitle != none {
      block(below: 1em)[
        #set text(font: font-sans, size: 14pt, weight: "medium", fill: accent-soft)
        #subtitle
      ]
    }
  ]

  v(1.4fr)

  // 下部の書誌情報(整列テーブル)
  let info-rows = ()
  if docnumber != none { info-rows.push(([文書番号], [#docnumber])) }
  if version != none { info-rows.push(([版数], [#version])) }
  if date != none { info-rows.push(([発行日], [#date])) }
  if author != none { info-rows.push(([作成者], [#author])) }

  align(center)[
    #block(width: 80%)[
      #thin-rule(weight: 0.8pt)
      #v(0.9em)
      #set text(font: font-sans, size: 10pt)
      #grid(
        columns: (1fr, 1fr),
        inset: (x: 4pt, y: 5pt),
        align: (left, left),
        ..info-rows.flatten()
      )
    ]
  ]

  v(12mm)
  accent-rule(weight: 1.4pt)
  v(4mm)
}

// =============================================================================
// 改訂履歴
// =============================================================================
#let revision-history(revisions: ()) = {
  if revisions.len() > 0 {
    heading(level: 1, numbering: none, outlined: false)[改訂履歴]
    v(0.4em)
    set text(font: font-sans, size: 9pt)
    table(
      columns: (10%, 18%, 22%, 50%),
      stroke: none,
      inset: (x: 8pt, y: 7pt),
      align: (center + horizon, center + horizon, center + horizon, left + horizon),
      table.header([版数], [日付], [作成者], [改訂内容]),
      table.hline(),
      ..revisions
        .map(r => (
          [#r.version],
          [#r.date],
          [#r.author],
          [#r.changes],
        ))
        .flatten()
    )
  }
}

// =============================================================================
// ヘッダ・フッタ(本文用)
// =============================================================================
#let doc-header(title: none, docnumber: none) = {
  context {
    // H1 の章扉は見出し自体で十分に文書を識別できるため、
    // ヘッダを隠して章の開始を明確にする。改訂履歴・目次の
    // outlined: false の H1 は通常のヘッダを保つ。
    let page-number = here().page()
    let is-chapter-page = query(heading.where(level: 1, outlined: true))
      .any(it => it.location().page() == page-number)

    if not is-chapter-page {
      set text(font: font-sans, size: 8pt, fill: header-gray)
      grid(
        columns: (1fr, auto),
        align: (left + horizon, right + horizon),
        [#title],
        [#if docnumber != none [#docnumber]],
      )
      v(-0.35em)
      thin-rule(weight: 0.5pt, color: rule-gray)
    }
  }
}

#let doc-footer() = context {
  set align(center)
  set text(font: font-sans, size: 8.5pt, fill: header-gray)
  [#counter(page).display("1") / #counter(page).final().first()]
}

// =============================================================================
// spec-doc: メインエントリポイント
// =============================================================================
#let spec-doc(
  title: none,
  subtitle: none,
  docnumber: none,
  version: none,
  date: none,
  author: none,
  organization: none,
  logo: none,
  revisions: (),
  body,
) = {
  // ---- 文書メタデータ(date は決定的ビルドのため常に none) ----
  set document(
    title: if title != none { title } else { none },
    author: if author != none { (content-to-string(author),) } else { () },
    // 既定の auto はビルド時刻を PDF に埋め込み、同一入力でもバイト単位で
    // 一致しなくなるため明示的に none にする。
    date: none,
  )

  // ---- 基本ページ設定 ----
  set page(
    paper: "a4",
    margin: (top: 30mm, bottom: 30mm, left: 25mm, right: 25mm),
    // フッタ(ページ番号)の位置。Typst 既定の 30% では Word の慣行より数 mm
    // 高い位置に出るため、下余白 30mm の 40%(本文下端から 12mm)まで下げて
    // 日本語版 Word の既定(下からのフッタ位置 17.5mm)相当に合わせている。
    footer-descent: 40%,
  )

  // ---- 基本文字設定(本文は明朝) ----
  set text(
    lang: "ja",
    region: "JP",
    font: font-serif,
    size: 10pt,
    cjk-latin-spacing: auto,
    top-edge: cjk-top-edge,
  )
  set par(
    justify: true,
    leading: 0.85em,
    spacing: 0.85em,
    first-line-indent: (amount: 1em, all: true),
  )

  // ---- 見出し番号: レベル3まで "1.1.1." ----
  // 見出し本文と番号の境界を和文中でも読み取りやすくするため、
  // 各レベルの番号末尾にピリオドを付ける。
  set heading(numbering: (..nums) => numbering("1.1.1.", ..nums) + h(0.25em))

  // ---- 相互参照 ----
  // 見出しへの @ラベル 参照を「1章」「1.1節」「1.1.1項」の和文順で表記する
  // (既定は supplement が先に付く「節 1.1」の英文順で、章・節・項の区別も
  // ない)。番号を表示しない見出し(H4 以降の小見出しと {.unnumbered})は
  // 見出しテキストのリンクにする(既定挙動は前者に本文に表示されない番号を
  // 与え、後者を「cannot reference heading without numbering」のコンパイル
  // エラーにしてしまうため、どちらも自前で描画する)。
  show ref: it => {
    let el = it.element
    if el != none and el.func() == heading {
      if el.numbering != none and el.level <= 3 {
        // 見出しの表示用ピリオドは「1章」などの参照文字列には
        // 含めない。
        let nums = numbering("1.1.1", ..counter(heading).at(el.location()))
        let unit = if el.level == 1 { "章" } else if el.level == 2 { "節" } else { "項" }
        link(el.location())[#nums#unit]
      } else {
        link(el.location(), el.body)
      }
    } else {
      it
    }
  }

  // ---- リンク(濃紺・下線なし。Typst のリンクは既定で下線なし) ----
  show link: set text(fill: accent-color)

  // ---- 強調 ----
  // 小書きかな(「ゃ」等)は字送りの右側に空きが大きいグリフ設計のため、
  // 小書きかなで終わる強調の直後に半角記号が続くと不自然な空白が生じる。
  // 該当パターンの直後だけ字送りを詰めて補正する。
  let small-kana-tail = "ぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮ"
  show strong: it => {
    let styled = text(weight: "bold", it.body)
    let s = content-to-string(it.body)
    if s.len() > 0 and small-kana-tail.contains(s.last()) {
      box[#styled#h(small-kana-correction)]
    } else {
      styled
    }
  }

  // ---- 強調(斜体) ----
  // 同梱フォントにイタリック体がないため斜体が直立体にフォールバックし、
  // 見た目の変化なく静かに消えてしまう。和文の慣行に合わせ、emph は
  // ゴシック体(直立)で表現する。
  show emph: it => text(font: font-sans, style: "normal", it.body)

  // ---- 引用(blockquote) ----
  show quote.where(block: true): it => block(
    width: 100%,
    inset: (left: 1.1em, top: 0.5em, bottom: 0.5em, right: 0.6em),
    stroke: (left: 2pt + accent-soft),
    fill: luma(250),
  )[
    #set text(fill: body-text-gray, style: "normal")
    #it.body
  ]

  // ---- リスト ----
  set list(marker: ([•], [–]), indent: 0.3em, spacing: 0.65em)
  set enum(indent: 0.3em, spacing: 0.65em)

  // ---- 定義リスト(Markdown の "Term\n: Description" 記法) ----
  // 太字の用語 + インデントされた説明(Pandoc の既定テンプレート由来の装飾)。
  show terms.item: it => block(breakable: false)[
    #text(weight: "bold")[#it.term]
    #block(inset: (left: 1.5em, top: -0.4em))[#it.description]
  ]

  // ---- コードブロック(等幅フォント・低彩度シンタックスハイライト) ----
  // 既定のハイライト配色は彩度が高く紙面から浮くため、低彩度の独自テーマに
  // 差し替える(--root . 前提のルート相対パス。背景はテーマではなく下記
  // block の code-bg で描画する)。
  set raw(theme: "/assets/typst-highlight.tmTheme")
  show raw: set text(font: font-code)

  // 短いコードブロックはページ境界で分割せず丸ごと次ページへ送る
  // (ページ末尾に上枠だけの空断片が残るのを防ぐ)。長いものだけ分割を許可する。
  show raw.where(block: true): it => block(
    width: 100%,
    fill: code-bg,
    stroke: 0.6pt + code-border,
    radius: 2pt,
    inset: 8pt,
    breakable: it.text.split("\n").len() > code-breakable-min-lines,
  )[
    #set text(size: 8.5pt)
    #set par(justify: false, leading: 0.72em)
    #it
  ]

  // インラインコードには極細のボーダーを付ける(引用ブロックなど背景色を
  // 持つ領域の上でも輪郭で判別できるようにするため)。
  show raw.where(block: false): box.with(
    fill: code-bg,
    stroke: 0.4pt + luma(225),
    outset: (y: 2.5pt),
    inset: (x: 3pt),
    radius: 2pt,
  )

  // ---- 表 ----
  // ヘッダ行の網掛けは show/set table.cell(fill:) では反映されないため、
  // table 自体の fill を位置関数で与える。
  set table(
    stroke: none,
    inset: (x: 8pt, y: 8pt),
    fill: (x, y) => if y == 0 { table-header-bg } else { none },
  )
  show table.cell.where(y: 0): set text(font: font-sans, weight: "bold")
  // Pandoc は表を align(center) で包んで出力するため、放置するとセル内容が
  // 中央揃えを継承する。既定は左揃え+垂直中央とする(Markdown 側で明示した
  // 列揃えは table の align 引数が優先されるため保持される)。
  show table.cell: set align(start + horizon)
  // セル内は行長が短く両端揃え(justify)の恩恵がない一方、折り返し時に
  // 字間が不自然に広がったり記号だけが右端へ押し出されたりするため、
  // 表の中に限り左揃え(なりゆき)にする。
  show table: set par(justify: false)
  show table: set text(size: 9pt)
  // 本文用の top-edge(0.88em)のままだと表の行高が間延びするため、typst-js
  // の補正(2 × cjkheight − 1 = 0.76em)にならい表セル内だけ詰める。
  show table: set text(top-edge: 0.76em)
  show table: it => block(
    stroke: (top: 1.1pt + accent-color, bottom: 1.1pt + accent-color),
    inset: 0pt,
    it,
  )
  show table.hline: set line(stroke: 0.6pt + rule-gray)

  // キャプションは「表 1 キャプション文」の形式(Word の図表番号と同じ
  // 見た目。Typst 既定の「表 1: キャプション文」からコロンを除く)。
  set figure.caption(separator: h(0.5em))
  show figure.where(kind: table): set figure.caption(position: top)
  show figure.where(kind: image): set figure.caption(position: bottom)
  show figure.caption: set text(font: font-sans, size: 9pt)

  // 図表と前後の本文との間隔。キャプション(図表タイトル)も figure に
  // 含まれるため、キャプション側も同じ余白で本文から分離される。
  show figure: set block(above: figure-spacing, below: figure-spacing)

  // Pandoc は表を figure(kind: table)で包み、figure は既定で分割不可の
  // ため、1 ページに収まらない表はあふれた行が描画されずに消える。表のみ
  // 分割を許可する(継続ページのヘッダ行は table.header の繰り返しで再掲
  // され、上下のアクセント罫線も分割片ごとに描画される)。
  show figure.where(kind: table): set block(breakable: true)
  // 分割位置がキャプション(表は position: top)の直後に来ると、キャプション
  // だけが前ページ末尾に孤立するため、キャプションを直後の表本体に結合する。
  show figure.caption.where(position: top): it => block(sticky: true, it)

  // ---- 脚注 ----
  set footnote.entry(separator: thin-rule(width: footnote-separator-width, weight: 0.5pt))
  show footnote.entry: set text(size: 8.5pt)

  // ---- 見出しスタイル ----
  // H1: 章。ページを改め、太めの濃紺ルールを前後に配置する。
  show heading.where(level: 1): it => {
    if it.outlined {
      pagebreak(weak: true)
    }
    block(above: 0em, below: 1.5em, width: 100%)[
      #v(0.4em)
      #set text(font: font-sans, size: 16pt, weight: "bold")
      #it
      #v(0.6em)
      #accent-rule(weight: 1.1pt)
    ]
  }

  // H2: 節。左に太い濃紺バー。
  // breakable: false, sticky: true で見出しがページ最下部に孤立するのを防ぐ
  // (見出しの直後の内容が次ページに送られる場合、見出し自体も一緒に送られる)。
  show heading.where(level: 2): it => block(above: 1.4em, below: 0.75em, width: 100%, breakable: false, sticky: true)[
    #box(
      inset: (left: 0.85em, top: 0.3em, bottom: 0.3em, right: 0.3em),
      stroke: (left: 3pt + accent-color),
    )[
      #set text(font: font-sans, size: 12pt, weight: "bold")
      #it
    ]
  ]

  // H3: 項。
  show heading.where(level: 3): it => block(above: 1.15em, below: 0.6em, breakable: false, sticky: true)[
    #set text(font: font-sans, size: 10.5pt, weight: "bold")
    #it
  ]

  // H4 以降: 番号なしの小見出し(レベル 4/5/6 すべて同じ見た目)。
  let unnumbered-subheading(it) = block(above: 1.1em, below: 0.5em, breakable: false, sticky: true)[
    #set text(font: font-sans, size: 10pt, weight: "bold", style: "normal")
    #it.body
  ]
  show heading.where(level: 4): unnumbered-subheading
  show heading.where(level: 5): unnumbered-subheading
  show heading.where(level: 6): unnumbered-subheading

  // ---- 目次の見出し文字 ----
  // 章(level 1)は濃紺の太字、節・項は通常ウェイトにして
  // 項目数が多くても章の切れ目を追いやすくする。
  show outline.entry: it => {
    set text(font: font-sans)
    if it.level == 1 {
      v(0.75em, weak: true)
      set text(weight: "bold", fill: accent-color)
      it
    } else {
      set text(weight: "regular")
      it
    }
  }

  // ===========================================================================
  // 1. 表紙
  // ===========================================================================
  cover-page(
    title: title,
    subtitle: subtitle,
    docnumber: docnumber,
    version: version,
    date: date,
    author: author,
    organization: organization,
    logo: logo,
  )

  pagebreak()

  // ===========================================================================
  // 2. 改訂履歴 → 目次(それぞれ独立したページ。2ページ目以降はヘッダのみ
  //    表示、フッタは非表示)
  // ===========================================================================
  set page(
    header: doc-header(title: title, docnumber: docnumber),
    footer: none,
    numbering: none,
  )

  revision-history(revisions: revisions)

  // 改訂履歴と目次を同居させると、どちらかが伸びたときに読みにくくなるため
  // ページを分ける(改訂履歴が無い場合は目次が最初のページに来る)。
  if revisions.len() > 0 {
    pagebreak()
  }

  heading(level: 1, numbering: none, outlined: false)[目次]
  v(0.4em)
  outline(title: none, depth: 3, indent: auto)

  pagebreak()

  // ===========================================================================
  // 3. 本文(ページ番号を 1 から起算)
  // ===========================================================================
  counter(page).update(1)
  set page(
    header: doc-header(title: title, docnumber: docnumber),
    footer: doc-footer(),
    numbering: "1",
  )

  body
}
