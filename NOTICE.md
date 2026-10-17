# 来源与第三方说明

番茄OH 基于 ch6vip/fqapp，基线提交 5938f25dab2015f502ded1f2079ec2a51b8b4bc6；上游地址 https://github.com/ch6vip/fqapp 。保留上游 GNU GPL v3 许可证，根目录 LICENSE 与 app/LICENSE 一致。HarmonyOS 移植改动和本项目源码在该许可证条件下提供。

- Flutter-OH、Flutter 引擎与 Dart SDK：构建时按固定版本获取，遵循其随附许可。
- app/packages/ 下的本地适配插件与 UI 依赖：保留各目录 LICENSE 和原作者声明。
- IJKPlayer：构建依赖 @ohos/ijkplayer 2.0.11；声明见 app/assets/licenses/ijkplayer/ 的 LICENSE、NOTICE、README.OpenSource，以及应用内播放器开源许可入口。源码/配置上游地址保留在这些文件中。
- Tiny AES：保留 app/native/third_party/tiny_aes/unlicense.txt。
- 其他 Dart/Rust/OHPM 依赖：版本在 pubspec.lock、Cargo.lock、oh-package-lock.json5 中固定，遵循各依赖许可。

本说明不替换任何第三方许可证，所有随附作者声明和许可继续适用。安卓参考目录未纳入本仓库；实际构建所需的一方 Dart、Rust/C 与鸿蒙适配源码均包含在 app/ 中。
