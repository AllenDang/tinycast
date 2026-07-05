#!/bin/bash
# Builds Tinycast and assembles a runnable, ad-hoc-signed .app bundle.
# Usage: Packaging/make-app.sh [debug|release]
set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="Tinycast"
BUNDLE_ID="com.tinycast.app"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
DISPLAY_NAME="${DISPLAY_NAME:-$APP_NAME}"
MIN_OS="26.0"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$ROOT"

echo "▸ Building Tinycast ($CONFIG)…"
swift build -c "$CONFIG"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP="$ROOT/build/$APP_NAME.app"

echo "▸ Assembling $APP_NAME.app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

# Bundle any SwiftPM resource bundles (e.g. Tinycast's own resources bundle).
shopt -s nullglob
for bundle in "$BIN_DIR"/*.bundle; do
    cp -R "$bundle" "$APP/Contents/Resources/"
done
shopt -u nullglob

ICON_KEY=""
if [ -f "$ROOT/Packaging/AppIcon.icns" ]; then
    cp "$ROOT/Packaging/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
    ICON_KEY=$'\t<key>CFBundleIconFile</key>\n\t<string>AppIcon</string>'
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>$APP_NAME</string>
	<key>CFBundleDisplayName</key>
	<string>$DISPLAY_NAME</string>
	<key>CFBundleExecutable</key>
	<string>$APP_NAME</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>$BUILD_NUMBER</string>
	<key>LSMinimumSystemVersion</key>
	<string>$MIN_OS</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSAutoFillRequiresTextContentTypeForOneTimeCodeOnMac</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>Tinycast</string>
$ICON_KEY
</dict>
</plist>
PLIST

# Prefer a stable, self-signed identity so the Accessibility (TCC) grant survives rebuilds.
# Falls back to ad-hoc if it hasn't been created yet (run Packaging/dev-cert.sh once).
SIGN_IDENTITY="Tinycast Self-Signed"
# Note: no `-v` — the cert is self-signed (untrusted) but codesign still signs with it, and the
# stable cert identity is what keeps the TCC grant alive across rebuilds.
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
    echo "▸ Signing with stable identity ($SIGN_IDENTITY)…"
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP"
else
    echo "▸ Ad-hoc signing (run Packaging/dev-cert.sh once for a persistent Accessibility grant)…"
    codesign --force --deep --sign - "$APP"
fi

echo "✓ Built $APP"
