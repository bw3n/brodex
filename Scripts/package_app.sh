#!/bin/zsh
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="Brodex"
LOGO_SOURCE="/Users/jerng5/Desktop/PNG/BRODEX.png"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$DIST_DIR/${APP_NAME}.iconset"
ICON_FILE="$RESOURCES_DIR/${APP_NAME}.icns"

echo "Building release binary..."
swift build -c release --package-path "$ROOT_DIR"
BIN_DIR=$(swift build -c release --package-path "$ROOT_DIR" --show-bin-path)
EXECUTABLE_PATH="$BIN_DIR/BrodexV1Frontend"

if [[ ! -f "$LOGO_SOURCE" ]]; then
  echo "Logo source not found at $LOGO_SOURCE" >&2
  exit 1
fi

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "Release executable not found at $EXECUTABLE_PATH" >&2
  exit 1
fi

rm -rf "$APP_DIR" "$ICONSET_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "Generating app icon from $LOGO_SOURCE..."
swift "$ROOT_DIR/Scripts/generate_placeholder_icon.swift" "$LOGO_SOURCE" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"
rm -rf "$ICONSET_DIR"

echo "Creating app bundle..."
cp "$ROOT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$EXECUTABLE_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

echo "Signing app bundle..."
codesign --force --deep --sign - "$APP_DIR"

echo "Packaged app at:"
echo "  $APP_DIR"
