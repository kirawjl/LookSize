#!/bin/bash
set -euo pipefail

pkill -x LookSize 2>/dev/null || true

if [ -d "/Applications/LookSize.app" ]; then
    if [ -w "/Applications" ]; then
        rm -rf "/Applications/LookSize.app"
    else
        sudo rm -rf "/Applications/LookSize.app"
    fi
fi

printf 'LookSize 已从 /Applications 删除。\n'
printf '辅助功能授权记录需在“系统设置 → 隐私与安全性 → 辅助功能”中手动移除。\n'
