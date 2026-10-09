#!/usr/bin/env bash
# Builds the macOS release app and packages it as a drag-to-install DMG.
# Output: build/MagicSoftSQL-<version>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

# Previous implementation:
# flutter build macos --release
#
# APP="build/macos/Build/Products/Release/MagicSoftSQL.app"
# VERSION=$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml | tr -d ' ')
# OUT="build/MagicSoftSQL-${VERSION}.dmg"
#
# STAGE=$(mktemp -d)
# trap 'rm -rf "$STAGE"' EXIT
# cp -R "$APP" "$STAGE/"
# ln -s /Applications "$STAGE/Applications"
#
# rm -f "$OUT"
# hdiutil create -volname "MagicSoftSQL" -srcfolder "$STAGE" -ov -format UDZO "$OUT"
# echo "Created $OUT"

# Gene - Oct 7, 2026: Added Apple Developer ID code signing, hardened runtime, DMG signing, and Apple notarization support
flutter build macos --release

APP="build/macos/Build/Products/Release/MagicSoftSQL.app"
VERSION=$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml | tr -d ' ')
OUT="build/MagicSoftSQL-${VERSION}.dmg"
ENTITLEMENTS="macos/Runner/Release.entitlements"

# Previous inlined signing logic:
# # 1. Resolve signing identity (env CODESIGN_IDENTITY or auto-detect from keychain)
# IDENTITY="${CODESIGN_IDENTITY:-}"
# if [ -z "$IDENTITY" ]; then
#   IDENTITY=$(security find-identity -p codesigning -v | grep "Developer ID Application:" | head -n 1 | sed -E 's/.*"(Developer ID Application: [^"]+)".*/\1/' || true)
# fi
#
# if [ -n "$IDENTITY" ]; then
#   echo "==> Found Apple Developer ID identity: $IDENTITY"
#   echo "==> Signing embedded frameworks and libraries..."
#   if [ -d "$APP/Contents/Frameworks" ]; then
#     find "$APP/Contents/Frameworks" -depth \( -name "*.framework" -o -name "*.dylib" \) | while read -r fw; do
#       echo "    Signing: $(basename "$fw")"
#       codesign --force --verify --verbose --timestamp --options runtime --sign "$IDENTITY" "$fw"
#     done
#   fi
#
#   echo "==> Signing main application bundle with hardened runtime..."
#   codesign --force --verify --verbose --timestamp --options runtime --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
#
#   echo "==> Verifying app bundle signature..."
#   codesign --verify --deep --strict --verbose=2 "$APP"
# else
#   echo "==> WARNING: No Developer ID Application identity found in keychain. Skipping app bundle signing."
# fi

# Gene - Oct 7, 2026: Delegate application bundle signing to standalone scripts/sign_macos_app.sh
bash scripts/sign_macos_app.sh "$APP"

IDENTITY="${CODESIGN_IDENTITY:-${MACOS_SIGN_IDENTITY:-}}"
if [ -z "$IDENTITY" ]; then
  IDENTITY=$(security find-identity -p codesigning -v | grep "Developer ID Application:" | head -n 1 | sed -E 's/.*"(Developer ID Application: [^"]+)".*/\1/' || true)
fi

# 2. Stage and create the DMG
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$OUT"
echo "==> Creating DMG: $OUT"
hdiutil create -volname "MagicSoftSQL" -srcfolder "$STAGE" -ov -format UDZO "$OUT"
echo "Created $OUT"

# 3. Sign the DMG
if [ -n "$IDENTITY" ]; then
  echo "==> Signing DMG container..."
  codesign --force --verify --verbose --timestamp --sign "$IDENTITY" "$OUT"
  codesign --verify --verbose=2 "$OUT"
fi

# 4. Apple Notarization (if credentials are provided)
# Previous implementation:
# NOTARY_PROFILE="${NOTARY_PROFILE:-${KEYCHAIN_PROFILE:-}}"

# Gene - Oct 09, 2026: Default to existing stored keychain profile 'batterie-notary' if NOTARY_PROFILE is not explicitly set
NOTARY_PROFILE="${NOTARY_PROFILE:-${KEYCHAIN_PROFILE:-}}"
if [ -z "$NOTARY_PROFILE" ]; then
  if xcrun notarytool history --keychain-profile "batterie-notary" >/dev/null 2>&1; then
    NOTARY_PROFILE="batterie-notary"
  elif xcrun notarytool history --keychain-profile "notarytool-profile" >/dev/null 2>&1; then
    NOTARY_PROFILE="notarytool-profile"
  fi
fi

if [ -n "$NOTARY_PROFILE" ]; then
  echo "==> Submitting $OUT for Apple notarization using keychain profile '$NOTARY_PROFILE'..."
  xcrun notarytool submit "$OUT" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "==> Stapling notarization ticket to DMG..."
  xcrun stapler staple "$OUT"
  echo "==> Stapling notarization ticket to app bundle..."
  xcrun stapler staple "$APP" || true
  echo "==> Validating Gatekeeper acceptance..."
  spctl --assess --type open --context context:primary-signature -v "$OUT" || true
elif [ -n "${NOTARY_KEY_PATH:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER_ID:-}" ]; then
  echo "==> Submitting $OUT for Apple notarization using App Store Connect API Key..."
  xcrun notarytool submit "$OUT" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --wait
  echo "==> Stapling notarization ticket to DMG..."
  xcrun stapler staple "$OUT"
  echo "==> Stapling notarization ticket to app bundle..."
  xcrun stapler staple "$APP" || true
elif [ -n "${NOTARY_APPLE_ID:-}" ] && [ -n "${NOTARY_APP_PASSWORD:-}" ] && [ -n "${NOTARY_TEAM_ID:-}" ]; then
  echo "==> Submitting $OUT for Apple notarization using Apple ID and app-specific password..."
  xcrun notarytool submit "$OUT" --apple-id "$NOTARY_APPLE_ID" --password "$NOTARY_APP_PASSWORD" --team-id "$NOTARY_TEAM_ID" --wait
  echo "==> Stapling notarization ticket to DMG..."
  xcrun stapler staple "$OUT"
  echo "==> Stapling notarization ticket to app bundle..."
  xcrun stapler staple "$APP" || true
else
  echo ""
  echo "======================================================================"
  echo "==> DMG successfully created and signed with Apple Developer ID!"
  echo "    To notarize with Apple so Gatekeeper allows double-click open without prompts:"
  echo "    1. Store your notary credentials once (requires an Apple ID App-Specific Password):"
  echo "       xcrun notarytool store-credentials \"notarytool-profile\" \\"
  echo "         --apple-id \"bluegene37@outlook.com\" \\"
  echo "         --team-id \"T7LB768N2Z\""
  echo "    2. Run notarization & stapling:"
  echo "       xcrun notarytool submit \"$OUT\" --keychain-profile \"notarytool-profile\" --wait"
  echo "       xcrun stapler staple \"$OUT\""
  echo "    Alternatively, re-run with: NOTARY_PROFILE=\"notarytool-profile\" bash scripts/build_macos_dmg.sh"
  echo "======================================================================"
fi

