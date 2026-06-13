#!/bin/bash
# 把 Swift Package 编译产物打包成 Fluent.app，并做自签名。
# 用法：./build-app.sh
# 说明：产品名（.app / 显示名）为 Fluent；内部可执行文件名仍是 SPM 目标名 PomoTranslate（不影响显示）。
set -e

PRODUCT_NAME="Fluent"          # 用户可见的产品名（.app 名）
BIN_NAME="PomoTranslate"       # SPM 编译出的可执行文件名（CFBundleExecutable 与之一致）
APP_DIR="$PRODUCT_NAME.app"

echo "==> 1. 编译 release（分别编 arm64 + x86_64，再合并为通用二进制）..."
echo "    - 编译 arm64..."
swift build -c release --arch arm64
ARM64_BIN="$(swift build -c release --arch arm64 --show-bin-path)/$BIN_NAME"

echo "    - 编译 x86_64..."
swift build -c release --arch x86_64
X86_BIN="$(swift build -c release --arch x86_64 --show-bin-path)/$BIN_NAME"

echo "==> 2. 组装 .app 结构..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

echo "    - lipo 合并通用二进制..."
lipo -create "$ARM64_BIN" "$X86_BIN" -output "$APP_DIR/Contents/MacOS/$BIN_NAME"
echo "    - 架构：$(lipo -archs "$APP_DIR/Contents/MacOS/$BIN_NAME")"
cp "Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

echo "==> 3. 用稳定自签名证书签名（让系统权限跨重新编译不丢失）..."
SIGN_ID="PomoTranslate Self-Signed"
if security find-identity -v -p codesigning | grep -q "$SIGN_ID"; then
    codesign --force --deep --options runtime --sign "$SIGN_ID" "$APP_DIR"
    echo "    已用证书签名：$SIGN_ID"
else
    echo "    ⚠️ 未找到自签名证书，回退到 ad-hoc（权限会随重编失效）"
    codesign --force --deep --sign - "$APP_DIR"
fi

echo ""
echo "✅ 完成：$APP_DIR"
echo ""
echo "下一步："
echo "  1. 打开 app：    open $APP_DIR"
echo "  2. 首次运行会提示授权，去 系统设置 > 隐私与安全性 勾选 Fluent（辅助功能）"
echo "  3. 授权后 app 会自动重启使其生效（无需手动退出再打开）"
echo "  4. 点菜单栏 🍅 图标 > 设置，填入你的 AI API key"
