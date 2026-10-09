#!/bin/bash
# 构建 MMac-clipboard.app：SPM 编译 → 组装 bundle → ad-hoc 签名
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> swift build (release)"
swift build -c release

APP="build/MMac-clipboard.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/MMacClipboard "$APP/Contents/MacOS/MMacClipboard"
cp Resources/Info.plist "$APP/Contents/Info.plist"

codesign --force --sign - "$APP"

echo "==> 完成: $APP"
