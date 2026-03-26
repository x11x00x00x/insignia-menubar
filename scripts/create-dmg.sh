#!/bin/bash
# Create a signed DMG for Insignia Menubar (run after Release build).
# Usage: ./create-dmg.sh [path-to-built.app]
# Or set APP_PATH and run from project root.

set -e
APP_PATH="${1:-${APP_PATH}}"
if [ -z "$APP_PATH" ]; then
  # Default: use most recent Release build
  DERIVED="$HOME/Library/Developer/Xcode/DerivedData/Insignia_Menubar-esdyqqzirdkqkgfldnwjttdsqdus/Build/Products/Release"
  APP_PATH="$DERIVED/Insignia Menubar.app"
fi
if [ ! -d "$APP_PATH" ]; then
  echo "App not found at: $APP_PATH"
  echo "Build for Release first, or pass path: $0 /path/to/Insignia\\ Menubar.app"
  exit 1
fi

PRODUCT_NAME="Insignia Menubar"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DMG_NAME="${PRODUCT_NAME}.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

echo "Copying app to staging..."
cp -R "$APP_PATH" "$STAGING/"

# Optional: sign with Developer ID (set SIGN_IDENTITY to your "Developer ID Application: ..." name)
if [ -n "$SIGN_IDENTITY" ]; then
  echo "Signing with: $SIGN_IDENTITY"
  codesign --force --deep --sign "$SIGN_IDENTITY" "$STAGING/$PRODUCT_NAME.app"
fi

echo "Creating DMG..."
DMG_OUT="$PROJECT_DIR/$DMG_NAME"
rm -f "$DMG_OUT"
hdiutil create -volname "$PRODUCT_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_OUT"

echo "Created: $DMG_OUT"
