#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="IMEKeeper"
BUILD_DIR="${PROJECT_ROOT}/.build/release"
OUTPUT_DIR="${PROJECT_ROOT}/dist"
APP_BUNDLE="${OUTPUT_DIR}/${APP_NAME}.app"

echo "==> Building ${APP_NAME} in Release mode..."
swift build -c release --package-path "${PROJECT_ROOT}"

echo "==> Creating macOS App Bundle at ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/imekeeper" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

cat << 'EOF' > "${APP_BUNDLE}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>IMEKeeper</string>
    <key>CFBundleIdentifier</key>
    <string>com.antigravity.imekeeper</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>IME Keeper</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <!-- 关键属性：纯菜单栏 Agent，不显示在 Dock 栏中 -->
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026. All rights reserved.</string>
</dict>
</plist>
EOF

echo "==> App bundle built successfully at: ${APP_BUNDLE}"
echo "==> You can now run: open \"${APP_BUNDLE}\""
