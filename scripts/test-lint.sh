#!/bin/sh
# =============================================================================
# scripts/test-lint.sh — scripts/lint.sh の回帰テスト
#
# 使い方: sh scripts/test-lint.sh   (make test からも実行される)
#
# 一時ディレクトリにテストケースごとの独立したサンドボックス(docs/ /
# examples/ / assets/diagrams/ を持つミニリポジトリ)を作り、その中から
# lint.sh を実行して終了コードと出力を検証する。lint.sh は引数なし時の
# docs/・examples/ 探索も、PlantUML ソースの存在確認(assets/diagrams/)も
# カレントディレクトリ相対で行うため、サンドボックス内で実行しないと
# 本物のリポジトリの内容が結果に混入する。
#
# 検証の観点は 2 つ:
#   - 検出すべき違反(エラー/警告)を検出すること
#   - 正常な原稿・除外対象(改訂履歴ファイル等)を誤検知しないこと
#     (正常系は「出力が空であること」まで確認する)
# =============================================================================
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
LINT="$ROOT/scripts/lint.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pass_count=0
fail_count=0
case_num=0
case_name=""
case_dir=""
last_status=0
last_output=""

# 新しいサンドボックスを用意してテストケースを開始する。
new_case() {
	case_name=$1
	case_num=$((case_num + 1))
	case_dir="$tmp/case-$case_num"
	mkdir -p "$case_dir/docs" "$case_dir/examples" "$case_dir/assets/diagrams"
}

# 標準入力の内容でサンドボックス内にファイルを作る(親ディレクトリも作成)。
write() {
	mkdir -p "$case_dir/$(dirname "$1")"
	cat > "$case_dir/$1"
}

# write の CRLF 版(Windows のエディタが保存した原稿を再現する)。sed の \r は
# 環境によって解釈が異なるため awk で組み立てる。
write_crlf() {
	mkdir -p "$case_dir/$(dirname "$1")"
	awk '{ printf "%s\r\n", $0 }' > "$case_dir/$1"
}

# サンドボックス内から lint.sh を実行し、終了コードと出力(stdout+stderr)を
# last_status / last_output に保存する。
run_lint() {
	set +e
	last_output=$( (cd "$case_dir" && sh "$LINT" "$@") 2>&1 )
	last_status=$?
	set -e
}

report_ok() {
	pass_count=$((pass_count + 1))
	echo "ok: $case_name"
}

report_ng() {
	fail_count=$((fail_count + 1))
	echo "NG: $case_name($1)" >&2
	printf '%s\n' "    exit=$last_status 出力:" >&2
	printf '%s\n' "$last_output" | sed 's/^/    | /' >&2
}

# エラー検出を期待: exit 1 かつ出力に期待メッセージ断片を含む。
expect_error() {
	pattern=$1
	shift
	run_lint "$@"
	if [ "$last_status" -ne 1 ]; then
		report_ng "exit 1 を期待(実際: $last_status)"
	elif ! printf '%s\n' "$last_output" | grep -qF "$pattern"; then
		report_ng "出力に「$pattern」が見つかりません"
	else
		report_ok
	fi
}

# 警告のみを期待: exit 0 かつ出力に期待メッセージ断片を含み、ERROR 行はない。
expect_warn() {
	pattern=$1
	shift
	run_lint "$@"
	if [ "$last_status" -ne 0 ]; then
		report_ng "exit 0 を期待(実際: $last_status)"
	elif ! printf '%s\n' "$last_output" | grep -qF "$pattern"; then
		report_ng "出力に「$pattern」が見つかりません"
	elif printf '%s\n' "$last_output" | grep -q "^ERROR:"; then
		report_ng "警告のみを期待しましたが ERROR 行が出力されました"
	else
		report_ok
	fi
}

# 指摘なしを期待: exit 0 かつ出力が空。
expect_ok() {
	run_lint "$@"
	if [ "$last_status" -ne 0 ]; then
		report_ng "exit 0 を期待(実際: $last_status)"
	elif [ -n "$last_output" ]; then
		report_ng "出力なしを期待"
	else
		report_ok
	fi
}

# --- フロントマター / title -------------------------------------------------

new_case "正常な単一ファイルは指摘なし"
write docs/ok.md <<-'EOF'
	---
	title: テスト仕様書
	author: テスト太郎
	---

	# はじめに

	本文。

	# 付録A: 対応一覧 {.unnumbered}

	#ハッシュタグ風の行(見出しではない)
	EOF
expect_ok docs/ok.md

new_case "クォート付きの title は正常"
write docs/quoted.md <<-'EOF'
	---
	title: "テスト仕様書"
	---

	# はじめに
	EOF
