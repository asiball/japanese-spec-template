# =============================================================================
# Dockerfile — ビルド環境(すべてのビルドはこのイメージ内で実行する)
#
# pandoc はベースイメージ同梱のものを使い、Typst は GitHub Releases の musl
# 静的ビルドを、PlantUML は Maven Central の jar を、フォントは Adobe の
# GitHub リポジトリのリリースタグを、それぞれ固定バージョン+チェックサム
# 検証で導入する。フォントは /opt/fonts に焼き込み、typst の --font-path と
# PlantUML の文字幅計測(fontconfig)の両方から参照する。
# =============================================================================

# 4 桁のイミュータブルタグで固定する(pandoc/dockerfiles は 3.10 のような
# 数値タグを rolling として再 push しうるため、a.b.c.d 形式でのみ実体が
# 固定される。digest 固定が必要な場合は guides/BUILDING.md の手順で上書き)。
ARG PANDOC_IMAGE=pandoc/core:3.10.0.0
FROM ${PANDOC_IMAGE}

# 変更時は TYPST_SHA256_X86_64 / TYPST_SHA256_AARCH64 も差し替える(guides/BUILDING.md 参照)。
# Dockerfile の内容が変わると Makefile 側の DOCKER_TAG(内容ハッシュ)も
# 自動的に変わるため、手動でのバージョン管理は不要。
ARG TYPST_VERSION=0.15.0
# 空の場合は RUN 内で `uname -m` から自動選択する(x86_64 / aarch64 のみ)。
# それ以外のアーキテクチャ、または既定の自動選択を上書きしたい場合は
# `--build-arg TYPST_ARCH=...` で明示指定する(guides/BUILDING.md の Docker 節参照)。
ARG TYPST_ARCH=""
# 既定の TYPST_VERSION 用、x86_64 / aarch64 それぞれの sha256(GitHub
# Releases のアセットダイジェスト)。TYPST_ARCH 自動選択時はここから対応する
# 値を選ぶ。TYPST_ARCH を明示指定するアーキテクチャがこの 2 つ以外の場合は
# 焼き込み値がないため、TYPST_SHA256 の明示指定が必要になる。
ARG TYPST_SHA256_X86_64="59b207df01be2dab9f13e80f73d04d7ff8273ffd46b3dd1b9eef5c60f3eeabea"
ARG TYPST_SHA256_AARCH64="cdf50ffc7b8ba759ed02200632eda3d78eb8b99aacb6611f4f75684990647620"
# 明示指定時はこの値を検証に使う(焼き込み値より優先)。空の場合は
# TYPST_SHA256_X86_64 / TYPST_SHA256_AARCH64 から選択された値を使う。
ARG TYPST_SHA256=""
# TYPST_SHA256 も焼き込み値もない場合(未知アーキテクチャで TYPST_SHA256 も
# 未指定)は ALLOW_UNVERIFIED=1 の指定を必須とする(検証なしの「暗黙の
# スキップ」を防ぐフェイルセーフ)。
ARG ALLOW_UNVERIFIED=""

USER root

