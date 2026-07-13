#!/bin/bash
# Builds Tinycast and assembles a runnable, ad-hoc-signed .app bundle.
# Usage: Packaging/make-app.sh [debug|release]
set -euo pipefail

CONFIG="${1:-release}"
# EXECUTABLE_NAME is the SwiftPM product (always "Tinycast") — it's the file under
# Contents/MacOS and CFBundleExecutable. The *display* identity (bundle folder name,
# CFBundleName/DisplayName) and bundle ID are channel-driven via env so alpha/beta/stable
# ship as distinct, side-by-side apps.
EXECUTABLE_NAME="Tinycast"
BUNDLE_ID="${BUNDLE_ID:-com.tinycast.app}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
DISPLAY_NAME="${DISPLAY_NAME:-Tinycast}"
CATEGORY="${CATEGORY:-public.app-category.productivity}"
MIN_OS="26.0"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Single source of truth for the marketing version: the root VERSION file. An explicit
# VERSION env var still wins (used by channel/release builds); keep project.yml in sync for the IDE.
VERSION="${VERSION:-$(tr -d '[:space:]' < "$ROOT/VERSION" 2>/dev/null)}"
VERSION="${VERSION:-0.1.0}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$ROOT"

echo "▸ Building Tinycast ($CONFIG)…"
swift build -c "$CONFIG"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
# Bundle folder is named after the display name so channels don't collide in /Applications.
APP="$ROOT/build/$DISPLAY_NAME.app"

echo "▸ Assembling $DISPLAY_NAME.app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/$EXECUTABLE_NAME" "$APP/Contents/MacOS/$EXECUTABLE_NAME"

# Bundle any SwiftPM resource bundles (e.g. Tinycast's own resources bundle).
shopt -s nullglob
for bundle in "$BIN_DIR"/*.bundle; do
    cp -R "$bundle" "$APP/Contents/Resources/"
done
shopt -u nullglob

# App icon: compile the Icon Composer .icon (Liquid Glass) via actool into
# Assets.car + a fallback .icns. SwiftPM never processes .icon files, so this is the
# only place the icon is built; skipping it ships the app with no icon.
ICON_KEY=""
ICON_SRC="$(ls -d "$ROOT"/Tinycast/*.icon 2>/dev/null | head -1 || true)"
if [ -n "$ICON_SRC" ]; then
    ICON_NAME="$(basename "$ICON_SRC" .icon)"
    echo "▸ Compiling app icon ($ICON_NAME.icon)…"
    ICON_TMP="$(mktemp -d)"
    xcrun actool \
        --app-icon "$ICON_NAME" \
        --output-partial-info-plist "$ICON_TMP/icon.plist" \
        --platform macosx \
        --minimum-deployment-target "$MIN_OS" \
        --compile "$APP/Contents/Resources" \
        "$ICON_SRC" >/dev/null
    rm -rf "$ICON_TMP"
    ICON_KEY=$'\t<key>CFBundleIconFile</key>\n\t<string>'"$ICON_NAME"$'</string>\n\t<key>CFBundleIconName</key>\n\t<string>'"$ICON_NAME"$'</string>'
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>$DISPLAY_NAME</string>
	<key>CFBundleDisplayName</key>
	<string>$DISPLAY_NAME</string>
	<key>CFBundleExecutable</key>
	<string>$EXECUTABLE_NAME</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>LSApplicationCategoryType</key>
	<string>$CATEGORY</string>
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
	<string>$DISPLAY_NAME</string>
$ICON_KEY
</dict>
</plist>
PLIST

# Prefer a stable, self-signed identity so the Accessibility (TCC) grant survives rebuilds.
# Falls back to ad-hoc if it hasn't been created yet (run Packaging/dev-cert.sh once).
SIGN_IDENTITY="Tinycast Self-Signed"
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
    echo "▸ Signing with stable identity ($SIGN_IDENTITY)…"
    SIGN_AS="$SIGN_IDENTITY"
else
    echo "▸ Ad-hoc signing (run Packaging/dev-cert.sh once for a persistent Accessibility grant)…"
    SIGN_AS="-"
fi
# Sign nested code (SwiftPM resource bundles) first, then the app last — `--deep` is deprecated
# and can't sign inner bundles correctly for anything but the simplest layouts.
shopt -s nullglob
for bundle in "$APP"/Contents/Resources/*.bundle; do
    codesign --force --sign "$SIGN_AS" "$bundle"
done
shopt -u nullglob
codesign --force --sign "$SIGN_AS" "$APP"

echo "✓ Built $APP"