expect_ok docs/quoted.md

new_case "フロントマターがない単一ファイルはエラー"
write docs/no-fm.md <<-'EOF'
	# はじめに

	本文。
	EOF
expect_error "YAML フロントマター(ファイル先頭の --- ブロック)が見つかりません" docs/no-fm.md

new_case "フロントマターの終端がないとエラー"
write docs/no-end.md <<-'EOF'
	---
	title: テスト仕様書

	# はじめに
	EOF
expect_error "YAML フロントマターの終端(---)が見つかりません" docs/no-end.md

new_case "title キーがないとエラー"
write docs/no-title.md <<-'EOF'
	---
	author: テスト太郎
	---

	# はじめに
	EOF
expect_error "title: が見つかりません" docs/no-title.md

new_case "title の値が空だとエラー"
write docs/empty-title.md <<-'EOF'
	---
	title:
	---

	# はじめに
	EOF
expect_error "title: の値が空です" docs/empty-title.md

new_case "title がダブルクォートのみでもエラー"
write docs/quoted-empty.md <<-'EOF'
	---
	title: ""
	---

	# はじめに
	EOF
expect_error "title: の値が空です" docs/quoted-empty.md

new_case "title がシングルクォートのみでもエラー"
write docs/quoted-empty2.md <<-'EOF'
	---
	title: ''
	---

	# はじめに
	EOF
expect_error "title: の値が空です" docs/quoted-empty2.md

new_case "CRLF 改行の単一ファイルは指摘なし"
write_crlf docs/crlf.md <<-'EOF'
	---
	title: "CRLF テスト仕様書"
	---

	# はじめに

	本文。
	EOF
expect_ok docs/crlf.md

new_case "CRLF 改行でも title の空は検出する"
write_crlf docs/crlf-empty-title.md <<-'EOF'
	---
	title: ""
	---

	# はじめに
	EOF
expect_error "title: の値が空です" docs/crlf-empty-title.md

# --- 表紙ロゴ ---------------------------------------------------------------

new_case "logo: が指す画像が存在しないとエラー"
write docs/logo-missing.md <<-'EOF'
	---
	title: テスト仕様書
	logo: "/assets/images/no-such-logo.png"
	---

	# はじめに
	EOF
expect_error "logo: が指す画像が存在しません" docs/logo-missing.md

new_case "logo: が指す画像が存在すれば正常"
write docs/logo-ok.md <<-'EOF'
	---
	title: テスト仕様書
	logo: "/assets/images/logo.png"
	---

	# はじめに
	EOF
write assets/images/logo.png <<-'EOF'
	dummy
	EOF
expect_ok docs/logo-ok.md

# --- 章別ファイル分割 -------------------------------------------------------

new_case "章別ファイル分割の正常形は指摘なし"
write docs/spec/00-meta.md <<-'EOF'
	---
	title: 章別テスト仕様書
	---
	EOF
write docs/spec/01-intro.md <<-'EOF'
	# はじめに

	本文。
	EOF
expect_ok docs/spec/00-meta.md docs/spec/01-intro.md

new_case "章ファイルへのフロントマター混入はエラー"
write docs/spec/00-meta.md <<-'EOF'
	---
	title: 章別テスト仕様書
	---
	EOF
write docs/spec/01-intro.md <<-'EOF'
	---
	title: 上書きしてしまうタイトル
	---

	# はじめに
	EOF
expect_error "章ファイルの先頭に YAML フロントマター" docs/spec/00-meta.md docs/spec/01-intro.md

new_case "CRLF 改行でも章ファイルへのフロントマター混入を検出する"
write_crlf docs/spec/00-meta.md <<-'EOF'
	---
	title: 章別テスト仕様書
	---
	EOF
write_crlf docs/spec/01-intro.md <<-'EOF'
	---
	title: 上書きしてしまうタイトル
	---

	# はじめに
	EOF
expect_error "章ファイルの先頭に YAML フロントマター" docs/spec/00-meta.md docs/spec/01-intro.md

new_case "docs 直下の NN-*.md は章ファイルではなく単一ファイル扱い"
write docs/01-standalone.md <<-'EOF'
	# はじめに

	本文。
	EOF
expect_error "YAML フロントマター(ファイル先頭の --- ブロック)が見つかりません" docs/01-standalone.md

# --- 見出しの手動採番 -------------------------------------------------------

new_case "「# 1. 見出し」形式の手動採番はエラー"
write docs/numbered.md <<-'EOF'
	---
	title: テスト仕様書
	---

	# 1. はじめに
	EOF
expect_error "見出しに手動採番が付与されています" docs/numbered.md

