# fqapp-for-harmony

fqapp 鸿蒙移植工作区。最低支持 **HarmonyOS 6.1.0（API 23）及以上版本**，初期以 ARM64 手机为目标。

当前已初始化独立 Git 仓库，完成安卓源码静态分析和移植规划，尚未创建鸿蒙应用工程、构建 HAP 或完成真机验收。

- [鸿蒙移植执行手册](鸿蒙移植执行手册.md)：源码拆解、技术路线、阶段任务、构建与提交流程、验收门槛。
- [源码基线记录](docs/source-baseline.json)：上游提交、604 个文件比对结果及关键文件 SHA-256。
- 上游项目：[ch6vip/fqapp](https://github.com/ch6vip/fqapp)。

`fqapp-source-code-android/` 是本地安卓参考源码，`Agents.md` 是本地协作规则；两者均被忽略，不纳入 Git。将来移植实现需把实际使用并适配后的 Dart、Rust、C 代码放入受版本控制的应用目录，不能依靠被忽略的参考目录参与构建。
