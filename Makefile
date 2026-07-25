# =============================================================================
# Makefile — Markdown -> Pandoc(Typst backend) -> Typst -> PDF
# =============================================================================
#
# 使い方:
#   make pdf SRC=docs/foo.md     単一 Markdown ファイルをビルド(SRC 必須)
#   make pdf SRC=docs/foo        章別ファイル分割ディレクトリをビルド(SRC 必須)
#   make example                 同梱サンプル 2 種(章別ファイル分割・単一ファイル)をビルド
#   make pdf-all                 docs/ 配下のビルド対象を自動発見して全件ビルド
#   make watch SRC=docs/foo.md   執筆中の自動リビルド(README の「執筆中の自動更新」参照。SRC 必須)
#   make lint                    docs/ と examples/ の Markdown の簡易 lint のみを実行
#   make test                    scripts/lint.sh 自体の回帰テストを実行
#   make clean                   build/ を削除
#   make help                    コマンド一覧を表示(引数なしの make も同じ)
#
# ビルドはすべて Docker コンテナ内で実行する(pandoc / typst / plantuml と
# フォントは Dockerfile が固定バージョン+チェックサム検証で導入する。
# BUILDING.md 参照)。Makefile はビルド対象の導出と検証を担い、ビルド本体は
# scripts/container-build.sh が担う。lint(scripts/lint.sh)のみ POSIX sh
# だけで動くためローカルで直接実行する。

# SRC は既定で空(同梱サンプルのビルドは make example に分離、validate-src が
# 空チェックで案内エラーを出す)。
# 末尾スラッシュを正規化する(コマンドライン指定値の上書きには override が必要)。
override SRC := $(patsubst %/,%,$(SRC))
BUILD      := build

# 章別ファイル分割(SRC がディレクトリの場合)。00-meta.md がフロントマター
# 専用、[0-9][0-9]-*.md が章ファイルでファイル名の辞書順が章順(規約の詳細は
# README の「章別ファイル分割」節参照)。
SRC_IS_DIR := $(shell [ -d "$(SRC)" ] && echo 1)

ifeq ($(SRC_IS_DIR),1)
# ディレクトリ名には basename を適用しない(docs/spec.v2 のようにドットを
# 含む名前が spec へ切り詰められ、docs/spec.v3 と出力先が衝突するため)。
NAME               := $(notdir $(SRC))
CHAPTER_FILES      := $(sort $(wildcard $(SRC)/[0-9][0-9]-*.md))
META_FILE          := $(SRC)/00-meta.md
NON_META_CHAPTERS  := $(filter-out $(META_FILE),$(CHAPTER_FILES))
SRC_INPUTS         := $(CHAPTER_FILES)
REV_MD             := $(SRC)/revisions.md
REV_YAML           := $(SRC)/revisions.yaml
else
NAME                := $(basename $(notdir $(SRC)))
CHAPTER_FILES       :=
META_FILE           :=
NON_META_CHAPTERS   :=
SRC_INPUTS          := $(SRC)
# 改訂履歴の別ファイル化(SRC と同じディレクトリ・同じベース名)。
REV_MD              := $(patsubst %.md,%.revisions.md,$(SRC))
REV_YAML            := $(patsubst %.md,%.revisions.yaml,$(SRC))
endif

# 改訂履歴の別ファイル(README の「改訂履歴の別ファイル化」節参照)。存在の
# 判定だけを行い、変換・--metadata-file の付与は container-build.sh が行う。
# 両方存在する場合は validate-src がエラーで停止する。
REV_MD_EXISTS    := $(wildcard $(REV_MD))
REV_YAML_EXISTS  := $(wildcard $(REV_YAML))