RUN set -eu; \
	apk add --no-cache curl xz ca-certificates; \
	if [ -z "$TYPST_ARCH" ]; then \
		case "$(uname -m)" in \
			x86_64) TYPST_ARCH="x86_64-unknown-linux-musl" ;; \
			aarch64|arm64) TYPST_ARCH="aarch64-unknown-linux-musl" ;; \
			*) \
				echo "ERROR: 未知のアーキテクチャです($(uname -m))。TYPST_ARCH と TYPST_SHA256 を明示指定してください。" >&2; \
				echo "  例: docker build --build-arg TYPST_ARCH=<対応するターゲット triple> --build-arg TYPST_SHA256=<対応するsha256> ." >&2; \
				exit 1 ;; \
		esac; \
	fi; \
	arch_url="https://github.com/typst/typst/releases/download/v${TYPST_VERSION}/typst-${TYPST_ARCH}.tar.xz"; \
	curl -fsSL -o /tmp/typst.tar.xz "$arch_url"; \
	# 検証 sha の優先順位: 明示指定 > ALLOW_UNVERIFIED によるスキップ >
	# 焼き込み値。ALLOW_UNVERIFIED を焼き込み値より優先するのは、バージョンを
	# 上げて焼き込み値が古くなった場合(必ず不一致で停止する)の脱出ハッチを
	# 残すため。
	if [ -n "$TYPST_SHA256" ]; then \
		sha="$TYPST_SHA256"; \
	elif [ -n "$ALLOW_UNVERIFIED" ]; then \
		sha=""; \
	else \
		case "$TYPST_ARCH" in \
			x86_64-unknown-linux-musl) sha="$TYPST_SHA256_X86_64" ;; \
			aarch64-unknown-linux-musl) sha="$TYPST_SHA256_AARCH64" ;; \
			*) sha="" ;; \
		esac; \
	fi; \
	if [ -n "$sha" ]; then \
		echo "${sha}  /tmp/typst.tar.xz" | sha256sum -c -; \
	elif [ -n "$ALLOW_UNVERIFIED" ]; then \
		echo "WARNING: TYPST_SHA256 が未指定のため、チェックサム検証をスキップしました(ALLOW_UNVERIFIED が明示的に指定されているため続行します)。" >&2; \
	else \
		echo "ERROR: TYPST_SHA256 が未指定です。チェックサム検証なしで Typst バイナリを導入することはできません。" >&2; \
		echo "  取得方法: curl -fsSL '${arch_url}' | sha256sum" >&2; \
		echo "  取得した値を指定してビルド: docker build --build-arg TYPST_SHA256=<sha256> ." >&2; \
		echo "  検証をスキップしてビルドする場合(非推奨): docker build --build-arg ALLOW_UNVERIFIED=1 ." >&2; \
		exit 1; \
	fi; \
	mkdir -p /tmp/typst-extract; \
	tar -xJf /tmp/typst.tar.xz -C /tmp/typst-extract; \
	install -m 0755 "/tmp/typst-extract/typst-${TYPST_ARCH}/typst" /usr/local/bin/typst; \
	rm -rf /tmp/typst.tar.xz /tmp/typst-extract; \
	apk del curl xz

# PlantUML(Markdown から参照する .puml の SVG 変換に使用。guides/WRITING.md の
# 「図の挿入」節参照)。Maven Central の jar はアーキテクチャ非依存・イミュータブル
# なので、バージョンと sha256 の固定だけで決定的に導入できる。
ARG PLANTUML_VERSION=1.2026.6
ARG PLANTUML_SHA256="e620ae095a2ba0134d3c33fd5ae34ff01e785f3df1796c0898802b8761a033a8"

RUN set -eu; \
	# JRE は headless 版ではなく通常版を使う: Alpine の openjdk21-jre-headless
	# には libfontmanager.so が含まれず、PlantUML のフォント計測(AWT)が
	# UnsatisfiedLinkError で失敗する。
	# graphviz はシーケンス図以外(クラス図・状態遷移図等)のレイアウトに必要。
	# fontconfig + /opt/fonts の登録は、イメージに焼き込むフォントを
	# PlantUML(Java)から見えるようにするため: 図中テキストの幅計測を
	# PDF 描画と同じフォントで行わないと、ラベル幅と箱のサイズがずれる
	# ことがある(ttf-dejavu は欧文のフォールバック)。
	apk add --no-cache openjdk21-jre graphviz fontconfig ttf-dejavu curl; \
	curl -fsSL -o /opt/plantuml.jar "https://repo1.maven.org/maven2/net/sourceforge/plantuml/plantuml/${PLANTUML_VERSION}/plantuml-${PLANTUML_VERSION}.jar"; \
	echo "${PLANTUML_SHA256}  /opt/plantuml.jar" | sha256sum -c -; \
	printf '#!/bin/sh\nexec java -Djava.awt.headless=true -jar /opt/plantuml.jar "$@"\n' > /usr/local/bin/plantuml; \
	chmod 0755 /usr/local/bin/plantuml; \
	printf '<?xml version="1.0"?>\n<!DOCTYPE fontconfig SYSTEM "fonts.dtd">\n<fontconfig><dir>/opt/fonts</dir></fontconfig>\n' > /etc/fonts/conf.d/60-opt-fonts.conf; \
	apk del curl

