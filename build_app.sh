#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

swift build -c release

APP_DIR="$ROOT_DIR/.build/Remlink.app"
EXECUTABLE="$ROOT_DIR/.build/release/Remlink"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/Remlink"

RESOURCE_BUNDLE="$(find "$ROOT_DIR/.build" -name 'Remlink_Remlink.bundle' -type d | head -n 1)"
if [[ -n "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/"
  APP_ICON="$(find "$RESOURCE_BUNDLE" -path '*/app/AppIcon.icns' -type f | head -n 1)"
  if [[ -n "$APP_ICON" ]]; then
    cp "$APP_ICON" "$APP_DIR/Contents/Resources/AppIcon.icns"
  fi
fi

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Remlink</string>
  <key>CFBundleIdentifier</key>
  <string>com.landlord.Remlink</string>
  <key>CFBundleName</key>
  <string>Remlink</string>
  <key>CFBundleDisplayName</key>
  <string>Remlink</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSRemindersUsageDescription</key>
  <string>用于导出、导入和管理“链接”提醒事项列表中的链接收藏。</string>
</dict>
</plist>
PLIST

echo "$APP_DIR"