new_case "「## 2) 見出し」形式の手動採番はエラー"
write docs/numbered2.md <<-'EOF'
	---
	title: テスト仕様書
	---

	## 2) 概要
	EOF
expect_error "見出しに手動採番が付与されています" docs/numbered2.md

new_case "「# 第1章 見出し」形式はエラー"
write docs/chapter-style.md <<-'EOF'
	---
	title: テスト仕様書
	---

	# 第1章 はじめに
	EOF
expect_error "手動採番(第N章/節/項)" docs/chapter-style.md

new_case "「## 3節 見出し」形式はエラー"
write docs/chapter-style2.md <<-'EOF'
	---
	title: テスト仕様書
	---

	## 3節 概要
	EOF
expect_error "手動採番(第N章/節/項)" docs/chapter-style2.md

new_case "「## 1.1. 見出し」形式(多階層採番)はエラー"
write docs/numbered-multi.md <<-'EOF'
	---
	title: テスト仕様書
	---

	## 1.1. 概要
	EOF
expect_error "見出しに手動採番が付与されています" docs/numbered-multi.md

new_case "「## (1) 見出し」形式(括弧数字)はエラー"
write docs/numbered-paren.md <<-'EOF'
	---
	title: テスト仕様書
	---

	## (1) 概要
	EOF
expect_error "見出しに手動採番が付与されています" docs/numbered-paren.md

new_case "「## 1．見出し」形式(全角ピリオド)はエラー"
write docs/numbered-zenkaku.md <<-'EOF'
	---
	title: テスト仕様書
	---

	## 1．概要
	EOF
expect_error "見出しに手動採番が付与されています" docs/numbered-zenkaku.md

new_case "数字で始まる見出しは警告のみ"
write docs/version-heading.md <<-'EOF'
	---
	title: テスト仕様書
	---

	## 2.5 系の変更点
	EOF
expect_warn "見出しが数字で始まっています" docs/version-heading.md

new_case "コードフェンス内の見出し風の行は検査しない"
write docs/fenced.md <<-'EOF'
	---
	title: テスト仕様書
	---

	# はじめに

	```markdown
	# 1. フェンス内の手動採番
	```

	~~~text
	## 2) こちらも対象外
	~~~
	EOF
expect_ok docs/fenced.md

new_case "4 バッククォートのフェンス内は内側の 3 バッククォートがあっても検査しない"
write docs/fenced4.md <<-'EOF'
	---
	title: テスト仕様書
	---

	# はじめに

	````markdown
	```
	# 1. 手動採番
	```
	````
	EOF
expect_ok docs/fenced4.md

new_case "4 バッククォートのフェンスの閉じ後は検査される"
write docs/fenced4-closed.md <<-'EOF'
	---
	title: テスト仕様書
	---

	# はじめに

	````markdown
	```
	内側の行
	```
	````

	# 1. 手動採番
	EOF
expect_error "見出しに手動採番が付与されています" docs/fenced4-closed.md

