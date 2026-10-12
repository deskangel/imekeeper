#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="IMEKeeper"
BUILD_DIR="${PROJECT_ROOT}/.build/release"
OUTPUT_DIR="${PROJECT_ROOT}/dist"
APP_BUNDLE="${OUTPUT_DIR}/${APP_NAME}.app"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
INSTALL_APP_PATH="${INSTALL_DIR}/${APP_NAME}.app"

echo "=================================================="
echo "  IME Keeper - 自动化编译、签名与更新部署脚本"
echo "=================================================="

# 1. 编译 Release 二进制文件
echo "==> [1/5] Building ${APP_NAME} in Release mode..."
swift build -c release --package-path "${PROJECT_ROOT}"

# 2. 构造 macOS App Bundle
echo "==> [2/5] Creating macOS App Bundle at ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/imekeeper" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

cp "${PROJECT_ROOT}/Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

if [ -f "${PROJECT_ROOT}/Resources/AppIcon.icns" ]; then
    echo "==> Packaging AppIcon.icns into Resources..."
    cp "${PROJECT_ROOT}/Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

# 3. 搜索证书并自动代码签名
echo "==> [3/5] Searching for code signing identities in Keychain..."
SIGNING_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -E "Developer ID Application|Apple Development" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)

if [ -n "${SIGNING_IDENTITY}" ]; then
    echo "==> Found valid code signing identity: \"${SIGNING_IDENTITY}\""
    echo "==> Signing app bundle..."
    codesign --force --deep --options runtime --sign "${SIGNING_IDENTITY}" "${APP_BUNDLE}"
else
    # 尝试查找任何有效证书，若均无则使用 Ad-hoc 自签名
    FIRST_ANY_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep ')' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
    if [ -n "${FIRST_ANY_IDENTITY}" ]; then
        echo "==> Using available identity: \"${FIRST_ANY_IDENTITY}\""
        codesign --force --deep --sign "${FIRST_ANY_IDENTITY}" "${APP_BUNDLE}"
    else
        echo "==> No Keychain identity found. Falling back to Ad-hoc signing (-)..."
        codesign --force --deep --sign "-" "${APP_BUNDLE}"
    fi
fi

# 验证签名
echo "==> Verifying code signature..."
codesign --verify --deep --strict "${APP_BUNDLE}"
echo "==> Signature verified successfully."

# 4. 检查当前运行状态并关闭
WAS_RUNNING=false
echo "==> [4/5] Checking if ${APP_NAME} is currently running..."
if pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
    echo "==> Detected running instance of ${APP_NAME}. Terminating for update..."
    WAS_RUNNING=true
    pkill -x "${APP_NAME}" || true
    
    # 轮询等待进程安全退出
    for _ in {1..10}; do
        if ! pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
            break
        fi
        sleep 0.5
    done
    
    # 若仍未退出则强制 kill
    if pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
        echo "==> Force terminating stubborn process..."
        pkill -9 -x "${APP_NAME}" || true
        sleep 0.5
    fi
    echo "==> Previous instance closed."
else
    echo "==> ${APP_NAME} is not currently running."
fi

# 5. 更新安装至目标安装目录
echo "==> [5/5] Installing ${APP_NAME}.app to ${INSTALL_APP_PATH}..."
mkdir -p "${INSTALL_DIR}"
rm -rf "${INSTALL_APP_PATH}"
cp -R "${APP_BUNDLE}" "${INSTALL_APP_PATH}"
echo "==> Successfully installed to: ${INSTALL_APP_PATH}"

# 如果更新前正在运行，则自动重新拉起最新版本
if [ "${WAS_RUNNING}" = true ]; then
    echo "==> Restarting updated ${APP_NAME}..."
    open "${INSTALL_APP_PATH}"
    echo "==> Application restarted successfully."
else
    echo "==> Done. You can launch it with: open \"${INSTALL_APP_PATH}\""
fi
