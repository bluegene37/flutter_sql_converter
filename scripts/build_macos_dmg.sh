#!/usr/bin/env bash
# Builds the macOS release app and packages it as a drag-to-install DMG.
# Output: build/MagicSoftSQL-<version>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

flutter build macos --release

APP="build/macos/Build/Products/Release/MagicSoftSQL.app"
VERSION=$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml | tr -d ' ')
OUT="build/MagicSoftSQL-${VERSION}.dmg"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$OUT"
hdiutil create -volname "MagicSoftSQL" -srcfolder "$STAGE" -ov -format UDZO "$OUT"
echo "Created $OUT"
