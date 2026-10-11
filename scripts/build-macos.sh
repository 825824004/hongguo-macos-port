#!/bin/bash
# 在上游源码目录中编译 macOS Release 版并统一做 ad-hoc 签名。
#
# 用法：
#   export GUOAPP_DIR=/path/to/guoapp
#   bash build-macos.sh
#
# 环境变量：
#   GUOAPP_DIR   上游 guoapp 源码目录（必填）
#   TOOLCHAIN    Flutter / Go 工具链目录（可选，默认读同目录 env.sh）

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "$GUOAPP_DIR" ]; then
  echo "错误：请先设置 GUOAPP_DIR 指向 guoapp 源码目录"
  echo "示例：export GUOAPP_DIR=\$HOME/guoapp"
  exit 1
fi
if [ ! -d "$GUOAPP_DIR" ]; then
  echo "错误：目录不存在：$GUOAPP_DIR"
  exit 1
fi
cd "$GUOAPP_DIR"

# 载入 Flutter / Go 环境（若同目录提供 env.sh）
if [ -f "$SCRIPT_DIR/env.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/env.sh"
fi
if ! command -v flutter >/dev/null 2>&1; then
  echo "错误：未找到 flutter，请先安装 Flutter 3.47+ 并加入 PATH"
  exit 1
fi
if ! command -v go >/dev/null 2>&1; then
  echo "错误：未找到 go，请先安装 Go 1.24+ 并加入 PATH"
  exit 1
fi

echo "=========================================="
echo " 步骤 1/4：编译 Go 原生核心 (darwin/arm64)"
echo "=========================================="
python3 scripts/build_native.py --platform darwin
cp -f native/build/darwin/libduanju_core.dylib macos/Runner/
cp -f native/build/darwin/libduanju_core.h macos/Runner/
ls -lh macos/Runner/libduanju_core.dylib

echo
echo "=========================================="
echo " 步骤 2/4：编译 macOS 应用"
echo "=========================================="
# 说明：ffmpeg_kit 的预编译 framework 由 zip 解出，带有 ._* AppleDouble 文件，
# 会导致 codesign 报 "unsealed contents" 而整个 app 签名失败。
# 已在 pbxproj 注入的 "Embed Duanju Core" 阶段中处理（删除 ._* 后逐个 ad-hoc 签）。
flutter build macos --release 2>&1 \
  | grep -viE "objc_ownership|AVKeyValueStatus|SWIFT_CLASS|@interface|NONNULL|^\s*[0-9]+ \||^\s*\||Swift Package Manager|media_kit|contact the plugin|Xcode 27 no longer|enable-macos-arm64-only|warnings? generated" \
  | tail -20

APP="build/macos/Build/Products/Release/duanjuapp.app"
if [ ! -d "$APP" ]; then
  echo "编译未产出 app，流程终止。"
  exit 1
fi

echo
echo "=========================================="
echo " 步骤 3/4：签 app 本体"
echo "=========================================="
codesign --force --sign - --timestamp=none \
  --entitlements macos/Runner/Release.entitlements \
  "$APP" 2>&1 | tail -3
codesign --deep --force --sign - --timestamp=none "$APP" 2>&1 | tail -3

echo
echo "=========================================="
echo " 步骤 4/4：签名验证"
echo "=========================================="
if codesign -v "$APP" 2>&1; then
  echo "app 签名校验通过 ✓"
else
  echo "app 签名校验未通过 ✗"
  exit 1
fi

echo
echo "产物：$(du -sh "$APP" | cut -f1)  $APP"
echo "运行：open $APP"
echo
echo "提示：首次打开若被 Gatekeeper 拦截，右键点 app → 打开。"
