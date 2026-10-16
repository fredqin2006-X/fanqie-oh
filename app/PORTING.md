# 当前应用范围

此工程由固定 Flutter-OH 3.44.9 canary tag 的 Stage 模板创建，仅保留 ohos 平台。
`lib/main.dart` 是内部 G1 验证入口，当前验证原生目录、Preferences、HUKS。
不包含完整 fqapp 首页、阅读、搜索、Rust API 或播放器，不把模板启动算作功能移植完成。

工具链、构建流程及未验项见 [../docs/toolchain.md](../docs/toolchain.md)。
保持 `pubspec.lock` 和 `ohos/oh-package-lock.json5` 跟踪；生成资源、引擎库、签名材料均忽略。
