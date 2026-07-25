#!/bin/sh
# =============================================================================
# scripts/revisions-md2yaml.sh — 改訂履歴の Markdown パイプ表を YAML に変換する
#
# 使い方: sh scripts/revisions-md2yaml.sh docs/<name>.revisions.md > out.yaml
# 入力:   「版数|日付|作成者|改訂内容」の 4 列固定のパイプ表(1 改訂 = 1 行)
# 出力:   pandoc の --metadata-file に渡せる revisions: 配列の YAML(標準出力)
#
# パース規則:
#   - 最初の表行はヘッダとして読み飛ばす(列名は任意)。区切り行も読み飛ばす
#   - 4 列でない行は「ファイル名:行番号」付きのエラーで exit 1。セル内に
#     生の `|` は使えない(エスケープ記法は未対応。README 参照)
#   - `|` で始まらない非空行は警告して無視する
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
BEGIN { nrows = 0; seen_header = 0; err = 0 }
{
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
	if (sep) next
	if (!seen_header) { seen_header = 1; next }
	if (n != 4) {
		printf "ERROR: %s:%d: 改訂履歴の表の行は 4 列(版数|日付|作成者|改訂内容)である必要があります(%d 列でした)。セル内に生の | は使えません: %s\n", fname, NR, n, t > "/dev/stderr"
		err = 1
		exit 1
	}
	nrows++
	row_v[nrows] = yesc(trim(c[1]))
	row_d[nrows] = yesc(trim(c[2]))
	row_a[nrows] = yesc(trim(c[3]))
	row_c[nrows] = yesc(trim(c[4]))
}
END {
	if (err) exit 1
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
