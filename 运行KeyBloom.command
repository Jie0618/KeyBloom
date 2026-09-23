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

# Quit the installed instance before replacing its executable. Otherwise `open`
# can activate the still-running old process after the new build is installed.
if /usr/bin/pgrep -x "KeyBloom" >/dev/null 2>&1; then
    /usr/bin/osascript -e 'tell application id "com.local.keybloom" to quit' >/dev/null 2>&1 || true
    for _ in {1..40}; do
        if ! /usr/bin/pgrep -x "KeyBloom" >/dev/null 2>&1; then
            break
        fi
        /bin/sleep 0.25
    done
    if /usr/bin/pgrep -x "KeyBloom" >/dev/null 2>&1; then
        echo "无法关闭正在运行的 KeyBloom。请从菜单栏退出 KeyBloom 后，再重新运行此脚本。"
        read -r -p "按回车键退出…"
        exit 1
    fi
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

SIGNING_IDENTITY_NAME="KeyBloom Local Signing"
SIGNING_STATE_DIR="$HOME/Library/Application Support/KeyBloom"
SIGNING_IDENTITY_MARKER="$SIGNING_STATE_DIR/signing-identity.sha1"
mkdir -p "$SIGNING_STATE_DIR"

normalize_keychain_path() {
    local candidate="$1"
    candidate="${candidate#"${candidate%%[![:space:]]*}"}"
    candidate="${candidate%"${candidate##*[![:space:]]}"}"
    candidate="${candidate#\"}"
    candidate="${candidate%\"}"
    if [[ "$candidate" == "~/"* ]]; then
        candidate="$HOME/${candidate:2}"
    elif [[ "$candidate" != /* ]]; then
        candidate="$HOME/Library/Keychains/$candidate"
    fi
    [[ -f "$candidate" ]] && printf '%s' "$candidate"
}

LOGIN_KEYCHAIN="$(normalize_keychain_path "$(/usr/bin/security default-keychain -d user 2>/dev/null || true)" || true)"
if [[ -z "$LOGIN_KEYCHAIN" ]]; then
    while IFS= read -r keychain_line; do
        keychain_line="${keychain_line#"${keychain_line%%[![:space:]]*}"}"
        keychain_line="${keychain_line#\"}"
        keychain_line="${keychain_line%\"}"
        keychain_path="$(normalize_keychain_path "$keychain_line" || true)"
        if [[ "$keychain_path" == */login.keychain-db || "$keychain_path" == */login.keychain ]]; then
            LOGIN_KEYCHAIN="$keychain_path"
            break
        fi
    done < <(/usr/bin/security list-keychains -d user 2>/dev/null || true)
fi

if [[ -n "$LOGIN_KEYCHAIN" ]]; then
    echo "将把签名身份保存在当前用户钥匙串中。"
else
    echo "无法解析钥匙串文件路径，将尝试使用 macOS 当前默认钥匙串。"
fi

find_signing_identity_hash() {
    if [[ -n "$LOGIN_KEYCHAIN" ]]; then
        /usr/bin/security find-identity -p codesigning "$LOGIN_KEYCHAIN" 2>/dev/null
    else
        /usr/bin/security find-identity -p codesigning 2>/dev/null
    fi | /usr/bin/awk -F '"' -v name="$SIGNING_IDENTITY_NAME" \
        '$2 == name { identity = $1; sub(/^.*\)[[:space:]]*/, "", identity); gsub(/[[:space:]]/, "", identity); print identity; exit }'
}

SIGNING_IDENTITY="$(find_signing_identity_hash)"
if [[ -z "$SIGNING_IDENTITY" ]]; then
    if ! command -v openssl >/dev/null 2>&1; then
        echo "找不到 OpenSSL，无法创建本机签名身份。请安装 Apple Command Line Tools 后重试。"
        read -r -p "按回车键退出…"
        exit 1
    fi

    echo "正在为当前用户创建一次性的本机签名身份…"
    SIGNING_TMP="$(mktemp -d "${TMPDIR:-/tmp}/keybloom-signing.XXXXXX")"
    chmod 700 "$SIGNING_TMP"
    trap 'rm -rf "$SIGNING_TMP"' EXIT
    cat > "$SIGNING_TMP/codesign.cnf" <<'CERTCONFIG'
[req]
prompt = no
distinguished_name = subject
x509_extensions = codesigning

[subject]
CN = KeyBloom Local Signing

[codesigning]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
CERTCONFIG

    openssl req -new -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 \
        -config "$SIGNING_TMP/codesign.cnf" \
        -keyout "$SIGNING_TMP/key.pem" -out "$SIGNING_TMP/certificate.pem" >/dev/null 2>&1
    SIGNING_P12_PASSWORD="$(openssl rand -hex 24)"
    if openssl pkcs12 -help 2>&1 | grep -- '-legacy' >/dev/null; then
        # OpenSSL 3 defaults to newer PKCS#12 algorithms that Apple's importer
        # may reject as a misleading "wrong password" error.
        openssl pkcs12 -export -legacy \
            -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
            -name "$SIGNING_IDENTITY_NAME" \
            -inkey "$SIGNING_TMP/key.pem" -in "$SIGNING_TMP/certificate.pem" \
            -out "$SIGNING_TMP/identity.p12" -passout "pass:$SIGNING_P12_PASSWORD"
    else
        openssl pkcs12 -export \
            -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
            -name "$SIGNING_IDENTITY_NAME" \
            -inkey "$SIGNING_TMP/key.pem" -in "$SIGNING_TMP/certificate.pem" \
            -out "$SIGNING_TMP/identity.p12" -passout "pass:$SIGNING_P12_PASSWORD"
    fi
    if [[ -n "$LOGIN_KEYCHAIN" ]]; then
        if ! /usr/bin/security import "$SIGNING_TMP/identity.p12" \
            -k "$LOGIN_KEYCHAIN" -P "$SIGNING_P12_PASSWORD" -T /usr/bin/codesign; then
            echo "macOS 未能把本机签名身份导入钥匙串。请确认钥匙串已解锁后重试。"
            read -r -p "按回车键退出…"
            exit 1
        fi
    else
        if ! /usr/bin/security import "$SIGNING_TMP/identity.p12" \
            -P "$SIGNING_P12_PASSWORD" -T /usr/bin/codesign; then
            echo "macOS 未能把本机签名身份导入钥匙串。请确认钥匙串已解锁后重试。"
            read -r -p "按回车键退出…"
            exit 1
        fi
    fi
    rm -rf "$SIGNING_TMP"
    trap - EXIT

    SIGNING_IDENTITY="$(find_signing_identity_hash)"
    if [[ -z "$SIGNING_IDENTITY" ]]; then
        echo "本机签名身份已创建，但 macOS 未能从当前用户的钥匙串读取它。请重试，或检查“钥匙串访问”。"
        read -r -p "按回车键退出…"
        exit 1
    fi
fi

echo "正在使用稳定的本机签名身份构建 KeyBloom…"
/usr/bin/codesign --force --sign "$SIGNING_IDENTITY" \
    --identifier com.local.keybloom --timestamp=none "$APP_PATH"
/usr/bin/codesign --verify --deep --strict "$APP_PATH"
SIGNING_REQUIREMENT="$(/usr/bin/codesign -d -r- "$APP_PATH" 2>&1)"
if [[ "$SIGNING_REQUIREMENT" == *cdhash* ]]; then
    echo "签名仍绑定到本次构建的文件哈希，无法保证输入监控授权在下次更新后保留。"
    read -r -p "按回车键退出…"
    exit 1
fi

PREVIOUS_SIGNING_IDENTITY="$(cat "$SIGNING_IDENTITY_MARKER" 2>/dev/null || true)"
if [[ "$PREVIOUS_SIGNING_IDENTITY" != "$SIGNING_IDENTITY" ]]; then
    echo "首次切换签名身份：仅重置 KeyBloom 自己的旧输入监控授权，之后需要重新授权一次。"
    if /usr/bin/tccutil reset ListenEvent com.local.keybloom; then
        printf '%s\n' "$SIGNING_IDENTITY" > "$SIGNING_IDENTITY_MARKER"
    else
        echo "自动重置未完成。请在 Terminal 执行：tccutil reset ListenEvent com.local.keybloom"
    fi
fi

echo "KeyBloom 已构建，正在打开。"
open "$APP_PATH"
echo "如果 macOS 阻止首次打开，请在“系统设置 > 隐私与安全性”中选择“仍要打开”。"
read -r -p "按回车键关闭此窗口…"
