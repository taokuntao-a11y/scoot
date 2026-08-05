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
# Embedding is OPTIONAL: if it's missing, Scoot still builds fine and falls back
# to resolving `slim` from PATH at runtime (SlimService.locateBinary), which is
# what a Mac that installed slim via its own install.sh (pipx) will have.
SLIM_BIN="${SLIM_BIN:-/Users/kun/Projects/slim/dist/slim}"
SLIM_EMBEDDED=0

echo "==> Assembling $APP ..."
rm -rf "$APP"
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

cp "$BINARY" "$MACOS/Scoot"

if [ -f "$SLIM_BIN" ]; then
    echo "==> Embedding slim binary from $SLIM_BIN ..."
    cp "$SLIM_BIN" "$RESOURCES/slim"
    chmod +x "$RESOURCES/slim"
    SLIM_EMBEDDED=1
else
    echo "WARNING: slim binary not found at $SLIM_BIN — skipping embed." >&2
    echo "         'scoot slim' / the GUI's 压缩 action will resolve 'slim' from PATH at runtime instead." >&2
    echo "         Install slim (see its install.sh), or set SLIM_BIN to point at a frozen build," >&2
    echo "         or build it yourself with:  cd /Users/kun/Projects/slim && make freeze" >&2
fi

echo "==> Installing app icon ..."
cp "$REPO_DIR/icon/AppIcon.icns" "$RESOURCES/AppIcon.icns"

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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.6.1</string>
    <key>CFBundleVersion</key>
    <string>8</string>
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

if [ "$SLIM_EMBEDDED" = "1" ]; then
    echo "==> Signing embedded slim binary ad-hoc (nested code must be signed before the app)..."
    codesign --force -s - "$RESOURCES/slim"
fi

echo "==> Signing ad-hoc..."
codesign --force -s - "$APP"

echo "==> Done: $APP"
