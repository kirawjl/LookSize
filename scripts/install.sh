#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_APP="$ROOT_DIR/dist/LookSize.app"
DESTINATION_APP="/Applications/LookSize.app"

if [ ! -x "$SOURCE_APP/Contents/MacOS/LookSize" ] || [ "${REBUILD:-0}" = "1" ]; then
    UNIVERSAL="${UNIVERSAL:-1}" "$ROOT_DIR/scripts/build-app.sh"
else
    printf '使用现有构建产物：%s\n' "$SOURCE_APP"
fi

codesign --verify --deep --strict "$SOURCE_APP"
pkill -x LookSize 2>/dev/null || true
sleep 1

if [ -w "/Applications" ]; then
    rm -rf "$DESTINATION_APP"
    ditto "$SOURCE_APP" "$DESTINATION_APP"
else
    sudo rm -rf "$DESTINATION_APP"
    sudo ditto "$SOURCE_APP" "$DESTINATION_APP"
fi

printf '已安装：%s\n' "$DESTINATION_APP"
open "$DESTINATION_APP"
