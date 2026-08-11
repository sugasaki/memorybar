#!/bin/bash
# 配布用の .app バンドルを dist/ に生成する。
# .app 化により Dock 非表示(LSUIElement)でメニューバーのみに常駐する。
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Memory Info"
BUNDLE_ID="com.sugasaki.memory-info-menubar"
EXECUTABLE="memory-info-menubar"
VERSION="0.1.0"

swift build -c release

APP_DIR="dist/$APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"

cp ".build/release/$EXECUTABLE" "$APP_DIR/Contents/MacOS/$EXECUTABLE"

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
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>$VERSION</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>MIT License</string>
</dict>
</plist>
EOF

# ad-hoc 署名(ローカル利用向け。配布する場合は Developer ID で署名し直すこと)
codesign --force --sign - "$APP_DIR"

echo ""
echo "生成完了: $APP_DIR"
echo "インストール: cp -R \"$APP_DIR\" /Applications/"
echo "ログイン時に自動起動するには: システム設定 > 一般 > ログイン項目 に追加"
