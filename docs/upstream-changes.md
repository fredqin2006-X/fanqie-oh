# 上游导入与鸿蒙差异

基线：`ch6vip/fqapp` 提交 `5938f25dab2015f502ded1f2079ec2a51b8b4bc6`，版本 `1.0.120+125`。

2026-10-28 将本地安卓参考同步至 `43b20ba40d91d98322f29344847788ac54a15971`
（`1.0.133+138`）。874 个文件逐一通过 SHA-256 校验，清除上游已删除的
18 个旧文件，没有创建旧源码备份。同步记录见
[`upstream/android-reference.json`](upstream/android-reference.json)，鸿蒙移植记录见
[`upstream/2026-10-28-android-followup.md`](upstream/2026-10-28-android-followup.md)。
本节首行为最初移植基线。本轮按用户要求进一步合入新版共享 Dart/Rust 功能、组件及测试，并用鸿蒙平台接口接续原生功能；详细范围及验证边界见上述记录。

2026-10-16 开始受控导入 `lib/`、`test/`、`assets/`、`rust/`、`native/crypto_core/`、`native/third_party/tiny_aes/`、FRB 配置与锁文件，保留 `app/LICENSE`。没有导入 Android Gradle、Kotlin 或 JNI 工程，也不依赖参考目录构建。

## 界面约束

用户明确要求与安卓应用完全一致。原 `main.dart`、`pages/`、`widgets/` 和产品资源直接复用，不重新设计页面。先前 G1 临时页面已移除，平台验证不成为产品入口。后续仅允许因鸿蒙系统能力而调整平台接缝；不把静态文件一致当作屏幕和交互已经验收。

## 当前受控适配

- Stage 工程最低/target 固定 6.1/API 23；编译 API 26。每次 HAP 尝试均记录并提交。
- `SecureKeyProvider` 在 OHOS 选择 HUKS 原生通道；已有坏密钥拒绝替换。OHOS 的 `EncryptedHive` 在密钥不可用/解密失败时保留原文件并报错，不进入明文降级或删除重建。
- path_provider、Preferences、URL、SQLite 用独立 OHOS 实现注册，保留原 Dart 根包版本。
- connectivity_plus 保留 pub.dev **7.3.1** Dart 源码和 API，仅加入一方 **7.0.0** 鸿蒙原生实现；没有用低版本根包绕过 `^7.3.1`。原生通道/事件仍须实际回归。
- 未采用 `flutter_secure_storage_ohos` 候选：其 RSA 包装私钥保存在普通 Preferences，不能作为本项目受保护的根密钥。候选源码保留于忽略目录供审查，不纳入产品；本项目用不可导出的 HUKS key + AES-GCM、随机 nonce、按条目绑定 AAD。
- `material_ui 1.1.1` / `cupertino_ui 1.0.2` 对新增 `TargetPlatform.ohos` 的穷尽 switch 未覆盖，阻止原应用编译。以相同发布版本 vendored，仅把 OHOS 并入已有 Android 分支；不改样式常量、布局或绘制。`app_theme.dart` 同样为 OHOS 选择原安卓的无过渡 builder。
- 原 Android manifest/备份 XML 测试不适用于独立 OHOS 工程，明确跳过，不计为鸿蒙安全验收。其余原 Dart 回归保留；坏密钥测试更新为保留既有记录、不自动换钥。
- 生产密钥和 G1 探针使用不同 alias 与 Preferences。日志不输出密钥、capability 或设备池。

## vendored 插件来源

仅跟踪插件 `lib/`、`ohos/`、pubspec 与许可证；示例及其他平台实现留在忽略的本地审查目录。

| app/packages | 上游来源与精确提交 |
| --- | --- |
| path_provider_ohos | CPF-Flutter/flutter_packages `7cc9f4cfbd464943096dc7c87288252c543df5cb` |
| shared_preferences_ohos | CPF-Flutter/flutter_packages `19bd50ff6d5eaa96f18c63796c51e1b4e78a7480` |
| url_launcher_ohos | CPF-Flutter/flutter_packages `f31db0d72e7a1d91dd023325a23dc2fba4b6ce4b` |
| sqflite_ohos | CPF-Flutter/flutter_sqflite `5ef0761001378455e872e46d1c0620d39dcc1002` |
| connectivity_plus | pub.dev `7.3.1` 发布归档的 Dart + CPF-Flutter/flutter_plus_plugins `9514235dda402b432b860a31c69d4dc5153891f5` 的 ohos/ |

插件固定在本仓库中维护，不再跟随其子依赖的活动 Git 分支。锁文件记录实际 path 来源；后续修改必须在这里说明。
