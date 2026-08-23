#!/bin/bash
# Build L3270.app menu bar bundle from SwiftPM executable.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CONFIG="${1:-debug}"
PRODUCT="L3270App"
APP_NAME="L3270"
BUILD_DIR="$ROOT/.build/$CONFIG"
EXE="$BUILD_DIR/$PRODUCT"
APP_DIR="$ROOT/.build/$APP_NAME.app"

swift build -c "$CONFIG" --product "$PRODUCT"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXE" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>L3270</string>
    <key>CFBundleIdentifier</key>
    <string>com.l3270.menubar</string>
    <key>CFBundleName</key>
    <string>L3270</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "Built $APP_DIR"
echo "Install: cp -R '$APP_DIR' /Applications/"
