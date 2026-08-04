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
RESOURCES="$CONTENTS/Resources"

# Frozen `slim` binary (PDF/PPTX/image compressor), built via `make freeze`
# in the slim repo. Bundle-embed: Scoot calls it as a subprocess at runtime.
SLIM_BIN="${SLIM_BIN:-/Users/kun/Projects/slim/dist/slim}"
if [ ! -f "$SLIM_BIN" ]; then
    echo "ERROR: slim binary not found at $SLIM_BIN" >&2
    echo "       Build it with:  cd /Users/kun/Projects/slim && make freeze" >&2
    echo "       Or point SLIM_BIN at an existing frozen build." >&2
    exit 1
fi

echo "==> Assembling $APP ..."
rm -rf "$APP"
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

cp "$BINARY" "$MACOS/Scoot"

echo "==> Embedding slim binary from $SLIM_BIN ..."
cp "$SLIM_BIN" "$RESOURCES/slim"
chmod +x "$RESOURCES/slim"

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
    <string>0.5.0</string>
    <key>CFBundleVersion</key>
    <string>5</string>
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

echo "==> Signing embedded slim binary ad-hoc (nested code must be signed before the app)..."
codesign --force -s - "$RESOURCES/slim"

echo "==> Signing ad-hoc..."
codesign --force -s - "$APP"

echo "==> Done: $APP"
