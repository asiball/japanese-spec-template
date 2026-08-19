#!/bin/sh
# =============================================================================
# scripts/revisions-md2yaml.sh — 改訂履歴の Markdown パイプ表を YAML に変換する
#
# 使い方: sh scripts/revisions-md2yaml.sh docs/<name>.revisions.md > out.yaml
# 入力:   「版数|日付|作成者|改訂内容」の 4 列固定のパイプ表(1 改訂 = 1 行)
# 出力:   pandoc の --metadata-file に渡せる revisions: 配列の YAML(標準出力)
#
# パース規則:
#   - 区切り行(|---|---|---|---|)は表の 2 行目に置かれた場合のみ区切りとして
#     扱い、その直前の行(1 行目)をヘッダとして読み飛ばす(列名は任意)。
#     3 行目以降の全セルがダッシュの行はデータ行として扱う(空欄をダッシュで
#     埋めた改訂行を区切り行と誤認して無言で捨てないため)
#   - 区切り行が見つからない場合はエラーで exit 1(ヘッダの書き忘れを最初の
#     改訂行の無言消失として扱わないため。改訂履歴は監査対象になりうる)
#   - 4 列でない行は「ファイル名:行番号」付きのエラーで exit 1。セル内に
#     生の `|` は使えない(エスケープ記法は未対応。guides/WRITING.md 参照)
#   - `|` で始まらない非空行は警告して無視する。行末の CR(CRLF 改行)は
#     読み込み時に落とす(lint.sh と同じ Windows エディタ対応)
#   - YAML 出力(ダブルクォート文字列)では `\` と `"` をエスケープする
# =============================================================================
set -eu

if [ "$#" -ne 1 ]; then
	echo "usage: sh scripts/revisions-md2yaml.sh docs/<name>.revisions.md > build/obj/<name>.revisions.yaml" >&2
	exit 2
fi

f=$1
if [ ! -f "$f" ]; then
	echo "ERROR: $f が見つかりません。" >&2
	exit 1
fi

awk -v fname="$f" '
function trim(s) { gsub(/^[ \t]+/, "", s); gsub(/[ \t]+$/, "", s); return s }
function yesc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
BEGIN { nrows = 0; tlines = 0; seen_sep = 0; err = 0 }
{
	sub(/\r$/, "")
	t = trim($0)
	if (t == "") next
	if (substr(t, 1, 1) != "|") {
		printf "WARNING: %s:%d: 表以外の行を無視します: %s\n", fname, NR, t > "/dev/stderr"
		next
	}
	s = t
	sub(/^\|/, "", s)
	sub(/\|[ \t]*$/, "", s)
	n = split(s, c, "|")
	sep = (n > 0)
	for (i = 1; i <= n; i++) {
		if (trim(c[i]) !~ /^:?-+:?$/) { sep = 0; break }
	}
	# 区切り行として扱うのはヘッダ直後(表の 2 行目まで)に現れた場合のみ
	# (それ以降の全セルがダッシュの行は、空欄をダッシュで埋めたデータ行)。
	# 直前の行(ヘッダ)は保留から捨てる。
	if (sep && !seen_sep && tlines <= 1) {
		seen_sep = 1
		tlines = 0
		nrows = 0
		next
	}
	# ヘッダ候補(区切り行より前の 1 行目)は列数を検査しない(列名・列数は
	# 任意)。データ行は 4 列固定。
	if ((tlines > 0 || seen_sep) && n != 4) {
		printf "ERROR: %s:%d: 改訂履歴の表の行は 4 列(版数|日付|作成者|改訂内容)である必要があります(%d 列でした)。セル内に生の | は使えません: %s\n", fname, NR, n, t > "/dev/stderr"
		err = 1
		exit 1
	}
	tlines++
	if (n == 4) {
		nrows++
		row_v[nrows] = yesc(trim(c[1]))
		row_d[nrows] = yesc(trim(c[2]))
		row_a[nrows] = yesc(trim(c[3]))
		row_c[nrows] = yesc(trim(c[4]))
	}
}
END {
	if (err) exit 1
	if (!seen_sep && nrows > 0) {
		printf "ERROR: %s: 改訂履歴の表に区切り行(|---|---|---|---| の形式。ヘッダ行の直後)が見つかりません。ヘッダ行と区切り行を書いてください(guides/WRITING.md の「改訂履歴の別ファイル化」参照)。\n", fname > "/dev/stderr"
		exit 1
	}
	if (nrows == 0) {
		printf "WARNING: %s: 改訂履歴のデータ行が見つかりませんでした(ヘッダ行のみ?)。\n", fname > "/dev/stderr"
		print "revisions: []"
		exit 0
	}
	print "revisions:"
	for (i = 1; i <= nrows; i++) {
		printf "  - version: \"%s\"\n", row_v[i]
		printf "    date: \"%s\"\n", row_d[i]
		printf "    author: \"%s\"\n", row_a[i]
		printf "    changes: \"%s\"\n", row_c[i]
	}
}
' "$f"
