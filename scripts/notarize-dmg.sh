#!/bin/bash
# Notarize and staple the signed DMG so it opens on other Macs.
# Run this AFTER you've run: xcrun notarytool store-credentials "notarytool-profile" ...
# Usage: ./scripts/notarize-dmg.sh [path-to-dmg]

set -e
DMG="${1:-Insignia Menubar.dmg}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

if [ ! -f "$DMG" ]; then
  echo "DMG not found: $DMG"
  echo "Usage: $0 [Insignia Menubar_signed.dmg]"
  exit 1
fi

echo "Submitting to Apple for notarization (this may take 1–2 minutes)..."
OUTPUT=$(mktemp -t notarytool.XXXXXX)
trap 'rm -f "$OUTPUT"' EXIT
if ! xcrun notarytool submit "$DMG" \
  --keychain-profile "notarytool-profile" \
  --wait 2>&1 | tee "$OUTPUT"; then
  echo ""
  echo "Notarization failed. Check the message above. Common fixes:"
  echo "  1. Build for Release in Xcode with Manual signing and 'Developer ID Application'."
  echo "  2. Ensure the .app has Hardened Runtime (target → Build Settings → ENABLE_HARDENED_RUNTIME = YES)."
  echo "  3. Use the DMG created by the build (Insignia Menubar.dmg), or create a new DMG from the built .app."
  exit 1
fi
if grep -q "status: Invalid" "$OUTPUT"; then
  echo ""
  echo "Notarization was rejected (status: Invalid). Do not staple."
  echo "Get the log: xcrun notarytool log <submission-id> --keychain-profile \"notarytool-profile\""
  exit 1
fi

echo ""
echo "Notarization accepted. Stapling ticket to DMG..."
xcrun stapler staple "$DMG"

echo ""
echo "Done. $DMG is notarized and stapled. Safe to distribute."
