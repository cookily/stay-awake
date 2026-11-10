#!/bin/bash
# 构建 StayAwake 菜单栏应用，输出到 ~/Applications/StayAwake.app
# 与 ~/gitlab-pipeline-monitor/build.sh 同一套流程
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="StayAwake"
APP_DIR="$HOME/Applications/$APP_NAME.app"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp Info.plist "$APP_DIR/Contents/Info.plist"
# 通用二进制（universal）：Intel 与 Apple Silicon 都支持
swiftc -swift-version 5 -O -target x86_64-apple-macos12.0 -o "$APP_DIR/Contents/MacOS/$APP_NAME.x86_64" main.swift
swiftc -swift-version 5 -O -target arm64-apple-macos12.0 -o "$APP_DIR/Contents/MacOS/$APP_NAME.arm64" main.swift
lipo -create "$APP_DIR/Contents/MacOS/$APP_NAME.x86_64" "$APP_DIR/Contents/MacOS/$APP_NAME.arm64" -output "$APP_DIR/Contents/MacOS/$APP_NAME"
rm -f "$APP_DIR/Contents/MacOS/$APP_NAME.x86_64" "$APP_DIR/Contents/MacOS/$APP_NAME.arm64"
# ad-hoc 签名：未签名应用部分系统接口（通知/SMAppService）会静默失败
codesign --force --sign - "$APP_DIR"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"
echo "已构建: $APP_DIR"