new_case "チルダフェンス内のバッククォート行ではフェンスが閉じない"
write docs/tilde-with-backtick.md <<-'EOF'
	---
	title: テスト仕様書
	---

	# はじめに

	~~~markdown
	```
	# 1. 手動採番
	~~~
	EOF
expect_ok docs/tilde-with-backtick.md

# --- PlantUML 参照 ----------------------------------------------------------

new_case ".puml の直接画像参照はエラー"
write docs/direct-puml.md <<-'EOF'
	---
	title: テスト仕様書
	---

	![図](/assets/diagrams/foo.puml)
	EOF
expect_error ".puml を直接画像参照することはできません" docs/direct-puml.md

new_case "参照 SVG に対応する .puml がないとエラー"
write docs/missing-puml.md <<-'EOF'
	---
	title: テスト仕様書
	---

	![図](/build/diagrams/missing.svg)
	EOF
expect_error "対応する PlantUML ソースが存在しません" docs/missing-puml.md

new_case "対応する .puml がある SVG 参照は正常(width 属性付き)"
write docs/good-diagram.md <<-'EOF'
	---
	title: テスト仕様書
	---

	![シーケンス図](/build/diagrams/seq.svg){width=75%}
	EOF
write assets/diagrams/seq.puml <<-'EOF'
	@startuml
	A -> B
	@enduml
	EOF
expect_ok docs/good-diagram.md

new_case "ルート絶対パスでない図の参照はエラー"
write docs/relative-diagram.md <<-'EOF'
	---
	title: テスト仕様書
	---

	![図](build/diagrams/seq.svg)
	EOF
write assets/diagrams/seq.puml <<-'EOF'
	@startuml
	A -> B
	@enduml
	EOF
expect_error "/build/diagrams/<name>.svg 形式" docs/relative-diagram.md

new_case "コードフェンス内の図参照は検査しない"
write docs/fenced-diagram.md <<-'EOF'
	---
	title: テスト仕様書
	---

	```markdown
	![図](/assets/diagrams/foo.puml)
	![図](build/diagrams/bar.svg)
	```
	EOF
expect_ok docs/fenced-diagram.md

new_case "リスト項目内のインデントされたフェンス内は検査しない"
write docs/list-fenced.md <<-'EOF'
	---
	title: テスト仕様書
	---

	# 図の書き方

	- 次のように参照する:

	    ```markdown
	    ![図](/build/diagrams/example.svg)
	    ```

	- 以上。
	EOF
expect_ok docs/list-fenced.md

new_case "引用ブロック内のフェンス内は検査しない"
write docs/quote-fenced.md <<-'EOF'
	---
	title: テスト仕様書
	---

	# 図の書き方

	> ```markdown
	> ![図](/build/diagrams/example.svg)
	> ```
	EOF
expect_ok docs/quote-fenced.md

new_case "インデントされたフェンスの閉じ後は検査される"
write docs/list-fenced-closed.md <<-'EOF'
	---
	title: テスト仕様書
	---

	- 例:

	    ```markdown
	    ![図](/build/diagrams/example.svg)
	    ```

	![実参照](/build/diagrams/example.svg)
	EOF
expect_error "対応する PlantUML ソースが存在しません" docs/list-fenced-closed.md

new_case "インデントコードブロック内のフェンス風の行で以降のチェックが無効化されない"
write docs/indented-code-fence.md <<-'EOF'
	---
	title: テスト仕様書
	---

	# 手順

	    ```sh
	    make pdf

	## 1. 悪い見出し
	EOF
expect_error "見出しに手動採番が付与されています" docs/indented-code-fence.md

new_case "ネストしたリスト項目(4 スペース)内の図参照も検査される"
write docs/nested-list-ref.md <<-'EOF'
	---
	title: テスト仕様書
	---

	# 構成

	- 外側の項目
	  - 内側の項目:
	    ![図](/build/diagrams/nonexistent.svg)
	EOF
expect_error "対応する PlantUML ソースが存在しません" docs/nested-list-ref.md

new_case "リスト項目の 4 スペース継続行の画像参照も検査される"
write docs/list-continuation-ref.md <<-'EOF'
	---
	title: テスト仕様書
	---

	# 構成

	- 箇条書きの項目です。
	    ![存在しない画像](/assets/images/nonexistent.png)
	EOF
expect_error "参照先のファイルが存在しません" docs/list-continuation-ref.md

new_case "インラインコード内の図参照は検査しない"
write docs/inline-code-ref.md <<-'EOF'
	---
	title: テスト仕様書
	---

	# 記法の説明

	図は `![キャプション](/build/diagrams/nonexistent.svg)` のように書きます。
	EOF
expect_ok docs/inline-code-ref.md

# --- assets 配下の参照先 ----------------------------------------------------

new_case "/assets/ 配下の参照先が存在しないとエラー"
write docs/missing-image.md <<-'EOF'
	---
	title: テスト仕様書
	---

	![構成図](/assets/images/no-such-image.png){width=70%}
	EOF
expect_error "参照先のファイルが存在しません" docs/missing-image.md

new_case "/assets/ 配下の参照先が存在すれば正常"
write docs/existing-image.md <<-'EOF'
	---
	title: テスト仕様書
	---

	![構成図](/assets/images/overview.png){width=70%}
	EOF
write assets/images/overview.png <<-'EOF'
	dummy
	EOF
expect_ok docs/existing-image.md

