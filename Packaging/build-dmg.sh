#!/bin/bash
# Builds a Release Tinycast.app and packages it into a distributable DMG.
# Usage: Packaging/build-dmg.sh
#
# Honors the same channel env as make-app.sh:
#   DISPLAY_NAME  bundle/app name + DMG volume name (e.g. "Tinycast Alpha"); default "Tinycast"
#   BUNDLE_ID     channel bundle id; default com.tinycast.app
#   VERSION       full version incl. channel suffix (e.g. 0.2.0-alpha.8); default 0.1.0
#   BUILD_NUMBER  CFBundleVersion
# The DMG file name always carries the version so release assets are unambiguous, e.g.
#   Tinycast-0.2.0-alpha.8.dmg   (alpha)      Tinycast-0.2.0.dmg   (stable)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/Packaging/make-app.sh" release

DISPLAY_NAME="${DISPLAY_NAME:-Tinycast}"
VERSION="${VERSION:-0.1.0}"
# Base name for the DMG file; version is appended below. Strip spaces so "Tinycast Alpha"
# would become "Tinycast-Alpha", but by default we key the file off the plain product name
# and let VERSION's suffix (-alpha.N / -beta.N) carry the channel.
DMG_BASE="${DMG_BASE:-Tinycast}"
DMG_NAME="${DMG_BASE}-${VERSION}"

APP="$ROOT/build/$DISPLAY_NAME.app"
DMG="$ROOT/build/$DMG_NAME.dmg"
STAGE="$(mktemp -d)"

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
echo "▸ Creating DMG…"
# `hdiutil create` is deprecated on macOS 26; diskutil is the supported path. The mounted
# volume is named after the display name (channel-aware); the file name carries the version.
diskutil image create from "$STAGE" \
    --format UDZO \
    --volumeName "$DISPLAY_NAME" \
    "$DMG" >/dev/null
rm -rf "$STAGE"

echo "✓ Built $DMG"