# PlantUML 図の変換(README の「図の挿入」節参照)。Markdown は変換後の
# /build/diagrams/<name>.svg を画像参照し(ビルド後はエディタの Markdown
# プレビューでもそのまま表示できる)、参照 SVG から名前の 1:1 対応で
# assets/diagrams/<name>.puml を逆引きして変換する。参照抽出はコードフェンス
# を除外するため scripts/list-diagram-refs.sh で行う。SRC が参照する図だけを
# 変換する。
DIAGRAM_DIR     := assets/diagrams
DIAGRAM_OUT     := $(BUILD)/diagrams
# SRC_INPUTS が空(SRC 未指定)のときは list-diagram-refs.sh を引数なしで
# 起動しない(引数なしだと awk が標準入力の到着を待ち続けて固まるため)。
DIAGRAM_SVGS    := $(sort $(if $(SRC_INPUTS),$(shell sh scripts/list-diagram-refs.sh $(SRC_INPUTS) 2>/dev/null)))
DIAGRAM_PUMLS   := $(patsubst $(DIAGRAM_OUT)/%.svg,$(DIAGRAM_DIR)/%.puml,$(DIAGRAM_SVGS))

DOCKER_IMAGE   := jp-spec-builder

# Typst バイナリのチェックサム検証(既定値は Dockerfile に設定済みのため
# 通常は指定不要。バージョン/アーキテクチャ変更時のみ上書きする。BUILDING.md 参照)。
#   make pdf TYPST_SHA256=<sha256>   検証値を差し替える
#   make pdf ALLOW_UNVERIFIED=1      検証をスキップする(非推奨)
TYPST_SHA256     ?=
ALLOW_UNVERIFIED ?=

# Dockerfile の内容(+検証系オーバーライド)から導出する内容ハッシュ。
# Dockerfile を変更すると自動的に別タグになり、次回ビルドで再構築が走る
# (手動でのバージョンバンプは不要)。sha256sum は macOS に無いため POSIX の
# cksum を使う。TYPST_SHA256 / ALLOW_UNVERIFIED はこの行より前で定義済み
# であること(ハッシュに含めるため)。
DOCKER_TAG     := $(shell { cat Dockerfile; printf '%s %s' "$(TYPST_SHA256)" "$(ALLOW_UNVERIFIED)"; } | cksum | cut -d' ' -f1)
DOCKER_FULLTAG := $(DOCKER_IMAGE):$(DOCKER_TAG)

# SRC / 改訂履歴ファイルの共通検証(validate ターゲットから展開する)。
# スペースを含むパスは Make が単語分割してしまうため、対応せず明確なエラーで
# 停止する。
define validate-src
@if [ -z "$(SRC)" ]; then \
	echo "ERROR: SRC を指定してください(例: make pdf SRC=docs/my-spec.md、章別ファイル分割は make pdf SRC=docs/my-spec)。同梱サンプルのビルドは make example を使ってください。" >&2; \
	exit 1; \
fi
@case "$(SRC)" in \
	*" "*) \
		echo "ERROR: SRC のパスにスペースは使えません: $(SRC)" >&2; \
		exit 1 ;; \
	*.revisions.md|*.revisions.yaml) \
		echo "ERROR: SRC に改訂履歴ファイル($(SRC))は指定できません。本文の Markdown(docs/<name>.md または docs/<name>/)を指定してください(改訂履歴ファイルはビルド時に自動で読み込まれます)。" >&2; \
		exit 1 ;; \
esac
@if [ ! -e "$(SRC)" ]; then \
	echo "ERROR: SRC が見つかりません: $(SRC)" >&2; \
	exit 1; \
fi
@if [ ! -d "$(SRC)" ]; then \
	case "$(SRC)" in \
		*.md) : ;; \
		*) \
			echo "ERROR: 単一ファイルの SRC は .md 拡張子が必要です: $(SRC)(改訂履歴の自動検出が <name>.md → <name>.revisions.md という命名規約に依存するため。章別ファイル分割の場合はディレクトリを指定してください)。" >&2; \
			exit 1 ;; \
	esac; \
