#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="jocalhost"
APP_IDENTIFIER="de.josuasievers.jocalhost"
PRODUCT_NAME="jocalhost"
CLI_NAME="jocalhostctl"
MCP_NAME="jocalhost-mcp"
CONFIGURATION="${CONFIGURATION:-release}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIST_DIR="$ROOT_DIR/dist.noindex"
APP_DIR="$APP_DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE="$ROOT_DIR/Assets/AppIcon/AppIcon.svg"
ICON_FILE="$ROOT_DIR/Assets/AppIcon/AppIcon.icns"
IDENTITY="${CODE_SIGN_IDENTITY:-}"

cd "$ROOT_DIR"

swift build -c "$CONFIGURATION"

rm -rf "$APP_DIR"
rm -rf "$DIST_DIR/$APP_NAME.app" "$DIST_DIR/Localhost.app" "$DIST_DIR/Jocalhost.app"
rm -rf "$APP_DIST_DIR/Localhost.app" "$APP_DIST_DIR/Jocalhost.app"
rm -f "$DIST_DIR/localhostctl" "$DIST_DIR/localhost-mcp"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$DIST_DIR" "$APP_DIST_DIR"
touch "$APP_DIST_DIR/.metadata_never_index"

cp ".build/$CONFIGURATION/$PRODUCT_NAME" "$MACOS_DIR/$APP_NAME"
cp ".build/$CONFIGURATION/$CLI_NAME" "$DIST_DIR/$CLI_NAME"
cp ".build/$CONFIGURATION/$MCP_NAME" "$DIST_DIR/$MCP_NAME"

generate_app_icon() {
  local iconset_dir="$ROOT_DIR/.build/AppIcon.iconset"
  local render_dir="$ROOT_DIR/.build/app-icon-render"
  local rendered_png="$render_dir/AppIcon.svg.png"

  if [[ ! -f "$ICON_SOURCE" ]]; then
    return
  fi

  rm -rf "$iconset_dir" "$render_dir"
  mkdir -p "$iconset_dir" "$render_dir"

  qlmanage -t -s 1024 -o "$render_dir" "$ICON_SOURCE" >/dev/null 2>&1

  if [[ ! -f "$rendered_png" ]]; then
    echo "Failed to render $ICON_SOURCE" >&2
    exit 1
  fi

  sips -z 16 16 "$rendered_png" --out "$iconset_dir/icon_16x16.png" >/dev/null
  sips -z 32 32 "$rendered_png" --out "$iconset_dir/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$rendered_png" --out "$iconset_dir/icon_32x32.png" >/dev/null
  sips -z 64 64 "$rendered_png" --out "$iconset_dir/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$rendered_png" --out "$iconset_dir/icon_128x128.png" >/dev/null
  sips -z 256 256 "$rendered_png" --out "$iconset_dir/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$rendered_png" --out "$iconset_dir/icon_256x256.png" >/dev/null
  sips -z 512 512 "$rendered_png" --out "$iconset_dir/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$rendered_png" --out "$iconset_dir/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$rendered_png" --out "$iconset_dir/icon_512x512@2x.png" >/dev/null

  iconutil -c icns "$iconset_dir" --output "$ICON_FILE"
}

generate_app_icon

if [[ -f "$ICON_FILE" ]]; then
  cp "$ICON_FILE" "$RESOURCES_DIR/AppIcon.icns"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$APP_IDENTIFIER</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon.icns</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

sign_path() {
  local path="$1"

  if [[ -n "$IDENTITY" ]]; then
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$path"
  elif [[ "$path" == "$APP_DIR" ]]; then
    codesign --force --sign - --requirements "=designated => identifier \"$APP_IDENTIFIER\"" "$path"
  else
    codesign --force --sign - "$path"
  fi
}

sign_path "$DIST_DIR/$CLI_NAME"
sign_path "$DIST_DIR/$MCP_NAME"
sign_path "$APP_DIR"

echo "$APP_DIR"
