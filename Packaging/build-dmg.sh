#!/bin/bash
# Builds a Release Tinycast.app and packages it into a distributable DMG.
# Usage: Packaging/build-dmg.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/Packaging/make-app.sh" release

APP="$ROOT/build/Tinycast.app"
DMG="$ROOT/build/Tinycast.dmg"
STAGE="$(mktemp -d)"

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
echo "▸ Creating DMG…"
hdiutil create -volname "Tinycast" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "✓ Built $DMG"