# フォント(Adobe Source Han。guides/BUILDING.md の「フォント」節参照)。
# 各リポジトリのリリースタグの raw URL から取得し sha256 で検証する
# (タグ付きコミットのファイルはイミュータブルなので、これで決定的に導入
# できる)。OFL の再配布条件に従い、ライセンス文書もフォントと同じ場所に置く。
# フォントを差し替える場合はこの一覧と template/spec.typ のフォント定数・
# template/plantuml.config をあわせて変更する(guides/BUILDING.md の手順参照)。
RUN set -eu; \
	apk add --no-cache curl; \
	mkdir -p /opt/fonts; \
	base="https://raw.githubusercontent.com/adobe-fonts"; \
	for spec in \
		"e5f502bb193c28829895b098498f0f9dd8f658c760b0f83656ad41c1137a8785:source-han-serif/2.003R/SubsetOTF/JP/SourceHanSerifJP-Regular.otf" \
		"13473d3c1cf1fdb0e08d5e5e093cf9fc57d3e59d9d13cf7f6369615bf96397ee:source-han-serif/2.003R/SubsetOTF/JP/SourceHanSerifJP-Bold.otf" \
		"5d39f8eaaa9ad2aed93166b0a4fc4a43ac82de8a5c6112992446c24d88b595f9:source-han-sans/2.005R/SubsetOTF/JP/SourceHanSansJP-Medium.otf" \
		"3a2722f94c97a53b172579a10ef8fc34b3fa8a6bb4f7947a2ec709ab647fb755:source-han-sans/2.005R/SubsetOTF/JP/SourceHanSansJP-Bold.otf" \
		"06751f8f4b9263da7bf2ce12ba4375daba4880a8e6d4ccb61b2adb6d6401fc10:source-han-code-jp/2.012R/OTF/SourceHanCodeJP-Regular.otf" \
		"4141bf4789f4c0d0160df1dcc550d03764977464dc8d923b6741dbcb95110b6e:source-han-code-jp/2.012R/OTF/SourceHanCodeJP-Bold.otf" \
	; do \
		sha="${spec%%:*}"; path="${spec#*:}"; \
		file="/opt/fonts/$(basename "$path")"; \
		curl -fsSL -o "$file" "$base/$path"; \
		echo "$sha  $file" | sha256sum -c -; \
	done; \
	curl -fsSL -o /opt/fonts/LICENSE-SourceHanSerif.txt "$base/source-han-serif/2.003R/LICENSE.txt"; \
	echo "9ff5bb567e1b92c801fc1069e5fbf992ff8efccacb9db94e5959a5b3ba9bb903  /opt/fonts/LICENSE-SourceHanSerif.txt" | sha256sum -c -; \
	curl -fsSL -o /opt/fonts/LICENSE-SourceHanSans.txt "$base/source-han-sans/2.005R/LICENSE.txt"; \
	echo "fcac737e761ec63dbfbdce11030a1780161920d80315edba9c8beff1c2bac5a2  /opt/fonts/LICENSE-SourceHanSans.txt" | sha256sum -c -; \
	curl -fsSL -o /opt/fonts/LICENSE-SourceHanCodeJP.txt "$base/source-han-code-jp/2.012R/LICENSE.txt"; \
	echo "6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2  /opt/fonts/LICENSE-SourceHanCodeJP.txt" | sha256sum -c -; \
	# fontconfig のキャッシュをイメージに焼き込む。ビルドは
	# `docker run --user $(id -u)` で実行されるため、実行時は
	# /var/cache/fontconfig にも $HOME にも書けず、キャッシュがないと
	# PlantUML(Java/AWT)の実行のたびにフォント走査が走る(警告も出る)。
	fc-cache -f >/dev/null; \
	apk del curl

WORKDIR /work

# ベースイメージの ENTRYPOINT ["pandoc"] を解除し、`docker run ... sh -c` で
# pandoc / typst の両方を呼び出せるようにする。
ENTRYPOINT []
