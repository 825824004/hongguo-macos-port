# macOS 移植构建环境变量
#
# 用法：在项目根目录执行
#   source scripts/env.sh
#
# 依赖：
#   - Flutter 3.47+ 已安装（或放在 $TOOLCHAIN/flutter）
#   - Go 1.24+   已安装（或放在 $TOOLCHAIN/go）
#   - Homebrew Ruby 4.x + CocoaPods 1.16+
#
# 关于 PUBCACHE：若沙箱环境不允许写 ~/.pub-cache，可将其重定向到本地目录。

# 工具链目录：按需修改，或用环境变量覆盖
export TOOLCHAIN="${TOOLCHAIN:-$HOME/.guoapp-toolchain}"

if [ -d "$TOOLCHAIN/flutter/bin" ]; then
  export PATH="$TOOLCHAIN/flutter/bin:$PATH"
fi
if [ -d "$TOOLCHAIN/go/bin" ]; then
  export PATH="$TOOLCHAIN/go/bin:$PATH"
fi

# Pub 缓存：默认用用户目录；如遇写权限问题，取消下面两行注释改用本地路径
# export PUB_CACHE="$TOOLCHAIN/pub-cache"

# Go 模块代理：国内网络建议保留 goproxy.cn
export GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"
export GOSUMDB="${GOSUMDB:-off}"
export GOTOOLCHAIN=local

# Flutter 镜像：国内网络建议保留
export FLUTTER_SUPPRESS_ANALYTICS=true
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"

# CocoaPods 依赖 Homebrew 的 Ruby 4.x。
# macOS 自带 Ruby 2.6 无法安装新版 CocoaPods（gem 要求 Ruby >= 3.0）。
if [ -d /opt/homebrew/opt/ruby/bin ]; then
  export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
  export GEM_HOME="${GEM_HOME:-$TOOLCHAIN/gems-ruby3}"
  export GEM_PATH="$GEM_HOME"
  export PATH="$GEM_HOME/bin:$PATH"
fi
