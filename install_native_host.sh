#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOURCE_DIR="$ROOT_DIR/Sources/Remlink/Resources"
HOST_NAME="com.landlord.remlink"
HOST_SCRIPT="/Applications/Remlink.app/Contents/Helpers/RemlinkHelper.app/Contents/MacOS/RemlinkHelper"
EXTENSION_MANIFEST="$RESOURCE_DIR/extension/manifest.json"

EXTENSION_ID="$(python3 - "$EXTENSION_MANIFEST" <<'PY'
import base64
import hashlib
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    key = json.load(f)["key"]

digest = hashlib.sha256(base64.b64decode(key)).digest()[:16]
alphabet = "abcdefghijklmnop"
print("".join(alphabet[b >> 4] + alphabet[b & 15] for b in digest))
PY
)"

if [[ ! -x "$HOST_SCRIPT" ]]; then
  echo "找不到 RemlinkHelper: $HOST_SCRIPT" >&2
  echo "请先运行 ./build_app.sh，并把 .build/Remlink.app 安装到 /Applications/Remlink.app。" >&2
  exit 1
fi

HOST_JSON="$(mktemp)"
cat > "$HOST_JSON" <<JSON
{
  "name": "$HOST_NAME",
  "description": "Save Chromium links to Reminders with Remlink",
  "path": "$HOST_SCRIPT",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://$EXTENSION_ID/"
  ]
}
JSON

TARGET_DIRS=(
  "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
  "$HOME/Library/Application Support/Chromium/NativeMessagingHosts"
  "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts"
  "$HOME/Library/Application Support/Microsoft Edge/NativeMessagingHosts"
  "$HOME/Library/Application Support/Arc/User Data/NativeMessagingHosts"
  "$HOME/Library/Application Support/net.imput.helium/NativeMessagingHosts"
)

for dir in "${TARGET_DIRS[@]}"; do
  mkdir -p "$dir"
  cp "$HOST_JSON" "$dir/$HOST_NAME.json"
done

rm -f "$HOST_JSON"

cat <<EOF
Native Messaging host 已安装。

扩展 ID:
  $EXTENSION_ID

下一步：
  1. 打开 Chromium 系浏览器的扩展管理页。
  2. 开启“开发者模式”。
  3. 选择“加载已解压的扩展程序”。
  4. 选择这个目录：
     $RESOURCE_DIR/extension
EOF
