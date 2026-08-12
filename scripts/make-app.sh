#!/bin/bash
# ローカル利用向けのad-hoc署名済み.appバンドルをdist/に生成する。
# .app化によりDock非表示(LSUIElement)でメニューバーのみに常駐する。
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="TrueMem"
BUNDLE_ID="com.sugasaki.truemem"
EXECUTABLE="truemem"
# バージョンは Git タグ(vX.Y.Z)を唯一の出所にする。
# CI がリリースのたびにタグを打つので、ファイルを書き換えて push する必要がない。
# 手元ビルドでは「いま出ている最新のタグ」を表示する(次の番号を騙らない)
version_from_tags() {
    local exact latest
    # このコミットにタグが付いていればそれが正
    if exact="$(git describe --tags --match 'v[0-9]*' --exact-match 2>/dev/null)"; then
        echo "${exact#v}"
        return
    fi
    if latest="$(git describe --tags --match 'v[0-9]*' --abbrev=0 2>/dev/null)"; then
        echo "${latest#v}"
        return
    fi
    echo 0.0.0
}
APP_VERSION="${APP_VERSION:-$(version_from_tags)}"
APP_BUILD="${APP_BUILD:-1}"
# 更新判定に使うソースコミット。CIでは GITHUB_SHA、ローカルでは git から取る
# 未コミットの変更を含むビルドに HEAD をそのまま刻むと、実際には別物なのに
# 「そのコミットのリリース版」を名乗ってしまう(更新判定にも使われる)。
# dirty なら SHA として不正な値にして、更新判定から外す
# git diff ではなく git status を見るのは、未追跡ファイルを拾うため。
# SwiftPM は Sources/ を glob するので、追加された未追跡の .swift は
# ビルドに取り込まれるのに git diff では検出できない
default_commit() {
    local sha status
    sha="$(git rev-parse HEAD 2>/dev/null)" || { echo unknown; return; }
    status="$(git status --porcelain)" || { echo unknown; return; }
    if [ -z "$status" ]; then
        echo "$sha"
    else
        echo "${sha}-dirty"
    fi
}
APP_COMMIT="${APP_COMMIT:-$(default_commit)}"
# ローカルは自アーキテクチャのみ、配布用は UNIVERSAL=1 で arm64 + x86_64
UNIVERSAL="${UNIVERSAL:-0}"

validate_plist_value() {
    local value="$1"
    local label="$2"
    case "$value" in
        ""|*[!0-9A-Za-z.-]*)
            echo "$labelには半角英数字・ピリオド・ハイフンのみ指定できます: $value" >&2
            exit 64
            ;;
    esac
}

validate_plist_value "$APP_VERSION" "APP_VERSION"
validate_plist_value "$APP_BUILD" "APP_BUILD"
validate_plist_value "$APP_COMMIT" "APP_COMMIT"

BUILD_ARGS=(-c release)
if [ "$UNIVERSAL" = "1" ]; then
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi

swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"

APP_DIR="dist/$APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"

cp "$BIN_DIR/$EXECUTABLE" "$APP_DIR/Contents/MacOS/$EXECUTABLE"

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>$EXECUTABLE</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleName</key>
	<string>$APP_NAME</string>
	<key>CFBundleDisplayName</key>
	<string>$APP_NAME</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$APP_VERSION</string>
	<key>CFBundleVersion</key>
	<string>$APP_BUILD</string>
	<key>TMSourceCommit</key>
	<string>$APP_COMMIT</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>MIT License</string>
</dict>
</plist>
EOF

# ad-hoc署名(ローカル利用専用。外部配布時はDeveloper ID署名とnotarizationが必要)
codesign --force --sign - "$APP_DIR"

echo ""
# 短縮すると -dirty が切り落ちて、人が唯一目にする場所から警告が消えるため付け直す
SHORT_COMMIT="${APP_COMMIT:0:7}"
case "$APP_COMMIT" in *-dirty) SHORT_COMMIT="${SHORT_COMMIT}-dirty" ;; esac
echo "生成完了: $APP_DIR (version=$APP_VERSION, build=$APP_BUILD, commit=$SHORT_COMMIT)"
echo "インストール: cp -R \"$APP_DIR\" /Applications/"
echo "ログイン時に自動起動するには: システム設定 > 一般 > ログイン項目 に追加"
