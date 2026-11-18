#!/bin/sh
set -e
cd "$(dirname "$0")"

swift build --build-system native -c release --product Writer 2>&1 | grep -v "has been deprecated" || true

APP=build/Writer.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Writer "$APP/Contents/MacOS/Writer"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -n "$VERSION" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion ${BUILD_NUMBER:-$(git rev-list --count HEAD)}" "$APP/Contents/Info.plist"
fi

SPARKLE=$(find .build/artifacts/sparkle -type d -name Sparkle.framework -path "*macos-arm64_x86_64*" | head -1)
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Writer" 2>/dev/null || true
cp -R Resources/Fonts Resources/Templates Resources/katex Resources/preview.js Resources/Welcome.md Resources/Shortcuts.md "$APP/Contents/Resources/"

XCODE_DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" xcrun --find actool >/dev/null 2>&1; then
  DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" xcrun actool Resources/Writer.icon --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 14.0 --app-icon Writer \
    --output-partial-info-plist build/icon-info.plist >/dev/null
else
  if [ ! -f build/Writer.icns ]; then
    swift Scripts/make-icon.swift build/Writer.iconset
    iconutil -c icns build/Writer.iconset -o build/Writer.icns
  fi
  cp build/Writer.icns "$APP/Contents/Resources/Writer.icns"
fi

if [ -n "$DEVELOPER_ID" ]; then
  SIGN_ARGS="--force --options runtime --timestamp --sign $DEVELOPER_ID"
else
  SIGN_ARGS="--force --sign -"
fi
SPARKLE_B="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for target in "$SPARKLE_B"/XPCServices/*.xpc "$SPARKLE_B/Autoupdate" "$SPARKLE_B/Updater.app" "$APP/Contents/Frameworks/Sparkle.framework" "$APP"; do
  codesign $SIGN_ARGS "$target" >/dev/null 2>&1
done
echo "Built $APP"
