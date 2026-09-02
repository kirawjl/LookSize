#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

CONFIGURATION="${CONFIGURATION:-release}"
UNIVERSAL="${UNIVERSAL:-0}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP_DIR="$ROOT_DIR/dist/LookSize.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
CLI_DIR="$ROOT_DIR/dist/bin"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$CLI_DIR"

if [ "$UNIVERSAL" = "1" ]; then
    X86_SCRATCH="$ROOT_DIR/.build"
    ARM_SCRATCH="$ROOT_DIR/.build-arm64"

    printf '构建 LookSize（%s，x86_64）…\n' "$CONFIGURATION"
    swift build \
        -c "$CONFIGURATION" \
        --triple x86_64-apple-macosx13.0 \
        --scratch-path "$X86_SCRATCH" \
        --product LookSize
    swift build \
        -c "$CONFIGURATION" \
        --triple x86_64-apple-macosx13.0 \
        --scratch-path "$X86_SCRATCH" \
        --product looksize-inspect
    X86_BIN_DIR="$(swift build \
        -c "$CONFIGURATION" \
        --triple x86_64-apple-macosx13.0 \
        --scratch-path "$X86_SCRATCH" \
        --show-bin-path)"

    printf '构建 LookSize（%s，arm64）…\n' "$CONFIGURATION"
    swift build \
        -c "$CONFIGURATION" \
        --triple arm64-apple-macosx13.0 \
        --scratch-path "$ARM_SCRATCH" \
        --product LookSize
    swift build \
        -c "$CONFIGURATION" \
        --triple arm64-apple-macosx13.0 \
        --scratch-path "$ARM_SCRATCH" \
        --product looksize-inspect
    ARM_BIN_DIR="$(swift build \
        -c "$CONFIGURATION" \
        --triple arm64-apple-macosx13.0 \
        --scratch-path "$ARM_SCRATCH" \
        --show-bin-path)"

    lipo -create \
        "$X86_BIN_DIR/LookSize" \
        "$ARM_BIN_DIR/LookSize" \
        -output "$MACOS_DIR/LookSize"
    lipo -create \
        "$X86_BIN_DIR/looksize-inspect" \
        "$ARM_BIN_DIR/looksize-inspect" \
        -output "$CLI_DIR/looksize-inspect"
    chmod 755 "$MACOS_DIR/LookSize" "$CLI_DIR/looksize-inspect"
else
    printf '构建 LookSize（%s，本机架构）…\n' "$CONFIGURATION"
    swift build -c "$CONFIGURATION" --product LookSize
    swift build -c "$CONFIGURATION" --product looksize-inspect

    BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
    install -m 755 "$BIN_DIR/LookSize" "$MACOS_DIR/LookSize"
    install -m 755 "$BIN_DIR/looksize-inspect" "$CLI_DIR/looksize-inspect"
fi

install -m 644 "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
install -m 644 "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR" >/dev/null
codesign --verify --deep --strict "$APP_DIR"

printf '\n构建完成：\n  App: %s\n  CLI: %s\n' "$APP_DIR" "$CLI_DIR/looksize-inspect"
file "$MACOS_DIR/LookSize"
printf '\n启动：open "%s"\n' "$APP_DIR"
