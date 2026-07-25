#!/bin/sh
# =============================================================================
# scripts/puml2svg.sh — PlantUML ソース 1 ファイルを SVG へ変換する
#
# 使い方:
#   scripts/puml2svg.sh <input.puml> <output.svg>
#
# リポジトリルートから実行されることを前提とする(scripts/container-build.sh
# から呼ばれる。PLANTUML_CONFIG の既定値がルート相対のため)。
#
# 環境変数:
#   PLANTUML         plantuml の実行コマンド(既定: plantuml)。
#                    `java -jar /path/to/plantuml.jar` のような複数語も可
#                    (そのため展開時は意図的にクォートしない)。
#   PLANTUML_CONFIG  全図に適用する設定ファイル(既定: template/plantuml.config)。
#
# -pipe を使う理由: plantuml は通常モードだと @startuml に付けた図名で出力
# ファイル名を決めてしまい、<name>.puml → <name>.svg の対応が保証されない。
# stdin/stdout 経由ならファイル名の対応を Makefile 側で完全に制御できる。
#
# 失敗時は書きかけの出力を必ず削除する(残すと mtime 比較で次回の変換が
# スキップされ、壊れた SVG が静かに使われ続けるため)。
# =============================================================================
set -eu

if [ "$#" -ne 2 ]; then
	echo "usage: $0 <input.puml> <output.svg>" >&2
	exit 2
fi

in=$1
out=$2
PLANTUML=${PLANTUML:-plantuml}
PLANTUML_CONFIG=${PLANTUML_CONFIG:-template/plantuml.config}

first_word=${PLANTUML%% *}
if ! command -v "$first_word" >/dev/null 2>&1; then
	echo "ERROR: plantuml が見つかりません($PLANTUML)。ビルドは Docker イメージ内での実行が前提です(make pdf を使ってください。イメージには plantuml が同梱されています)。" >&2
	exit 1
fi

mkdir -p "$(dirname "$out")"

if ! $PLANTUML -tsvg -failfast2 -config "$PLANTUML_CONFIG" -pipe < "$in" > "$out"; then
	rm -f "$out"
	echo "ERROR: PlantUML の変換に失敗しました: $in" >&2
	echo "以下は plantuml -syntax の診断出力(行番号は -config の適用分だけ後方にずれることがあります):" >&2
	$PLANTUML -syntax < "$in" >&2 || true
	exit 1
fi
