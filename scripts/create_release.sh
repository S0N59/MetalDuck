#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SDKROOT_PATH="${SDKROOT:-$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

cd "$ROOT_DIR"

if [[ ! -d "$SDKROOT_PATH" ]]; then
  echo "SDK not found at: $SDKROOT_PATH" >&2
  exit 1
fi

echo "Building release binary..."
SDKROOT="$SDKROOT_PATH" swift build -c release

BIN_DIR="$ROOT_DIR/.build/release"
PRODUCT_BIN="$BIN_DIR/MetalDuck"
BUNDLE_DIR="$BIN_DIR/MetalDuck_MetalDuck.bundle"
ICON_FILE="$ROOT_DIR/Sources/MetalDuck/Assets/AppIcon.icns"

if [[ ! -f "$PRODUCT_BIN" ]]; then
  echo "Release binary not found: $PRODUCT_BIN" >&2
  exit 1
fi

APP_NAME="MetalDuck"
APP_BUNDLE_NAME="${APP_NAME}.app"
STAGE_DIR="$ROOT_DIR/dist/MetalDuck-macos-arm64"
DMG_STAGE_DIR="$ROOT_DIR/dist/MetalDuck-dmg-root"
APP_DIR="$STAGE_DIR/$APP_BUNDLE_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
DMG_PATH="$ROOT_DIR/dist/MetalDuck-macos-arm64.dmg"

rm -rf "$STAGE_DIR" "$DMG_STAGE_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$DMG_STAGE_DIR"

cp "$PRODUCT_BIN" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"
if [[ -d "$BUNDLE_DIR" ]]; then
  cp -R "$BUNDLE_DIR" "$RESOURCES_DIR/"
fi
if [[ -f "$ICON_FILE" ]]; then
  cp "$ICON_FILE" "$RESOURCES_DIR/AppIcon.icns"
fi

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>MetalDuck</string>
  <key>CFBundleDisplayName</key>
  <string>MetalDuck</string>
  <key>CFBundleIdentifier</key>
  <string>com.nycolazs.metaldduck</string>
  <key>CFBundleVersion</key>
  <string>1.0.0</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleExecutable</key>
  <string>MetalDuck</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon.icns</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

touch "$CONTENTS_DIR/PkgInfo"
echo "APPL????" > "$CONTENTS_DIR/PkgInfo"

# Re-sign the full app bundle after assembling it, so Gatekeeper sees a valid signature.
codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

# Assemble the DMG stage directory
cp -R "$APP_DIR" "$DMG_STAGE_DIR/"
ln -s /Applications "$DMG_STAGE_DIR/Applications"

# Set up the DMG background
mkdir -p "$DMG_STAGE_DIR/.background"
if [[ -f "$ROOT_DIR/Sources/MetalDuck/Assets/dmg_background.png" ]]; then
  cp "$ROOT_DIR/Sources/MetalDuck/Assets/dmg_background.png" "$DMG_STAGE_DIR/.background/background.png"
fi

# Create a temporary empty DMG to configure layout
TEMP_DMG="${DMG_PATH}.temp.dmg"
rm -f "$TEMP_DMG" "$DMG_PATH"

hdiutil create -srcfolder "$DMG_STAGE_DIR" -volname "MetalDuck" -format UDRW -ov "$TEMP_DMG"

# Mount the temporary DMG
echo "Mounting temporary DMG to configure layout..."
MOUNT_DIR=$(mktemp -d /tmp/metaldduck_mount.XXXXXX)
hdiutil attach "$TEMP_DMG" -mountpoint "$MOUNT_DIR" -noautoopen

# Use AppleScript to configure the DMG window
echo "Configuring DMG layout via AppleScript..."
VOLUME_NAME=$(basename "$MOUNT_DIR")
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 100, 1000, 500}
        set viewOptions to the icon view options of container window
        set icon size of viewOptions to 100
        set arrangement of viewOptions to not arranged
        set background picture of viewOptions to file ".background:background.png"
        set position of item "MetalDuck.app" of container window to {170, 200}
        set position of item "Applications" of container window to {430, 200}
        close
    end tell
end tell
APPLESCRIPT

# Give Finder a moment to write its .DS_Store
sleep 2

# Set the DMG root to be invisible (optional, but cleaner)
# Set custom icon for the volume if needed

# Detach and convert to compressed DMG
hdiutil detach "$MOUNT_DIR"
hdiutil convert "$TEMP_DMG" -format UDZO -o "$DMG_PATH"
rm -f "$TEMP_DMG"
rmdir "$MOUNT_DIR"

echo "Release package created: $DMG_PATH"
