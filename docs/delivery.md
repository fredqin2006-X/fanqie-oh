# 鸿蒙内部验证交付

更新：2026-10-17（Asia/Shanghai）。当前为移植中的内部验证实现，**不是完整验收或正式发布版本**。产品 UI 沿用安卓；实际能力、已知限制及未验项见 [实施验收记录](acceptance/2026-10-16-porting.md)。

## 最新全屏与开孔适配包

- 文件：`local-reports/delivery/fqapp-1.0.120-20261017-fullscreen-cutout-arm64-release-unsigned.hap`
- ARM64 Release，正常 `lib/main.dart`，版本 `1.0.120+125`，debug=false，最低 HarmonyOS 6.1 / API 23。
- 构建记录：`20261017T015958470Z-2e6eb6`；104,925,997 字节。
- SHA-256：`a7f85d59c96984e55ba54c4c3904b9ec5038b5268d37df09a6eae5b10c195d0d`。
- 全屏只留视频与已启用弹幕，按视频宽高固定方向，返回先退全屏；推荐流和弹层全屏入口直接进入此模式。全应用根据系统开孔避让区预留空白并匹配背景色。
- 相关用例 87 项通过，分析无问题；[实现及验证范围](acceptance/2026-10-17-display.md)。本轮新增模拟器安装被自动审批拦截，新原生运行效果仍待用户人工真机复测。
- 未签名，沿用 DevEco 研发签名/profile 后安装；没有推送或发布。

## 上一版播放修复包

源码 `49fc140`，正常 `lib/main.dart` 入口，ARM64 Release，版本 `1.0.120+125`，debug=false，最低 HarmonyOS 6.1 / API 23。构建记录 `20261017T013108550Z-fc2ada`。

- 文件：`local-reports/delivery/fqapp-1.0.120-20261017-playback-fix-arm64-release-unsigned.hap`
- 大小：104,889,617 字节。
- SHA-256：`c197b3640df0804007ae44d5b8faed879eb5544483d2fa925d352af33a522d4a`。
- 未签名；需在 DevEco 配置匹配手机的研发签名/profile 后安装，交由用户人工真机复测。没有推送或发布。
- 已核实 ARM64 应用、引擎与两份自编译核心库的 ELF 架构；原生配置还打入额外 x86_64 依赖，但没有 x86_64 Flutter 应用/引擎，本包仅供 ARM64 使用。
- 本轮模拟器播放结果见 [黑屏修复记录](acceptance/2026-10-17-playback.md)。以下原交付文件保留为历史版本，不包含本次播放修复。

## 历史本地文件

- 正常产品入口：`app/lib/main.dart`，原始 Flutter 页面和组件直接复用。
- DevEco 工程：`app/ohos/`，Stage / HarmonyOS，min/target `6.1.0(23)`，compile API 26。
- ARM64 release 未签名 HAP：`local-reports/delivery/fqapp-1.0.120-ohos-arm64-release-unsigned.hap`。
- x86_64 debug 验证 HAP：`local-reports/delivery/fqapp-1.0.120-ohos-x64-acceptance-unsigned.hap`，包含非可视验证扩展，仅供本地模拟器。
- 本地 SHA-256 清单：`local-reports/delivery/SHA256SUMS.txt`；受控元数据记录见本文件后续校验段及 `docs/builds/`。

HAP、SDK、动态库、签名材料和设备数据均忽略，不提交到 Git。没有上传、推送或发布。ARM64 包使用正常 `main.dart`，不导入 debug 验证入口；当前没有 ARM64 真机运行或签名证据。x86_64 模拟器允许安装未签名 HAP，不能据此承诺普通手机可直接安装。

## 历史包校验结果

ARM64 构建记录：`20261016T201654062Z-a2855b`（UTC 时间；北京时间 2026-10-17），包含 TTS 播报完成修复。包大小 **37,978,878 字节**，SHA-256：

```text
67dc918a4f7cc836480f8fa64cb3690b7c72c41aa02f6fa8aa368db5056da2d3
```

包内只有 `arm64-v8a` 的 `libapp.so`、`libflutter.so`、`libfqapi_core.so`。`module.json`：版本 `1.0.120+125`，debug=false，min/target `60100023`（HarmonyOS 6.1/API 23），compile `26.0.0.105`。核心来自同一份 Rust/C 源码摘要 `3382496edd43919dc6ab130ba65675639ca5005f74e8f88104908513830a962a`；SDK `llvm-strip --strip-all` 后与包内核心字节一致，包内核心 SHA-256 为 `1b2e292e1785453a964741a0a6aaa29cefde6875944533c3697e5fff6aa889fb`。

x86_64 debug 验证包已更新到 `20261016T201315702Z-8f1432`，189,977,262 字节，SHA-256 `7bd59de5edc92c0b66f54c9545813033a66f0a11ce847032c33f270879aed464`，同样包含 TTS 播报完成回调修复。原页面的 TXT/备份与两章朗读续验见[2026-10-17 记录](acceptance/2026-10-17-followup.md)。

## 从源码构建

使用 `docs/toolchain.md` 中固定的 Flutter/Dart、DevEco/SDK 与 Rust 版本。PowerShell 7 从仓库根目录执行：

```powershell
. ./tools/environment.ps1
./tools/verify-upstream-ui.ps1
Push-Location app
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
Pop-Location
./tools/build-native.ps1 -Target ohos-arm64
./tools/build-hap.ps1 -Target ohos-arm64 -Mode release
```

`build-native.ps1` 生成目标 `.so` 和忽略目录中的源码摘要/库摘要记录。HAP 构建前保留目标 ABI 核心库，另一个 ABI 的自编译核心库临时存放于忽略目录，构建结束必须恢复；不要将其他 ABI 的库装入最终包。

`build-hap.ps1` 为每次成功/失败尝试记录输入 SHA-256 清单、结果、工具版本与 HAP 摘要。OHPM 在切换 ABI/debug/release 时会把锁文件指向同一固定引擎的对应 HAR，这是需要审查并提交的构建变化。脚本不自动暂存或提交。**每次尝试后先审查相关源码、锁文件、docs/builds 与 staged diff，显式暂存并本地提交，才能再次尝试 HAP。**

## 安装与真机续验

模拟器使用 HDC 指定设备，不影响其他连接：

```powershell
. ./tools/environment.ps1
hdc list targets
hdc -t <模拟器目标> install -r <x86_64验证HAP绝对路径>
hdc -t <模拟器目标> shell aa start -a EntryAbility -b com.fqapp.harmony.fqapp
```

手机阶段先在 DevEco 打开 `app/ohos`，连接已开启 USB 调试的 HarmonyOS 6.1 ARM64 手机，使用该项目/设备匹配的研发签名与 profile。签名配置、证书、密钥和密码仅在本地保管，不提交。签名后记录新 HAP 摘要和签名验证结果，覆盖安装并核实数据保留，再按手册 G1–G6 真机矩阵执行。当前无法跳过的条件是 API 23 真机与匹配的签名/profile。

重点续验：真实 HEVC 视频与加密音频听感，所有媒体/阅读前后台切换，锁屏/控制中心/耳机/蓝牙，离线重开与备份恢复，EPUB/字体/分享，损坏密钥/网络中断/磁盘满和长时间资源统计。测试夹具、回调和主机 Widget 测试不能替代这些结果。
