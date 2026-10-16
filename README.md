# fqapp-for-harmony

fqapp 鸿蒙移植工作区。最低支持 **HarmonyOS 6.1.0（API 23）及以上版本**，初期以 ARM64 手机为目标。

已创建 `app/ohos` Stage 工程，固定 Flutter-OH 3.44.9 canary / Dart 3.12.2。原安卓入口、页面、组件和资源直接复用，不新增产品界面。已接入 OHOS Rust/C、HUKS、AVPlayer、阅读设备、文档、中文 TTS 与 AVSession 通道；模拟器走通真实首页/小说正文和合成 CENC 视频/音频，1833 个 Flutter 测试通过。完整 G1–G6 尚未验收：尤其缺少 HarmonyOS 6.1 ARM64 真机、真实 HEVC、锁屏/耳机和数据异常场景。逐项证据见[实施验收记录](docs/acceptance/2026-10-16-porting.md)。

- [鸿蒙移植执行手册](鸿蒙移植执行手册.md)：源码拆解、技术路线、阶段任务、构建与提交流程、验收门槛。
- [源码基线记录](docs/source-baseline.json)：上游提交、604 个文件比对结果及关键文件 SHA-256。
- [工具链与 G1](docs/toolchain.md)、[依赖矩阵](docs/plugin-matrix.md)、[构建记录](docs/builds/)。
- 上游项目：[ch6vip/fqapp](https://github.com/ch6vip/fqapp)。

`fqapp-source-code-android/` 是只读参考，`Agents.md` 仅保留本地；二者均忽略。实际参与构建的 Dart、Rust/C 和插件源码均在 `app/` 受控维护。构建不依赖参考目录；界面一致性比对脚本只读该目录。
