# 2026-11-08 安卓同步验证

源码范围、Issue #1 原因与鸿蒙适配见 [同步记录](../upstream/2026-11-08-android-followup.md)。以下区分主机测试、构建与设备验收。

## 已完成的主机验证

- 安卓参考 1474 文件与 `c29b279` 比对通过，独立检出工作区干净。
- Dart 静态分析：`No issues found`。
- Flutter 全量：Rust 主机库补齐后 3534 项通过、4 项明确跳过。跳过为 Android 平台政策和特定 SDK/平台用例；跳过不计通过。
- 鸿蒙 ArkTS 主机行为测试：39 项通过，包括 HUKS/AI 凭据、根丢失保护、起播位置、PiP owner 取消与旧请求隔离、TTS、媒体、亮度及账号采集。OS 服务使用替身。
- C 原生测试：74 项通过，包含 AES/CENC、时伸缩、重采样、畸形输入和真实 FFmpeg 音视频帧比较。
- Rust 主机测试：263 项通过；2 项真实上游网络 smoke test 明确忽略，3 项符号链接相关用例因当前 Windows 进程无创建符号链接权限而过滤。
- Flutter Rust Bridge：9 项真实 Dart → FRB → Rust 动态库集成通过，使用本地 mock 上游，无真实设备池或外网。
- UI 源码复核：314 份入口/页面/组件中 304 份一致，126 份资源中 124 份一致；其余为已记录的适配差异。
- ARM64 OHOS Rust release 原生核心已构建，源摘要为 `b55a4eea230883955c71c666e33b85c2e8ed57b2edf97f0f93f27a15e1c539ec`。
- ARM64 Release HAP 构建成功。包内检查版本 `1.2.0 (127)`、`debug=false`、HarmonyOS 6.1/API 23 min/target、SDK 26、ARM64 ELF 和唯 ARM64 Rust ABI；打包 Rust 核心与新构建剥离产物匹配。未签名、未安装、未推送、未发布。
- 本地交付包：`local-reports/delivery/FanqieOH-20261108-android-sync-arm64-unsigned.hap`，110651272 bytes，SHA-256 `b1bbf18df0e34deb5ee08e53968466ca9730ea0481fb745fe86c2e0e8bde9c67`。
- 构建输入和结果见 [`docs/builds/20261108T070333131Z-9cf1fe-release-ohos-arm64.md`](../builds/20261108T070333131Z-9cf1fe-release-ohos-arm64.md)；APK/HAP 二进制、原始测试日志和设备材料均不纳入 Git。

首次全量回归出现 18 个失败。修复本地书分组清理、后台 PiP 交接后，更新了新版横屏/设置导航断言。最终全量结果包含 9 项真实 FRB 集成，为上述 3534 通过、4 跳过。

## 设备验收

本轮没有执行签名、安装、推送、标签或 Release。仍待真机检查：从阅读页启动/恢复听书、持续播放跨页/跨章、手动翻页后原进度恢复、真人录音关联原著与字幕同步、历史位置恢复、后台/耳机/蓝牙、PiP 成功与拒绝、HUKS 升级数据保留，以及 HarmonyOS 6.1/API 23 实际运行。
