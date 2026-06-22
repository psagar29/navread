#!/usr/bin/env bash
set -euo pipefail

APP_NAME="NavRead"
BUNDLE_ID="com.pranav.navread"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-0.1.1}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
CONFIGURATION="release"
DMG_PATH="$ROOT_DIR/dist/$APP_NAME.dmg"
RESOURCE_SOURCE_DIR="$ROOT_DIR/Sources/NavRead/Resources"
RESOURCE_BUNDLE_NAME="${APP_NAME}_${APP_NAME}.bundle"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"
REQUIRE_NOTARIZATION="${REQUIRE_NOTARIZATION:-0}"
STAGING_ROOT="$(mktemp -d "$ROOT_DIR/.build/package.XXXXXX")"
BUNDLE_DIR="$STAGING_ROOT/$APP_NAME.app"

cleanup() {
  rm -rf "$STAGING_ROOT"
}
trap cleanup EXIT

cd "$ROOT_DIR"
rm -f "$DMG_PATH"
rm -f "$ROOT_DIR"/dist/"$APP_NAME"-*.dmg
mkdir -p "$BUNDLE_DIR/Contents/MacOS" "$BUNDLE_DIR/Contents/Resources" "$ROOT_DIR/dist"

swift build -c "$CONFIGURATION"
PRODUCT_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
RESOURCE_BUNDLE_PATH="$PRODUCT_DIR/$RESOURCE_BUNDLE_NAME"
cp "$PRODUCT_DIR/$APP_NAME" "$BUNDLE_DIR/Contents/MacOS/$APP_NAME"
if [ -d "$RESOURCE_SOURCE_DIR" ]; then
  cp -R "$RESOURCE_SOURCE_DIR"/. "$BUNDLE_DIR/Contents/Resources/"
fi
if [ -d "$RESOURCE_BUNDLE_PATH" ]; then
  cp -R "$RESOURCE_BUNDLE_PATH" "$BUNDLE_DIR/Contents/Resources/$RESOURCE_BUNDLE_NAME"
fi

cat > "$BUNDLE_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

if [ -z "$SIGN_IDENTITY" ]; then
  SIGN_IDENTITY="$(security find-identity -p codesigning -v | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -n 1 || true)"
fi

if [ -n "$SIGN_IDENTITY" ]; then
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$BUNDLE_DIR"
  codesign --verify --deep --strict --verbose=2 "$BUNDLE_DIR"
else
  echo "warning: no Developer ID Application signing identity found; using ad-hoc local signing" >&2
  codesign --force --deep --sign - "$BUNDLE_DIR"
  codesign --verify --deep --strict --verbose=2 "$BUNDLE_DIR"
  if [ "$REQUIRE_NOTARIZATION" = "1" ]; then
    echo "error: REQUIRE_NOTARIZATION=1 but SIGN_IDENTITY is missing" >&2
    exit 1
  fi
fi

hdiutil create -volname "$APP_NAME" -srcfolder "$BUNDLE_DIR" -ov -format UDZO "$DMG_PATH"

if [ -n "$SIGN_IDENTITY" ]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
else
  codesign --force --sign - "$DMG_PATH" || true
fi

if [ -n "$NOTARY_KEYCHAIN_PROFILE" ]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
elif [ "$REQUIRE_NOTARIZATION" = "1" ]; then
  echo "error: REQUIRE_NOTARIZATION=1 but NOTARY_KEYCHAIN_PROFILE is missing" >&2
  exit 1
else
  echo "warning: NOTARY_KEYCHAIN_PROFILE not set; skipping Apple notarization" >&2
fi

spctl -a -t open --context context:primary-signature -vv "$DMG_PATH" || true
echo "Built $DMG_PATH"