fi
@if [ -d "$(SRC)" ]; then \
	for cf in "$(SRC)"/[0-9][0-9]-*.md; do \
		case "$$cf" in \
			*" "*) \
				echo "ERROR: 章ファイル名にスペースは使えません: $$cf(Make の引数分割の制約のため。ファイル名からスペースを除いてください)。" >&2; \
				exit 1 ;; \
		esac; \
	done; \
	if [ ! -f "$(SRC)/00-meta.md" ]; then \
		echo "ERROR: $(SRC)/00-meta.md が見つかりません(章別ファイル分割には 00-meta.md が必須です。README の「章別ファイル分割」参照)。" >&2; \
		exit 1; \
	fi; \
	if [ -z "$(strip $(NON_META_CHAPTERS))" ]; then \
		echo "ERROR: $(SRC) に章ファイル([0-9][0-9]-*.md。00-meta.md 以外)が 1 つも見つかりません。" >&2; \
		exit 1; \
	fi; \
fi
@if [ -f "$(REV_MD)" ] && [ -f "$(REV_YAML)" ]; then \
	echo "ERROR: $(REV_MD) と $(REV_YAML) が両方存在します。改訂履歴ファイルはどちらか一方のみにしてください(推奨: $(if $(filter 1,$(SRC_IS_DIR)),revisions.md,.revisions.md))。" >&2; \
	exit 1; \
fi
@if [ -n "$(strip $(DIAGRAM_PUMLS))" ]; then \
	for p in $(DIAGRAM_PUMLS); do \
		if [ ! -f "$$p" ]; then \
			echo "ERROR: Markdown から参照されている図に対応する PlantUML ソースが見つかりません: $$p(参照 /$(DIAGRAM_OUT)/<name>.svg に対し、ソースを $(DIAGRAM_DIR)/<name>.puml として置いてください)。" >&2; \
			exit 1; \
		fi; \
	done; \
fi
endef

# ビルド対象の導出結果を container-build.sh へ渡す環境変数(スクリプト冒頭の
# 環境変数一覧と揃える)。SRC_DIR は章別ファイル分割のときのみ SRC を渡し、
# watch モードが章ファイルの増減を毎回そこから動的に再導出できるようにする。
CONTAINER_ENV := \
	-e NAME="$(NAME)" \
	-e SRC_INPUTS="$(SRC_INPUTS)" \
	-e SRC_DIR="$(if $(filter 1,$(SRC_IS_DIR)),$(SRC))" \
	-e REV_MD="$(REV_MD_EXISTS)" \
	-e REV_YAML="$(REV_YAML_EXISTS)"

# --user: build/ 配下の生成物をホスト側の実行ユーザー所有にする(コンテナ内
# root 所有で残ると消せなくなるため)。
DOCKER_RUN := docker run --rm --user $$(id -u):$$(id -g) -v "$(CURDIR)":/work -w /work

.PHONY: help pdf example pdf-all docker-build validate watch clean lint lint-src test

# 引数なしの `make` は使い方を表示する(既定を pdf にすると SRC 必須の
# エラーだけが出て、何をすればよいか分からないため)。
.DEFAULT_GOAL := help

help:
	@echo "使い方:"
	@echo "  make pdf SRC=docs/foo.md     単一 Markdown ファイルをビルド"
	@echo "  make pdf SRC=docs/foo        章別ファイル分割ディレクトリをビルド"
	@echo "  make example                 同梱サンプル 2 種をビルド"
	@echo "  make pdf-all                 docs/ 配下を自動発見して全件ビルド"
	@echo "  make watch SRC=docs/foo.md   執筆中の自動リビルド(Ctrl-C で終了)"
	@echo "  make lint                    docs/ と examples/ の簡易 lint"
	@echo "  make test                    scripts/lint.sh の回帰テスト"
	@echo "  make clean                   build/ を削除"
	@echo ""
	@echo "詳細は README.md を参照してください。"

# SRC の検証を独立ターゲットにして、イメージ構築(docker-build)より先に
# 安価な検証で失敗できるようにする(prerequisite の並び順で先行させる)。
validate:
	$(validate-src)

pdf: validate docker-build
	@mkdir -p "$(BUILD)"
	$(DOCKER_RUN) $(CONTAINER_ENV) $(DOCKER_FULLTAG) sh scripts/container-build.sh

# 同梱サンプル 2 種(章別ファイル分割・単一ファイル)のビルド。SRC の既定値
# 廃止に伴い、動作確認用のビルドはここに切り出す。
example:
	$(MAKE) pdf SRC=examples/sample-spec
	$(MAKE) pdf SRC=examples/wareki-api-spec.md

