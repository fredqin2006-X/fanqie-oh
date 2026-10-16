# 当前应用范围

此工程由固定 Flutter-OH 3.44.9 canary tag 的 Stage 模板创建，仅保留 ohos 平台。
`lib/main.dart` 与原安卓版本完全一致，页面与组件、业务资源直接复用；不重新设计 UI。
当前已接入 OHOS Rust/C、路径、Preferences、HUKS、网络、SQLite，以及 AVPlayer、Reader、Documents、TTS、AVSession 业务通道。实现、构建、模拟器和真机结果必须分别判断，见 [验收记录](../docs/acceptance/2026-10-16-porting.md)。
平台探针记录与产品入口分离；不把页面启动或首页内容成功等同于全部功能验收。

工具链、构建流程及未验项见 [../docs/toolchain.md](../docs/toolchain.md)。
保持 `pubspec.lock` 和 `ohos/oh-package-lock.json5` 跟踪；生成资源、引擎库、签名材料均忽略。

`test_driver/harmony_acceptance.dart` 是显式选择的 debug 验证入口，启动原应用，并向经过认证的 Dart VM service 注册非可视验证命令。正常 `lib/main.dart` 及 release 不导入该入口，不包含这些验证扩展。
