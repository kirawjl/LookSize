#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="LookSize"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
APP_BINARY="$APP_DIR/Contents/MacOS/$APP_NAME"
INFO_PLIST="$APP_DIR/Contents/Info.plist"
REBUILD="${REBUILD:-1}"
UNIVERSAL="${UNIVERSAL:-1}"

if [ "$REBUILD" = "1" ] || [ ! -x "$APP_BINARY" ]; then
    UNIVERSAL="$UNIVERSAL" "$ROOT_DIR/scripts/build-app.sh"
fi

codesign --verify --deep --strict "$APP_DIR"
plutil -lint "$INFO_PLIST" >/dev/null

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
ARCHS="$(lipo -archs "$APP_BINARY")"
if [[ " $ARCHS " == *" x86_64 "* ]] && [[ " $ARCHS " == *" arm64 "* ]]; then
    ARCH_LABEL="universal"
else
    ARCH_LABEL="${ARCHS// /-}"
fi

OUTPUT_DMG="${OUTPUT_DMG:-$ROOT_DIR/dist/$APP_NAME-$VERSION-$ARCH_LABEL.dmg}"
CHECKSUM_FILE="$OUTPUT_DMG.sha256"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/looksize-dmg.XXXXXX")"
STAGING_DIR="$TEMP_DIR/staging"
MOUNT_DIR="$TEMP_DIR/mount"
MOUNTED=0

cleanup() {
    if [ "$MOUNTED" = "1" ]; then
        hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
    fi
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

mkdir -p "$STAGING_DIR" "$MOUNT_DIR" "$(dirname "$OUTPUT_DMG")"
ditto "$APP_DIR" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

cat > "$STAGING_DIR/安装说明.txt" <<EOF
LookSize $VERSION 安装说明

1. 将 LookSize.app 拖到旁边的 Applications 文件夹。
2. 在“应用程序”中打开 LookSize。
3. 如果 macOS 阻止首次打开：
   系统设置 → 隐私与安全性 → 安全性 → 仍要打开。
4. 按提示授予：
   - 辅助功能权限
   - 自动化 → Finder 权限

说明：此免费构建采用临时（Ad Hoc）签名，没有 Apple Developer ID 和公证。
请仅安装来自可信来源且校验值一致的安装包；无需也不建议关闭 Gatekeeper。
EOF

rm -f "$OUTPUT_DMG" "$CHECKSUM_FILE"
printf '制作 DMG（%s，%s）…\n' "$VERSION" "$ARCH_LABEL"
hdiutil create \
    -volname "$APP_NAME" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    -srcfolder "$STAGING_DIR" \
    -ov \
    "$OUTPUT_DMG" >/dev/null

hdiutil verify "$OUTPUT_DMG" >/dev/null
hdiutil attach "$OUTPUT_DMG" \
    -readonly \
    -nobrowse \
    -mountpoint "$MOUNT_DIR" >/dev/null
MOUNTED=1

test -x "$MOUNT_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME"
test -L "$MOUNT_DIR/Applications"
codesign --verify --deep --strict "$MOUNT_DIR/$APP_NAME.app"

hdiutil detach "$MOUNT_DIR" -quiet >/dev/null
MOUNTED=0

CHECKSUM="$(shasum -a 256 "$OUTPUT_DMG" | awk '{print $1}')"
printf '%s  %s\n' "$CHECKSUM" "$(basename "$OUTPUT_DMG")" > "$CHECKSUM_FILE"

printf '\n安装包已生成：\n  DMG: %s\n  SHA-256: %s\n  架构: %s\n' \
    "$OUTPUT_DMG" "$CHECKSUM" "$ARCHS"
printf '\n安装：双击 DMG，将 %s.app 拖到 Applications。\n' "$APP_NAME"
printf '首次打开若被拦截：系统设置 → 隐私与安全性 → 仍要打开。\n'