# docs/ 配下のビルド対象(単一ファイル + 章別ファイル分割)を自動発見して
# 全件ビルドする。テンプレートを元にした下流リポジトリでは docs/ に文書を
# 置くだけで CI 検証の対象になる(テンプレート時点では対象なしのため no-op)。
pdf-all:
	@found=0; \
	for f in docs/*.md; do \
		[ -f "$$f" ] || continue; \
		case "$$f" in \
			*.revisions.md) continue ;; \
		esac; \
		found=1; \
		$(MAKE) pdf SRC="$$f" || exit 1; \
	done; \
	for d in docs/*/; do \
		[ -d "$$d" ] || continue; \
		d=$${d%/}; \
		if [ ! -f "$$d/00-meta.md" ]; then \
			for cf in "$$d"/[0-9][0-9]-*.md; do \
				[ -f "$$cf" ] || continue; \
				echo "ERROR: $$d に 00-meta.md がありません(章ファイルが置かれているため章別ファイル分割と思われます。00-meta.md がないとビルド対象として検出されないため、エラーで停止します。README の「章別ファイル分割」参照)。" >&2; \
				exit 1; \
			done; \
			continue; \
		fi; \
		found=1; \
		$(MAKE) pdf SRC="$$d" || exit 1; \
	done; \
	if [ "$$found" -eq 0 ]; then \
		echo "pdf-all: docs/ にビルド対象がありません(docs/<name>.md または docs/<name>/ を置くと自動でビルド対象になります)"; \
		exit 0; \
	fi

# DOCKER_TAG はイメージ構築対象の内容ハッシュなので、そのタグのイメージが
# 既に存在するなら同じ Dockerfile 内容で構築済みであり、再構築は不要。
# デーモン未接続はここで検知する(docker build の生エラーは非技術者に分かり
# にくいため)。
docker-build:
	@if ! docker info >/dev/null 2>&1; then \
		echo "ERROR: Docker デーモンに接続できません。Docker Desktop(または docker サービス)が起動しているか確認してください。" >&2; \
		exit 1; \
	fi
	@if docker image inspect $(DOCKER_FULLTAG) >/dev/null 2>&1; then \
		exit 0; \
	fi; \
	docker build \
		$(if $(TYPST_SHA256),--build-arg TYPST_SHA256=$(TYPST_SHA256)) \
		$(if $(ALLOW_UNVERIFIED),--build-arg ALLOW_UNVERIFIED=$(ALLOW_UNVERIFIED)) \
		-t $(DOCKER_FULLTAG) -t $(DOCKER_IMAGE):latest .

# 執筆中の自動リビルド。コンテナ内で container-build.sh が watch モードで
# 動き続ける(仕組みはスクリプト側のコメント参照)。リポジトリはマウントで
# 共有されるため、ホスト側エディタでの編集がそのまま検知される。
# --init: Ctrl-C(SIGINT)をコンテナ内の sh へ確実に届けるため。
# -it: 対話端末前提(watch は CI では使わない)。
watch: validate docker-build
	@mkdir -p "$(BUILD)"
	@echo "watch: $(SRC) の変更を監視します(Ctrl-C で終了)"
	$(DOCKER_RUN) --init -it -e WATCH=1 $(CONTAINER_ENV) $(DOCKER_FULLTAG) sh scripts/container-build.sh

# 簡易 lint(scripts/lint.sh)。見出しの手動採番などを検知する。
# `make lint` 単体は docs/ と examples/ の Markdown 全件を対象にする。
lint:
	@sh scripts/lint.sh

# ビルド対象の SRC だけを lint する補助ターゲット(コンテナ内のビルドでも
# 同じ lint が pandoc の前に実行される)。
lint-src:
	@sh scripts/lint.sh $(SRC_INPUTS)

# scripts/lint.sh 自体の回帰テスト(検出すべき違反を検出し、正常な原稿を
# 誤検知しないことをサンドボックス上のフィクスチャで検証する)。
test:
	@sh scripts/test-lint.sh

clean:
	rm -rf $(BUILD)
