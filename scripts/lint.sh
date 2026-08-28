#!/bin/sh
# =============================================================================
# scripts/lint.sh — 仕様書 Markdown の簡易 lint
#
# 使い方:
#   scripts/lint.sh            docs/ と examples/ の *.md + 章別ファイル分割を全件検査
#   scripts/lint.sh file...    指定ファイルのみ検査(`make pdf` がビルド対象を渡す)
#
# モード判定: 親ディレクトリが docs / examples 以外、かつファイル名が
# [0-9][0-9]-*.md のものを章別ファイル分割として扱う(00-meta.md はメタ
# ファイル、それ以外は章ファイル)。残りはすべて単一ファイルモード。
#
# エラー(exit 1):
#   - フロントマターの title: 欠落・空(クォートのみの "" / '' も空扱い)。
#     単一ファイルと 00-meta.md が対象(表紙・ヘッダに title が必須)
#   - 章ファイルへのフロントマター混入(pandoc の連結時に後方ファイルが
#     前方を上書きし、00-meta.md の title 等が消えるため)
#   - 見出しの手動採番: `# 1. foo` / `## 2) foo` / `## 1.1. foo` / `## 1．foo` /
#     `## (1) foo` / `# 第1章 foo` / `# 1章 foo`
#     (Typst の自動採番と二重になるため。全ファイルが対象)
#   - PlantUML 参照の不備: .puml の直接画像参照(変換後の SVG を参照する
#     規約)、/build/diagrams/<name>.svg 形式(ルート絶対パス)でない図の
#     参照、参照 SVG に対応する assets/diagrams/<name>.puml の不存在
#     (いずれもビルド後半で分かりにくいエラーになるため早期に止める)
#   - /assets/ 配下の参照先ファイル(図版など)・フロントマターの logo: が
#     指す画像の不存在(同上)
#   - 注記ボックス(fenced div)のフェンス不一致: 閉じフェンス(:::)のない
#     開始フェンス(::: info 等)、開始フェンスのない閉じフェンス(pandoc は
#     div として認識せず、::: の行をそのまま本文として出力するため)
#
# 警告(exit 0。ビルドは継続):
#   - 見出しが数字で始まる(`## 2.5 系` 等。手動採番の疑いがあるだけの場合)
#   - 生 Typst ブロック内の装飾コード(見た目は spec.typ に一元化する方針)
#   - 章ファイル間の脚注定義 ID(`[^id]:`)の重複(pandoc の連結時に衝突する)
#   - 注記ボックスの種類が info / warning / error 以外(scripts/admonitions.lua
#     が変換せず、装飾なしのブロックとして出力される)、および ::: で始まるが
#     開始フェンスとして認識されない行(種類名の後に文字が続く等)
#
# コードフェンスの中身は誤検知を避けるためスキップする(```{=typst} の中身
# だけは装飾コード検出の対象)。改訂履歴ファイル(*.revisions.md /
# *.revisions.yaml / revisions.md / revisions.yaml)は仕様書本文ではないため
# 対象外。
#
# 行末の CR(CRLF 改行)は読み込み時に落とす。pandoc は CRLF をそのまま扱える
# ため、Windows のエディタが保存した原稿で lint だけが落ちる(フロントマター
# の --- が "---\r" になり検出できない)のを避ける。
# =============================================================================
set -eu

CR=$(printf '\r')
TAB=$(printf '\t')

