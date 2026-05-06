#!/usr/bin/env bash
set -euo pipefail

APP_NAME="NavRead"
BUNDLE_ID="com.pranav.navread"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="debug"
PRODUCT_DIR="$ROOT_DIR/.build/$CONFIGURATION"
BUNDLE_DIR="$ROOT_DIR/dist/$APP_NAME.app"
EXECUTABLE_PATH="$PRODUCT_DIR/$APP_NAME"
RESOURCE_SOURCE_DIR="$ROOT_DIR/Sources/NavRead/Resources"

MODE="${1:-}"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
swift build -c "$CONFIGURATION"

rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"
cp "$EXECUTABLE_PATH" "$BUNDLE_DIR/Contents/MacOS/$APP_NAME"
if [ -d "$RESOURCE_SOURCE_DIR" ]; then
  cp -R "$RESOURCE_SOURCE_DIR"/. "$BUNDLE_DIR/Contents/Resources/"
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
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

/usr/bin/open -n "$BUNDLE_DIR"

case "$MODE" in
  --verify)
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    echo "$APP_NAME launched"
    ;;
  --logs)
    /usr/bin/log stream --style compact --predicate "process == '$APP_NAME'"
    ;;
  --telemetry)
    /usr/bin/log stream --info --style compact --predicate "subsystem == 'com.pranav.navread'"
    ;;
  ""|--debug)
    ;;
  *)
    echo "Unknown mode: $MODE" >&2
    exit 2
    ;;
esac
