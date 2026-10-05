# macOS 移植成果说明

本仓库**不包含**上游 `zhoufuweigg/guoapp` 的应用源码（`lib/`、`native/`、`android/`、`ios/`、`windows/`）。

## 为什么没有源码

上游仓库 `zhoufuweigg/guoapp` **没有任何 LICENSE 文件**，`pubspec.yaml` 也未声明 `license` 字段，README 仅注明「源码来自网上大名鼎鼎的鱼佬（原作者）」。按著作权法默认规则，未声明许可意味着著作权人保留所有权利，他人无权复制与再分发。

因此本仓库仅发布**我自己编写的移植工程成果**：

- macOS 平台工程配置
- 对上游的改动补丁（patch 形式，不含完整源码）
- 构建与签名脚本
- 移植过程文档

若你需要运行完整应用，请自行克隆上游仓库并按本文档操作。**在原作者补充明确许可协议之前，请勿重新分发其源码。**

## 移植目标

将 Flutter 版红果短剧客户端从上游仅支持的 Android / Windows / iOS 扩展到 macOS（Apple Silicon）。

## 已验证环境

| 项目 | 版本 |
| --- | --- |
| macOS | 27.0 |
| 硬件 | Apple M6 / 24 GB |
| Xcode | 27.0（macOS SDK 27.0） |
| Flutter | 3.47.6 stable（Dart 3.13.5） |
| Go | 1.24.6 darwin/arm64 |
| Homebrew | 7.0.8 |
| Ruby | 4.0.7（仅用于 CocoaPods） |
| CocoaPods | 1.16.2 |

## 上游基线

- 仓库：`https://github.com/zhoufuweigg/guoapp`
- commit：`0e60928514c31a96ade9b31866948f15da5ca2a6`
- 版本：`0.2.64+71`
- 注意：作者声明「随时可能删库」，建议尽早自行备份

## 移植内容

### 1. macOS 平台工程

完整工程位于 `macos-platform/`，由以下命令生成后手工配置：

```bash
flutter create --platforms=macos --org com.phoenix --project-name duanjuapp .
```

在此基础上做了四处配置：

| 文件 | 改动 |
| --- | --- |
| `Runner/DebugProfile.entitlements`、`Runner/Release.entitlements` | 开启网络客户端/服务端、用户选文件与下载目录读写、JIT、关闭库校验 |
| `Runner/Info.plist` | 放开 ATS、声明 `NSBonjourServices` 为 `_zgj-link._tcp`（局域网追剧同步）、补充本地网络与目录用途说明 |
| `Runner/MainFlutterWindow.swift` | 默认窗口 1180×760、最小 900×600 并居中 |
| `Runner.xcodeproj/project.pbxproj` | 注入 `Embed Duanju Core` 构建阶段（置于所有 Pods 嵌入阶段之后） |

### 2. Dart 层补丁

见 `patches/macos-port-dart.patch`，共 4 个文件、54 行新增。上游桌面端逻辑本已较通用，平台耦合点集中在四处：

- **`lib/core_bridge.dart`** — 新增 `_openMacCore()`，按 `@rpath` 与多个候选路径加载 `libduanju_core.dylib`，失败时回退 `DynamicLibrary.process()`；原代码对非 Android/Windows/iOS 平台直接抛 `UnsupportedError`
- **`lib/main.dart`** — `windowManager` 初始化扩展到 macOS 并设置窗口尺寸；局域网设备类型判定把 macOS 归为 `computer` 而非 `phone`
- **`lib/player_screen.dart`** — 全屏逻辑扩展到 macOS（原本仅 Windows）；关闭硬件加速，对齐上游 iOS 端规避 libmpv 渲染崩溃的处理
- **`lib/lan_controller.dart`** — 设备名增加 `Mac` 分支

### 3. Go 原生核心

上游 `scripts/build_native.py` **已内置 `darwin` 分支**，无需修改：

```bash
python3 scripts/build_native.py --platform darwin
# → native/build/darwin/libduanju_core.dylib  (13 MB, Mach-O arm64)
```

导出符号 `DuanjuRequest` / `DuanjuFree`，运行时依赖仅 CoreFoundation、Security、libresolv、libSystem。

## 移植中遇到的关键问题

### CocoaPods 无法安装

macOS 自带 Ruby 2.6.10（2022 年），而新版 gem 要求 Ruby ≥ 3.0。在系统 Ruby 上逐个降级会陷入无限循环：

```
ffi 1.17.4 → securerandom → drb → minitest → …
```

RubyGems 的报错形式是「最后支持当前 Ruby 的版本是 X，试试装 X」，但装上 X 后立刻触发下一个不兼容。**根治办法是用 Homebrew 安装新版 Ruby。**

### `code object is not signed at all`

Xcode 报此错误时，**报错的 framework 名字每次都不同**（`libavformat` → `libswresample` → `libavfilter`），看起来像随机故障。真实链条：

1. ffmpeg_kit 的预编译 framework 由 zip 压缩包解出，带有 96 个 `._*` AppleDouble 元数据文件
2. 这些文件散落在 framework 根目录，codesign 无法封装，报 `unsealed contents present in the root directory of an embedded framework`
3. framework 结构封装失败 → 整个 app 签名失败