# YAML のスカラー値から前後の空白とクォートを外す(`title: ""` のような
# クォートだけの空値も空と判定できるようにするため、クォートを外した後に
# もう一度空白を落とす)。
unquote() {
	printf '%s' "$1" \
		| sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
		| sed -E "s/^\"(.*)\"\$/\\1/; s/^'(.*)'\$/\\1/" \
		| sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

if [ "$#" -eq 0 ]; then
	# _ 始まりのファイル・ディレクトリは下書き・共有素材の置き場のため
	# 自動探索から除外する(make pdf-all と同じ規約。ビルド対象外のものを
	# lint だけが検査して CI を止めないようにする。引数で明示的に渡された
	# 場合は検査する)。
	set --
	for f in docs/*.md examples/*.md; do
		case "$f" in docs/_*|examples/_*) continue ;; esac
		set -- "$@" "$f"
	done
	for d in docs/*/ examples/*/; do
		[ -d "$d" ] || continue
		d=${d%/}
		case "$d" in docs/_*|examples/_*) continue ;; esac
		chapters=""
		for cf in "$d"/[0-9][0-9]-*.md; do
			[ -f "$cf" ] || continue
			chapters="$chapters $cf"
		done
		if [ -n "$chapters" ]; then
			set -- "$@" $chapters
		fi
	done
fi

found_error=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

for f in "$@"; do
	[ -f "$f" ] || continue
	case "$f" in
		*.revisions.md|*.revisions.yaml) continue ;;
	esac
	base=$(basename "$f")
	case "$base" in
		revisions.md|revisions.yaml) continue ;;
	esac

	parent_dir=$(dirname "$f")
	parent_name=$(basename "$parent_dir")
	# ファイル名パターンも条件に含める(親ディレクトリ名だけで判定すると
	# docs/ 外の単一ファイルを章ファイルと誤判定するため)。docs / examples
	# 直下は単一ファイル置き場なので章モードから除外する。
	is_chapter_mode=0
	if [ "$parent_name" != "docs" ] && [ "$parent_name" != "examples" ]; then
		case "$base" in
			[0-9][0-9]-*.md) is_chapter_mode=1 ;;
		esac
	fi

	if [ "$is_chapter_mode" -eq 1 ] && [ "$base" != "00-meta.md" ]; then
		# --- 章ファイル: フロントマター混入チェック ---
		first_line=$(head -n1 "$f" | tr -d "$CR" || true)
		if [ "$first_line" = "---" ]; then
			echo "ERROR: $f: 章ファイルの先頭に YAML フロントマター(---)が見つかりました。フロントマターは 00-meta.md にのみ書いてください(pandoc で複数ファイルを連結する際、後方ファイルのフロントマターが前方を上書きするため、章ファイルへの混入は意図しない上書き事故につながります)。" >&2
			found_error=1
		fi
	else
		# --- フロントマターの title: チェック(単一ファイルモード / 00-meta.md) ---
		first_line=$(head -n1 "$f" | tr -d "$CR" || true)
		if [ "$first_line" != "---" ]; then
			echo "ERROR: $f: YAML フロントマター(ファイル先頭の --- ブロック)が見つかりません(表紙・ヘッダに title が必要です)。" >&2
			found_error=1
		else
			fm_end_lineno=$(awk '{ sub(/\r$/, "") } NR>1 && $0=="---" {print NR; exit}' "$f")
			if [ -z "$fm_end_lineno" ]; then
				echo "ERROR: $f: YAML フロントマターの終端(---)が見つかりません(表紙・ヘッダに title が必要です)。" >&2
				found_error=1
			else
				title_value=$(awk -v end="$fm_end_lineno" '{ sub(/\r$/, "") } NR>1 && NR<end && $0 ~ /^title:[[:space:]]*/ {sub(/^title:[[:space:]]*/, ""); print; exit}' "$f")
				has_title=$(awk -v end="$fm_end_lineno" '{ sub(/\r$/, "") } NR>1 && NR<end && $0 ~ /^title:[[:space:]]*/ {print "1"; exit}' "$f")
				if [ -z "$has_title" ]; then
					echo "ERROR: $f: YAML フロントマターに title: が見つかりません(表紙・ヘッダに必要です)。" >&2
					found_error=1
				else
					unquoted_title=$(unquote "$title_value")
					if [ -z "$unquoted_title" ]; then
						echo "ERROR: $f: YAML フロントマターの title: の値が空です(表紙・ヘッダに必要です)。" >&2
						found_error=1
					fi
				fi

				# --- フロントマターの logo: の存在チェック ---
				# 表紙ロゴのパス誤りは typst compile まで進んでから分かりに
				# くいエラーになるため、画像・図の参照と同様に早期に止める。
				logo_value=$(awk -v end="$fm_end_lineno" '{ sub(/\r$/, "") } NR>1 && NR<end && $0 ~ /^logo:[[:space:]]*/ {sub(/^logo:[[:space:]]*/, ""); print; exit}' "$f")
				if [ -n "$logo_value" ]; then
					logo_path=$(unquote "$logo_value")
					case "$logo_path" in
						/*)
							if [ ! -f "${logo_path#/}" ]; then
								echo "ERROR: $f: フロントマターの logo: が指す画像が存在しません: $logo_path(リポジトリルートからの絶対パスで、実在するファイルを指定してください)。" >&2
								found_error=1
							fi
							;;
					esac
				fi
			fi
		fi
	fi

	in_fence=0
	fence_lang=""
	fence_marker=""
	fence_len=0
	list_mode=0
	lineno=0
	div_depth=0
	div_stack=""

	while IFS= read -r line || [ -n "$line" ]; do
		lineno=$((lineno + 1))
		line=${line%"$CR"}

		# フェンス判定は行頭の引用符号・空白を落としてから行う。CommonMark は
		# リスト項目や引用の中でもフェンスを開始でき(実際にインデントして
		# 書かれる)、桁 0 のフェンスしか認識しないと、記法の説明としてフェンス
		# 内に書いた図参照を実参照と誤検出してビルドを止めてしまう。
		marker=$line
		indent=0
		while :; do
			case $marker in
				' '*) indent=$((indent + 1)); marker=${marker#?} ;;
				"$TAB"*) indent=$((indent + 4)); marker=${marker#?} ;;
				'>'*) indent=0; marker=${marker#?} ;;
				*) break ;;
			esac
		done
		# リスト文脈を追跡する。リスト項目の内容(ネストした項目・項目内の
		# フェンス)は 4 桁以上に字下げされることがあり、これはインデント
		# コードブロックではない。一方リスト外の 4 桁以上はインデントコード
		# であり、その中の ``` をフェンス開始と誤認すると以降の全チェックが
		# 無言で無効化される。リスト外の 4 桁以上のみフェンス扱いを止める。
		# 判定の順序が重要: インデントコードの中身はリスト文脈の更新にも
		# 使わない(コード内の「- 」行でリスト文脈が誤って立つと、直後の
		# ``` がフェンス扱いされて同じ無効化が起きるため)。
		if [ "$indent" -ge 4 ] && [ "$list_mode" -eq 0 ]; then
			marker=""
		elif [ "$in_fence" -eq 0 ]; then
			case "$marker" in
				'- '*|'* '*|'+ '*|[0-9]'. '*|[0-9][0-9]'. '*|[0-9]') '*|[0-9][0-9]') '*) list_mode=1 ;;
				*) [ "$indent" -eq 0 ] && [ -n "$marker" ] && list_mode=0 ;;
			esac
		fi

		case "$marker" in
			'`'*|'~'*)
				# CommonMark はフェンス文字の行頭連続数(run 長)で開始・終了を
				# 判定する。4 バッククォート以上のフェンス内に ``` が現れても
				# 誤って閉じないよう、run 長を実際に数える必要がある(run<3 は
				# インラインコード等でありフェンスではないので何もしない)。
				fchar=${marker%"${marker#?}"}
				rest=$marker
				run=0
				while [ "${rest#"$fchar"}" != "$rest" ]; do
					run=$((run + 1))
					rest=${rest#"$fchar"}
				done
				if [ "$run" -ge 3 ]; then
					if [ "$in_fence" -eq 0 ]; then
						in_fence=1
						fence_marker="$fchar"
						fence_len="$run"
						fence_lang="$rest"
						continue
					fi
					# フェンス内: 同じ文字・run 長が開始時以上・後続が空白のみ
					# (info 文字列なし)の行だけが閉じフェンスになる。それ以外
					# はフェンス内容として下の in_fence ブロックに処理させる。
					trailing=$(printf '%s' "$rest" | sed -E 's/[[:space:]]//g')
					if [ "$fchar" = "$fence_marker" ] && [ "$run" -ge "$fence_len" ] && [ -z "$trailing" ]; then
						in_fence=0
						fence_lang=""
						fence_marker=""
						fence_len=0
						continue
					fi
				fi
				;;
		esac

		if [ "$in_fence" -eq 1 ]; then
			if [ "$fence_lang" = "{=typst}" ]; then
				case "$line" in
					*'set text('*|*'text(font:'*|*'text(fill:'*|*'set page('*)
						trimmed=$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//')
						echo "WARNING: $f:$lineno: 生 Typst ブロック内に装飾コードが見つかりました(美観は spec.typ へ): $trimmed"
						;;
				esac
			fi
			continue
		fi

		case "$line" in
			'#'*)
				if printf '%s' "$line" | grep -Eq '^#{1,6} '; then
					rest=$(printf '%s' "$line" | sed -E 's/^#{1,6} //')
					# 「1. 」「2) 」に加え、多階層(1.1.)・全角ピリオド(1．)・
					# 括弧数字((1) )も手動採番として検出する。全角文字は
					# C ロケールの grep -E でバイト列として素直に一致する
					# リテラル・交代のみで書く(? などの量指定子は不可)。
					if printf '%s' "$rest" | grep -Eq '^([0-9]+(\.[0-9]+)*([.)] |．)|\([0-9]+\) )'; then
						echo "ERROR: $f:$lineno: 見出しに手動採番が付与されています(自動採番と二重になります): $line"
						found_error=1
					# 「第」の有無を「第?」のように ? 一つでまとめて書くと、C ロケールの
					# grep -E が多バイト文字をバイト単位で解釈して誤動作するため、
					# 「第N…|N…」の二分岐で書いている。
					elif printf '%s' "$rest" | grep -Eq '^(０|１|２|３|４|５|６|７|８|９)+(．|\.)'; then
						echo "ERROR: $f:$lineno: 見出しに手動採番(全角数字)が付与されています(自動採番と二重になります): $line"
						found_error=1
					elif printf '%s' "$rest" | grep -Eq '^(第[0-9]+|[0-9]+)(章|節|項)'; then
						echo "ERROR: $f:$lineno: 見出しに手動採番(第N章/節/項)が付与されています(自動採番と二重になります): $line"
						found_error=1
					elif printf '%s' "$rest" | grep -Eq '^[0-9]+(\.[0-9]+)* '; then
						echo "WARNING: $f:$lineno: 見出しが数字で始まっています(手動採番の可能性があります。バージョン表記などの正当な見出しであれば無視してください): $line"
					elif printf '%s' "$rest" | grep -Eq '^(０|１|２|３|４|５|６|７|８|９|①|②|③|④|⑤|⑥|⑦|⑧|⑨|⑩)'; then
						echo "WARNING: $f:$lineno: 見出しが全角数字・丸数字で始まっています(手動採番の可能性があります): $line"
					fi
				fi
				;;
		esac

		# --- 注記ボックス(fenced div)のフェンス対応・種類名チェック ---
		# pandoc は、閉じフェンスのない開始フェンスと開始フェンスのない閉じフェンス
		# を div として認識せず、::: の行をそのまま本文として出力する(エラーに
		# ならないため PDF を見るまで気づけない)。引用・リスト項目内の div も
		# pandoc は受け付けるため、判定は行頭の引用符号・空白を落とした marker で行う。
		case "$marker" in
			':::'*)
				spec=${marker#:::}
				while [ "${spec#:}" != "$spec" ]; do
					spec=${spec#:}
				done
				# 「::: info :::」のように末尾へ飾りの : を続ける書式も pandoc は
				# 受け付けるため、前後の空白と末尾の : を落としてから判定する。
				spec=$(printf '%s' "$spec" | sed -E 's/^[[:space:]]+//; s/[[:space:]]*:*[[:space:]]*$//')
				if [ -z "$spec" ]; then
					if [ "$div_depth" -eq 0 ]; then
						echo "ERROR: $f:$lineno: 対応する開始フェンスのない閉じフェンス(:::)です(pandoc は div として認識せず、::: がそのまま本文に印字されます)。" >&2
						found_error=1
					else
						div_depth=$((div_depth - 1))
						div_stack=${div_stack% *}
					fi
				else
					case "$spec" in
						'{'*)
							# 属性ブロック形式(::: {.info #id})。クラスは複数書けるため、
							# いずれかが対応種類ならよい(admonitions.lua も最初に一致した
							# 種類を使う)。
							kinds=$(printf '%s' "$spec" | sed -E 's/^\{//; s/\}.*$//' | tr "$TAB" ' ' | tr ' ' '\n' | sed -n -E 's/^\.([^[:space:]]+)$/\1/p')
							kind=""
							for k in $kinds; do
								case "$k" in
									info|warning|error) kind=$k; break ;;
								esac
							done
							if [ -z "$kind" ]; then
								echo "WARNING: $f:$lineno: 注記ボックスの種類が info / warning / error のいずれでもありません(装飾なしのブロックとして出力されます): $line"
								kind=$(printf '%s\n' "$kinds" | head -n1)
								[ -n "$kind" ] || kind="div"
							fi
							div_depth=$((div_depth + 1))
							div_stack="$div_stack $lineno:$kind"
							;;
						*' '*|*"$TAB"*)
							# 種類名の後に文字が続く行(::: info 補足 など)は pandoc が div の
							# 開始と見なさないため、開始として数えない(対応する閉じフェンス
							# があれば上の不一致エラーで止まる)。
							echo "WARNING: $f:$lineno: ::: で始まる行が注記ボックスの開始フェンスとして認識されません(「::: info」のように種類名だけを書きます): $line"
							;;
						*)
							case "$spec" in
								info|warning|error) ;;
								*) echo "WARNING: $f:$lineno: 注記ボックスの種類 \"$spec\" は未対応です(info / warning / error のみ。それ以外は装飾なしのブロックとして出力されます): $line" ;;
							esac
							div_depth=$((div_depth + 1))
							div_stack="$div_stack $lineno:$spec"
							;;
					esac
				fi
				;;
		esac

		# --- PlantUML 参照のチェック(1 行に複数の画像参照があってもすべて検査する) ---
		# インラインコード内の記法説明(`![図](/build/diagrams/x.svg)` 等)を
		# 実参照と誤検出しないよう、走査前にコードスパンを落とす(`` の 2 連
		# スパンを先に落としてから ` の 1 連スパンを落とす。CommonMark の
		# run 長ペアリングの近似であり、地の文の対になっていないバッククォート
		# が混ざると後続スパンと誤って対にされうるが、その場合の見逃しは
		# 後段の typst compile が file not found で停止するため無言にはならない)。
		scan=$line
		case "$scan" in
			*'`'*) scan=$(printf '%s' "$scan" | sed 's/``[^`]*``//g; s/`[^`]*`//g') ;;
		esac
		case "$scan" in
			*']('*)
				while [ "${scan#*']('}" != "$scan" ]; do
					scan=${scan#*']('}
					target=${scan%%\)*}
					target=${target%% *}
					case "$target" in
						*.puml)
							echo "ERROR: $f:$lineno: .puml を直接画像参照することはできません: $target(変換後の /build/diagrams/<name>.svg を参照し、ソースを assets/diagrams/<name>.puml に置いてください。guides/WRITING.md の「図の挿入」参照)。" >&2
							found_error=1
							;;
						/build/diagrams/*.svg)
							puml="assets/diagrams/$(basename "$target" .svg).puml"
							if [ ! -f "$puml" ]; then
								echo "ERROR: $f:$lineno: 参照 $target に対応する PlantUML ソースが存在しません: $puml を置いてください。" >&2
								found_error=1
							fi
							;;
						*build/diagrams/*)
							echo "ERROR: $f:$lineno: PlantUML 変換図の参照は /build/diagrams/<name>.svg 形式(リポジトリルートからの絶対パス)で書いてください: $target" >&2
							found_error=1
							;;
						/assets/*)
							# 図版のパス誤りは typst compile まで進んでから
							# 分かりにくいエラーになるため早期に止める
							# (assets/ 配下はリポジトリ内のファイルなので、
							# ビルド前に存在を確定できる)。
							if [ ! -f "${target#/}" ]; then
								echo "ERROR: $f:$lineno: 参照先のファイルが存在しません: $target" >&2
								found_error=1
							fi
							;;
					esac
				done
				;;
		esac

		# --- 脚注定義 ID の収集(章別ファイル分割時の重複検出用) ---
		if [ "$is_chapter_mode" -eq 1 ]; then
			case "$line" in
				'[^'*)
					fid=$(printf '%s' "$line" | sed -n -E 's/^\[\^([^]]+)\]:.*/\1/p')
					if [ -n "$fid" ]; then
						key=$(printf '%s' "$parent_dir" | cksum | awk '{print $1}')
						printf '%s\t%s\n' "$fid" "$f" >> "$tmp/footnotes-$key.txt"
					fi
					;;
			esac
		fi
	done < "$f"

	# 閉じ忘れはファイル末尾で確定する(開始フェンスの行を指して報告する)。
	if [ "$div_depth" -gt 0 ]; then
		for entry in $div_stack; do
			echo "ERROR: $f:${entry%%:*}: 注記ボックスの開始フェンス(::: ${entry#*:})に対応する閉じフェンス(:::)がありません(pandoc は div として認識せず、::: がそのまま本文に印字されます)。" >&2
			found_error=1
		done
	fi
done

# --- 脚注定義 ID の重複チェック(章別ファイル分割ディレクトリごと) ---
for accum in "$tmp"/footnotes-*.txt; do
	[ -f "$accum" ] || continue
	awk -F'\t' '
		{
			pair = $1 SUBSEP $2
			if (!(pair in seen)) {
				seen[pair] = 1
				count[$1]++
				files[$1] = files[$1] " " $2
			}
		}
		END {
			for (id in count) {
				if (count[id] > 1) {
					printf "WARNING: 脚注ID \"[^%s]\" が複数の章ファイルで重複定義されています(pandoc 連結時に衝突します):%s\n", id, files[id]
				}
			}
		}
	' "$accum"
done

if [ "$found_error" -eq 1 ]; then
	echo "lint: 見出しの手動採番エラー・フロントマターの不備・章ファイルへのフロントマター混入・図/画像参照の不備・注記ボックス(:::)のフェンス不一致のいずれかが見つかりました。上記の該当行を修正してください。" >&2
	exit 1
fi

exit 0
