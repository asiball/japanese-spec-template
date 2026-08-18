#!/bin/sh
# =============================================================================
# scripts/list-diagram-refs.sh — Markdown が参照する PlantUML 変換図を列挙する
#
# 使い方:
#   scripts/list-diagram-refs.sh file.md...
#
# 引数の Markdown から `](/build/diagrams/<name>.svg` 形式の画像参照を抽出
# し、ルートの `/` を除いたパス(build/diagrams/<name>.svg)を 1 行 1 件・
# 重複排除して出力する。Makefile がこのパスから <name> の 1:1 対応で
# assets/diagrams/<name>.puml を逆引きし、ビルド対象の文書が参照する図だけを
# 変換対象にする。
#
# コードフェンス(``` / ~~~)の中は除外する(記法の説明として書かれた参照
# 例を実参照と誤認すると、存在しないソースの変換を要求してしまうため)。
# =============================================================================
set -eu

# 引数なしだと awk が標準入力の到着を待ち続けて固まる(呼び出し元 Makefile
# の SRC 未指定時の防御と二重になるが、直接呼び出しからも守る)。
[ "$#" -eq 0 ] && exit 0

awk '
	# 複数ファイルを連続処理するため、各ファイルの先頭で判定状態をリセット
	# する(前の章ファイルが閉じないフェンスやリストで終わっていても、
	# 後続ファイルの図参照の抽出に影響させない。lint.sh のファイル単位の
	# 初期化と同じ)。
	FNR == 1 { in_fence = 0; fence_char = ""; fence_len = 0; list_mode = 0 }
	# CommonMark はフェンス文字の行頭連続数(run 長)で開始・終了を判定する。
	# 3 文字一致だけで見ると、4 バッククォート以上のフェンス内に ``` が
	# 現れたときに誤って閉じてしまう(lint.sh と同じ判定仕様)。
	function fence_run(s,    c, n) {
		c = substr(s, 1, 1)
		n = 0
		while (substr(s, n + 1, 1) == c) n++
		return n
	}
	{
		# フェンス判定は行頭の引用符号・空白を落としてから行う(リスト項目や
		# 引用の中に書かれたフェンスも認識するため。lint.sh と同じ判定仕様)。
		marker = $0
		sub(/\r$/, "", marker)
		indent = 0
		while (1) {
			mc = substr(marker, 1, 1)
			if (mc == " ") { indent++; marker = substr(marker, 2) }
			else if (mc == "\t") { indent += 4; marker = substr(marker, 2) }
			else if (mc == ">") { indent = 0; marker = substr(marker, 2) }
			else break
		}
		# リスト文脈を追跡し、リスト外の 4 桁以上の字下げはインデントコード
		# ブロックとしてフェンス扱いしない(インデントコード内の ``` を
		# フェンス開始と誤認すると、以降の図参照の抽出が無言で欠落する)。
		# インデントコードの中身はリスト文脈の更新にも使わない(コード内の
		# 「- 」行で文脈が誤って立つのを防ぐ)。lint.sh と同じ判定仕様。
		if (indent >= 4 && list_mode == 0) {
			marker = ""
		} else if (in_fence == 0) {
			if (marker ~ /^([-*+] |[0-9][0-9]?[.)] )/) list_mode = 1
			else if (indent == 0 && marker != "") list_mode = 0
		}
		c = substr(marker, 1, 1)
		if (c == "`" || c == "~") {
			n = fence_run(marker)
			if (n >= 3) {
				if (in_fence == 0) {
					in_fence = 1
					fence_char = c
					fence_len = n
					next
				}
				rest = substr(marker, n + 1)
				gsub(/[ \t]/, "", rest)
				if (c == fence_char && n >= fence_len && rest == "") {
					in_fence = 0
					next
				}
			}
		}
	}
	in_fence { next }
	{
		line = $0
		# インラインコード内の記法説明を実参照と誤認しない(2 連スパン →
		# 1 連スパンの順に落とす。lint.sh と同じ近似)。
		gsub(/``[^`]*``/, "", line)
		gsub(/`[^`]*`/, "", line)
		while (match(line, /\]\(\/build\/diagrams\/[^) ]+\.svg/)) {
			# マッチは "](/build/..." なので、先頭の "](" と "/" を除く
			print substr(line, RSTART + 3, RLENGTH - 3)
			line = substr(line, RSTART + RLENGTH)
		}
	}
' "$@" | sort -u