new_case "外部 URL の画像参照は存在チェックの対象外"
write docs/remote-image.md <<-'EOF'
	---
	title: テスト仕様書
	---

	![外部図](https://example.com/foo.png)
	EOF
expect_ok docs/remote-image.md

new_case "1 行に複数の図参照があってもすべて検査される"
write docs/multi-ref.md <<-'EOF'
	---
	title: テスト仕様書
	---

	![a](/build/diagrams/seq.svg) と ![b](/assets/diagrams/foo.puml)
	EOF
write assets/diagrams/seq.puml <<-'EOF'
	@startuml
	A -> B
	@enduml
	EOF
expect_error ".puml を直接画像参照することはできません" docs/multi-ref.md

# --- 生 Typst ブロック ------------------------------------------------------

new_case "生 Typst ブロック内の装飾コードは警告"
write docs/raw-typst.md <<-'EOF'
	---
	title: テスト仕様書
	---

	```{=typst}
	#set text(size: 8pt)
	```
	EOF
expect_warn "生 Typst ブロック内に装飾コード" docs/raw-typst.md

new_case "通常の typst 言語フェンスは装飾コード検出の対象外"
write docs/typst-sample.md <<-'EOF'
	---
	title: テスト仕様書
	---

	```typst
	#set text(size: 8pt)
	```
	EOF
expect_ok docs/typst-sample.md

# --- 脚注定義 ID の重複 -----------------------------------------------------

new_case "章ファイル間の脚注 ID 重複は警告"
write docs/spec/00-meta.md <<-'EOF'
	---
	title: 章別テスト仕様書
	---
	EOF
write docs/spec/01-a.md <<-'EOF'
	# 章A

	本文[^note]。

	[^note]: 章Aの脚注。
	EOF
write docs/spec/02-b.md <<-'EOF'
	# 章B

	本文[^note]。

	[^note]: 章Bの脚注。
	EOF
expect_warn "重複定義されています" docs/spec/00-meta.md docs/spec/01-a.md docs/spec/02-b.md

new_case "同一章ファイル内の脚注 ID 重複は対象外(ファイル間のみ検出)"
write docs/spec/00-meta.md <<-'EOF'
	---
	title: 章別テスト仕様書
	---
	EOF
write docs/spec/01-a.md <<-'EOF'
	# 章A

	[^note]: 一度目。

	[^note]: 二度目。
	EOF
expect_ok docs/spec/00-meta.md docs/spec/01-a.md

new_case "別ディレクトリの章ファイル間では脚注 ID が重複してもよい"
write docs/spec1/00-meta.md <<-'EOF'
	---
	title: 仕様書1
	---
	EOF
write docs/spec1/01-a.md <<-'EOF'
	# 章A

	[^note]: 仕様書1の脚注。
	EOF
write docs/spec2/00-meta.md <<-'EOF'
	---
	title: 仕様書2
	---
	EOF
write docs/spec2/01-a.md <<-'EOF'
	# 章A

	[^note]: 仕様書2の脚注。
	EOF
expect_ok docs/spec1/00-meta.md docs/spec1/01-a.md docs/spec2/00-meta.md docs/spec2/01-a.md

# --- 除外対象 ---------------------------------------------------------------

new_case "*.revisions.md は検査対象外"
write docs/foo.revisions.md <<-'EOF'
	# 1. フロントマターも採番エラーもあるが対象外
	EOF
expect_ok docs/foo.revisions.md

new_case "*.revisions.yaml は検査対象外"
write docs/foo.revisions.yaml <<-'EOF'
	revisions: []
	EOF
expect_ok docs/foo.revisions.yaml

new_case "章別ディレクトリの revisions.md / revisions.yaml は検査対象外"
write docs/spec/revisions.md <<-'EOF'
	# 1. 対象外
	EOF
write docs/spec/revisions.yaml <<-'EOF'
	revisions: []
	EOF
expect_ok docs/spec/revisions.md docs/spec/revisions.yaml

new_case "存在しないファイルの指定は読み飛ばす"
expect_ok docs/no-such-file.md

# --- 引数なし(全件検査)モード ---------------------------------------------

new_case "引数なしで docs/ と examples/ が空でも正常終了"
run_lint
if [ "$last_status" -ne 0 ]; then
	report_ng "exit 0 を期待(実際: $last_status)"
else
	report_ok
fi

new_case "引数なしで章別ファイル分割ディレクトリも自動探索される"
write examples/myspec/00-meta.md <<-'EOF'
	---
	title: 探索テスト仕様書
	---
	EOF
write examples/myspec/10-intro.md <<-'EOF'
	# 1. 手動採番エラー
	EOF
expect_error "見出しに手動採番が付与されています"

# --- 複合 -------------------------------------------------------------------

new_case "エラーと警告が混在するときは exit 1 で両方出力される"
write docs/mixed.md <<-'EOF'
	---
	title: テスト仕様書
	---

	# 1. 手動採番エラー

	## 2.5 系の変更点
	EOF
expect_error "見出しに手動採番が付与されています" docs/mixed.md
case_name="エラーと警告が混在するときの警告行の出力"
if printf '%s\n' "$last_output" | grep -qF "見出しが数字で始まっています"; then
	report_ok
else
	report_ng "出力に警告行が見つかりません"
fi

# --- 結果 -------------------------------------------------------------------

echo "test-lint: 成功 $pass_count 件 / 失敗 $fail_count 件"
if [ "$fail_count" -ne 0 ]; then
	exit 1
fi
exit 0