**排查陷阱**：`codesign -dv` 此时仍显示「已签名」，因为 Mach-O 二进制本身是 linker-signed。要判断是否真正签名成功，应检查是否存在 `_CodeSignature` 目录。

修复方式是在构建阶段执行：

```bash
find "$APP" -name '._*' -delete
find "$APP" -name '.DS_Store' -delete
# 然后逐个 ad-hoc 签所有 framework
```

### 修改 pbxproj 的教训

用 Python 正则批量替换 `project.pbxproj` 会破坏文件结构（`plutil -lint` 报 `Unexpected character /`）。由于 `macos/` 目录未被 git 跟踪，`git checkout` 无法恢复，只能用 `flutter create --platforms=macos` 重新生成。

**修改 Xcode 工程应使用 `xcodeproj` gem**，它会正确维护文件结构：

```ruby
require 'xcodeproj'
project = Xcodeproj::Project.open('macos/Runner.xcodeproj')
target = project.targets.find { |t| t.name == 'Runner' }
phase = target.new_shell_script_build_phase('Embed Duanju Core')
phase.shell_script = '...'
target.build_phases << phase
project.save
```

## 使用方法

### 环境要求

| 依赖 | 版本 | 说明 |
| --- | --- | --- |
| macOS | — | Apple Silicon 实测通过（M6 / 24 GB） |
| Xcode | 27.0 | 需先 `sudo xcodebuild -license accept` |
| Flutter | 3.47+ | 需 3.47.4 或更高 |
| Go | 1.24+ | 编译原生核心 |
| Homebrew Ruby | 4.x | **必须**。macOS 自带 Ruby 2.6 无法安装 CocoaPods |
| CocoaPods | 1.16+ | 由 Homebrew Ruby 安装 |

### 步骤

```bash
# 1. 克隆上游源码
git clone https://github.com/zhoufuweigg/guoapp.git
cd guoapp

# 2. 应用 Dart 层补丁
git apply /path/to/hongguo-macos-port/patches/macos-port-dart.patch

# 3. 生成 macOS 平台工程
flutter create --platforms=macos --org com.phoenix --project-name duanjuapp .

# 4. 用本仓库的工程配置覆盖（entitlements / Info.plist / pbxproj 已配好）
rsync -a /path/to/hongguo-macos-port/macos-platform/ macos/

# 5. 配置环境变量
export GUOAPP_DIR=$PWD
source /path/to/hongguo-macos-port/scripts/env.sh

# 6. 编译 + 签名（一步完成）
bash /path/to/hongguo-macos-port/scripts/build-macos.sh

# 7. 运行
open build/macos/Build/Products/Release/duanjuapp.app
```

`scripts/build-macos.sh` 会依次完成：编译 Go 原生核心 → 拷贝到 `macos/Runner/` →
`flutter build macos --release` → ad-hoc 签名 → 验证签名。

### 关于第 4 步

`macos-platform/` 中的 `Runner.xcodeproj` 含有我注入的 `Embed Duanju Core` 构建阶段，
这是解决 ffmpeg framework 签名问题的关键，不能省略。直接复制整个目录最省事。

若只想手动挑选文件，核心是这三个：

- `Runner/Release.entitlements` 与 `Runner/DebugProfile.entitlements` — 沙箱权限
- `Runner/Info.plist` — ATS 与 NSBonjour 声明
- `Runner.xcodeproj/project.pbxproj` — `Embed Duanju Core` 构建阶段

### 目录说明

```
hongguo-macos-port/
├── README.md                       本文件
├── LICENSE                         MIT（仅覆盖本仓库成果）+ 上游许可状态说明
├── NOTICE                          第三方组件与来源声明
├── macos-platform/                 macOS 平台工程（Flutter 模板 + 我的配置）
├── patches/
│   └── macos-port-dart.patch       4 个 Dart 文件的改动，共 54 行新增
└── scripts/
    ├── env.sh                      构建环境变量
    └── build-macos.sh              编译 + 签名自动化脚本
```


## macOS 功能差异

上游原本没有 macOS 实现，以下功能在 macOS 上不可用（属预期行为，非移植遗漏）：

- 后台下载（切走或关闭窗口会中断）
- 画质增强链路（上游仅 Windows）
- 画中画（上游仅 Android 手机与平板）
- 移动存储目录选择
- 系统代理自动监控（需在「设置与备份 → 网络与资源」手动配置）

## 地域限制实测

红果按用户出口 IP 做地域管控，公开资料称海外 IP 会出现片库变灰、播放被拦、评论区消失。

**但本移植实测中，日本 IP（128.22.174.209）直连可正常播放**，HTTPS 连接直接建立，无区域限制现象。推测原因是本客户端通过自带的 Go 核心（使用 `bogdanfinn/tls-client` 做 TLS 指纹伪装）直接调用接口，绕过了官方 App 的地区校验逻辑。

此结论基于单次实测，不同网络环境可能表现不同。app 内置的手动代理功能（支持 HTTP/HTTPS/SOCKS5）可作为备用手段。

## 声明

- 本仓库内容为个人移植成果，仅供学习与技术交流
- 上游应用及其站源内容的版权与合规性归各自权利人所有
- 请遵守所在地法律法规，不要将本成果用于商业用途
- 使用第三方站源内容时应遵守相应版权规定
