#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
INSTALL_DIR="$HOME/Applications"
APP_PATH="$INSTALL_DIR/KeyBloom.app"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "此启动脚本只能在 macOS 上运行。"
    read -r -p "按回车键退出…"
    exit 1
fi

if ! command -v xcrun >/dev/null 2>&1 || ! command -v swiftc >/dev/null 2>&1; then
    echo "需要安装 Apple 命令行工具（不需要安装完整 Xcode）。"
    xcode-select --install || true
    echo "完成安装后，再双击一次“运行KeyBloom.command”。"
    read -r -p "按回车键退出…"
    exit 0
fi

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
ICONSET_DIR="$BUILD_DIR/KeyBloom.iconset"
ICON_PNG="$PROJECT_DIR/Resources/KeyBloomIcon.png"
mkdir -p "$BUILD_DIR/ModuleCache" "$ICONSET_DIR" "$INSTALL_DIR" "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

echo "正在生成 KeyBloom 应用图标…"
sips -z 16 16 "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_PNG" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET_DIR" -o "$APP_PATH/Contents/Resources/KeyBloomIcon.icns"

echo "正在编译 KeyBloom…"
xcrun --sdk macosx swiftc \
    -sdk "$SDK_PATH" \
    -module-cache-path "$BUILD_DIR/ModuleCache" \
    -swift-version 5 \
    -parse-as-library \
    -framework SwiftUI \
    -framework Charts \
    -framework AppKit \
    -framework CoreGraphics \
    -framework Combine \
    -framework IOKit \
    -framework ServiceManagement \
    "$PROJECT_DIR/KeyBloom/KeyBloomApp.swift" \
    "$PROJECT_DIR/KeyBloom/KeyboardMonitor.swift" \
    "$PROJECT_DIR/KeyBloom/StatsStore.swift" \
    "$PROJECT_DIR/KeyBloom/DashboardView.swift" \
    "$PROJECT_DIR/KeyBloom/KeyboardHeatmapView.swift" \
    -o "$APP_PATH/Contents/MacOS/KeyBloom"

cat > "$APP_PATH/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>KeyBloom</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.keybloom</string>
    <key>CFBundleName</key>
    <string>KeyBloom</string>
    <key>CFBundleDisplayName</key>
    <string>KeyBloom</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>KeyBloomIcon</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - --identifier com.local.keybloom --timestamp=none "$APP_PATH"
echo "KeyBloom 已构建，正在打开。"
open "$APP_PATH"
echo "如果 macOS 阻止首次打开，请在“系统设置 > 隐私与安全性”中选择“仍要打开”。"
read -r -p "按回车键关闭此窗口…"
