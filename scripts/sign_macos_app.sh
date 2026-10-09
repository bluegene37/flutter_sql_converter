#!/usr/bin/env bash
set -euo pipefail

# Gene - Oct 7, 2026: Standalone macOS code signing script for MagicSoftSQL.app.
# Signs nested frameworks, dylibs, and the main application bundle with
# Developer ID Application, Hardened Runtime (--options runtime), secure timestamps,
# and Release entitlements required by Apple Gatekeeper and Notarization.

# Navigate to project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-build/macos/Build/Products/Release/MagicSoftSQL.app}"

if [[ "$TARGET" != /* ]]; then
  if [ -d "$PWD/$TARGET" ]; then
    APP="$PWD/$TARGET"
  else
    APP="$SCRIPT_DIR/../$TARGET"
  fi
else
  APP="$TARGET"
fi

cd "$SCRIPT_DIR/.."
ENTITLEMENTS="macos/Runner/Release.entitlements"

# Resolve signing identity: check env CODESIGN_IDENTITY or MACOS_SIGN_IDENTITY, then auto-detect from keychain
IDENTITY="${CODESIGN_IDENTITY:-${MACOS_SIGN_IDENTITY:-}}"
if [ -z "$IDENTITY" ]; then
  IDENTITY=$(security find-identity -p codesigning -v | grep "Developer ID Application:" | head -n 1 | sed -E 's/.*"(Developer ID Application: [^"]+)".*/\1/' || true)
fi

if [ -z "$IDENTITY" ]; then
  echo "==> WARNING: No Developer ID Application identity specified or found in keychain." >&2
  echo "    Leaving existing signature." >&2
  exit 0
fi

if [ ! -d "$APP" ]; then
  echo "Error: Application bundle $APP not found!" >&2
  exit 1
fi

if [ ! -f "$ENTITLEMENTS" ]; then
  echo "Error: Entitlements file $ENTITLEMENTS not found!" >&2
  exit 1
fi

echo "==> Signing code in $APP with \"$IDENTITY\"..."

# Nested code first, outer bundle last.
# Apple notarization requires --options runtime and a secure timestamp on all executables and frameworks.
if [ -d "$APP/Contents/Frameworks" ]; then
  echo "==> Signing nested frameworks, dylibs, and bundles..."
  find "$APP/Contents/Frameworks" -depth \
    \( -name '*.framework' -o -name '*.dylib' -o -name '*.bundle' \) \
    -print0 |
    while IFS= read -r -d '' nested; do
      echo "    Signing: $(basename "$nested")"
      codesign --force --options runtime --timestamp \
        --sign "$IDENTITY" "$nested"
    done
fi

echo "==> Signing main application bundle $APP..."
codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$IDENTITY" "$APP"

echo "==> Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP"
echo "==> Designated Requirement:"
codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => /    /p'
echo "==> Signature completed successfully for $APP"
