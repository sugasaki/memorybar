#!/bin/bash
# ローカル利用向けのad-hoc署名済み.appバンドルをdist/に生成する。
# .app化によりDock非表示(LSUIElement)でメニューバーのみに常駐する。
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="TrueMem"
BUNDLE_ID="com.sugasaki.truemem"
EXECUTABLE="truemem"
# バージョンは VERSION ファイルを唯一の出所にする(配布ビルドと手元ビルドで食い違わせない)
APP_VERSION="${APP_VERSION:-$(cat VERSION 2>/dev/null || echo 0.0.0)}"
APP_BUILD="${APP_BUILD:-1}"
# 更新判定に使うソースコミット。CIでは GITHUB_SHA、ローカルでは git から取る
APP_COMMIT="${APP_COMMIT:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}"
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
echo "生成完了: $APP_DIR (version=$APP_VERSION, build=$APP_BUILD, commit=${APP_COMMIT:0:7})"
echo "インストール: cp -R \"$APP_DIR\" /Applications/"
echo "ログイン時に自動起動するには: システム設定 > 一般 > ログイン項目 に追加"
