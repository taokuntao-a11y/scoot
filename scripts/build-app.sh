#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"

echo "==> Building Scoot (release)..."
swift build -c release

BINARY="$(swift build -c release --show-bin-path 2>/dev/null)/Scoot"

APP="$REPO_DIR/dist/Scoot.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"

echo "==> Assembling $APP ..."
rm -rf "$APP"
mkdir -p "$MACOS"

cp "$BINARY" "$MACOS/Scoot"

cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.kk.scoot</string>
    <key>CFBundleName</key>
    <string>Scoot</string>
    <key>CFBundleExecutable</key>
    <string>Scoot</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS/PkgInfo"

echo "==> Signing ad-hoc..."
codesign --force -s - "$APP"

echo "==> Done: $APP"
