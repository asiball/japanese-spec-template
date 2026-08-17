// =============================================================================
// template.typ — Pandoc 用 Typst テンプレート
//
// メタデータを spec.typ の `spec-doc` へ橋渡しするだけで、見た目の定義は
// 一切書かない(すべて spec.typ に一元化)。horizontalrule などの補助定義は
// `pandoc -D typst` のデフォルトテンプレート由来で、Pandoc の Typst ライター
// が前提とするため保持している。
// -----------------------------------------------------------------------------

#let horizontalrule = line(start: (25%, 0%), end: (75%, 0%))

$if(highlighting-definitions)$
// syntax highlighting functions from skylighting:
$highlighting-definitions$

$endif$
#import "/template/spec.typ": *

$if(smart)$
$else$
#set smartquote(enabled: false)

$endif$
$for(header-includes)$
$header-includes$

$endfor$
#show: doc => spec-doc(
$if(title)$
  title: [$title$],
$endif$
$if(subtitle)$
  subtitle: [$subtitle$],
$endif$
$if(docnumber)$
  docnumber: [$docnumber$],
$endif$
$if(version)$
  version: [$version$],
$endif$
$if(date)$
  date: [$date$],
$endif$
$if(author)$
  author: [$author$],
$endif$
$if(organization)$
  organization: [$organization$],
$endif$
$if(logo)$
  logo: content-to-string([$logo$]),
$endif$
$if(revisions)$
  revisions: (
$for(revisions)$
    (
      version: [$revisions.version$],
      date: [$revisions.date$],
      author: [$revisions.author$],
      changes: [$revisions.changes$],
    ),
$endfor$
  ),
$endif$
  doc,
)

$for(include-before)$
$include-before$

$endfor$
$body$

$if(citations)$
$for(nocite-ids)$
#cite(label("${it}"), form: none)
$endfor$
$if(csl)$

#set bibliography(style: "$csl$")
$elseif(bibliographystyle)$

#set bibliography(style: "$bibliographystyle$")
$endif$
$if(bibliography)$

#bibliography(($for(bibliography)$"$bibliography$"$sep$,$endfor$)$if(full-bibliography)$, full: true$endif$)
$endif$
$endif$
$for(include-after)$

$include-after$
$endfor$
