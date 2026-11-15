#!/bin/sh
set -e
cd "$(dirname "$0")"

swift build --build-system native -c release --product Writer 2>&1 | grep -v "has been deprecated" || true

APP=build/Writer.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Writer "$APP/Contents/MacOS/Writer"
cp Resources/Info.plist "$APP/Contents/Info.plist"
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

codesign --force --sign - "$APP" >/dev/null 2>&1
echo "Built $APP"
