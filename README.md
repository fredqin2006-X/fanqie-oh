# fqapp-for-harmony

fqapp 鸿蒙移植工作区。最低支持 **HarmonyOS 6.1.0（API 23）及以上版本**，初期以 ARM64 手机为目标。

已开始按手册执行 G1，创建 `app/ohos` Stage 工程，固定 Flutter-OH 3.44.9 canary / Dart 3.12.2，接入目录、Preferences 与 HUKS 原生平台验证。完整应用功能和 HarmonyOS 6.1 ARM64 真机验收尚未完成；实际构建、模拟器结果分别见记录。

- [鸿蒙移植执行手册](鸿蒙移植执行手册.md)：源码拆解、技术路线、阶段任务、构建与提交流程、验收门槛。
- [源码基线记录](docs/source-baseline.json)：上游提交、604 个文件比对结果及关键文件 SHA-256。
- [工具链与 G1](docs/toolchain.md)、[依赖矩阵](docs/plugin-matrix.md)、[构建记录](docs/builds/)。
- 上游项目：[ch6vip/fqapp](https://github.com/ch6vip/fqapp)。

`fqapp-source-code-android/` 是本地安卓参考源码，`Agents.md` 是本地协作规则；两者均被忽略，不纳入 Git。将来移植实现需把实际使用并适配后的 Dart、Rust、C 代码放入受版本控制的应用目录，不能依靠被忽略的参考目录参与构建。
