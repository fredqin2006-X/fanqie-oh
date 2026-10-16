# 鸿蒙工具链与 G1 记录

核实日期：2026-10-16。当前选择路线 A：Flutter-OH + Rust/C；仅建立 G1 最小原生平台验证，尚未导入完整应用。

## 固定版本

| 工具 | 当前实际值 | 说明 |
| --- | --- | --- |
| DevEco Studio | 26.0.0.851 / 261.23567.138.36.2600851 | 本机 `F:\DevEco Studio` |
| HarmonyOS 编译 SDK | 26.0.0.105 / API 26 | DevEco 内置 `sdk/default`；不是 API 23 SDK |
| 最低兼容 / target | 6.1.0(23) / 6.1.0(23) | 工程显式设置，构建后另验 HAP manifest |
| Flutter-OH | `3.44.9+ohos-0.0.1-canary1` | 精确提交 `39285df71a97ffe0c23241dcc459d997a9d8b7c6`；预览版，未宣称稳定 |
| Flutter engine | `5a2a6a42cce67f965cf540fcecf616faca624aa1` | `flutter --version --machine` 实测 |
| OHOS engine | `7c82f54483327a13e09e7cc9c2f1e17c40e3987d` | `bin/internal/engine.ohos.version` |
| Dart | 3.12.2 | SDK 实际版本满足原项目 `^3.12.2`；未下调约束 |
| Node / ohpm | v24.14.1 / 26.0.0.630 | DevEco bundled |
| Hvigor | 6.26.8 | DevEco bundled package.json |
| Java | JBR 25.0.2+1-329.117 | DevEco bundled jbr |
| Rust / FRB | 尚未安装/编译验证；原核心要求 FRB 2.13.0 | 留到 G2，不用主机或 Android 库替代 OHOS 库 |
| 调试模拟器 | HarmonyOS 7.0 / API 26 / x86_64 手机 | HDC 读取 `OpenHarmony-7.0.0.105`、`26`、`x86_64`；不计为 6.1 ARM64 真机 |

Flutter SDK 位于仓库外 `E:\Codex-bulid\toolchains\flutter-oh-3.44.9-canary1`，固定 tag 检出；不提交 SDK 和引擎二进制。

维护方已从 OpenHarmony-TPC 迁移到 [CPF-Flutter/flutter_flutter](https://gitcode.com/CPF-Flutter/flutter_flutter)。本次通过 `git ls-remote` 核实新旧仓库相同 tag 的提交，不能用规划中的版本替代实际 SDK。现有满足 Dart 3.12.2 的 tag 仍为 canary，后续稳定版升级须单独比较和复验。参考该 tag 的 [README](https://gitcode.com/CPF-Flutter/flutter_flutter/blob/3.44.9%2Bohos-0.0.1-canary1/README.md)。

## 本机操作

从仓库根目录的 PowerShell 7 执行：

```powershell
. ./tools/environment.ps1
Set-Location app
flutter --version --machine
flutter doctor -v
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
```

未安装时可用 Git 克隆固定 tag（目标目录不得已存在）：

```powershell
git clone --depth 1 --branch 3.44.9+ohos-0.0.1-canary1 https://gitcode.com/CPF-Flutter/flutter_flutter.git E:\Codex-bulid\toolchains\flutter-oh-3.44.9-canary1
```

SDK 位置变化时通过 environment.ps1 参数指定，不改全局 PATH。Flutter doctor 对自定义分支、未配置 Android/Visual Studio 的提示不等于 OHOS 通过/失败；实际以 OHOS 构建和运行分别记录。

HAP 必须从仓库根目录通过 `./tools/build-hap.ps1 -Target ohos-x64`（模拟器）或默认 ARM64 构建。每次尝试结束先补充构建结论、检查差异并本地提交，之后才执行下一次。脚本只记录，提交需经过明确差异检查。

## 当前验证内容和边界

G1 页面通过 `fqapp/harmony_bootstrap` 调用 ArkTS 原生服务：

- 应用私有文件首次写入回读，后续启动检查同一标记文件；损坏时报错而非覆盖。
- Preferences 启动计数持久化；原生通道操作串行，避免重试导致并发写入。
- 独立的 G1 HUKS AES-256-GCM 探针：每次随机 12 字节 nonce、条目名作为 AAD、保存密文和摘要，读出后校验；已有密文但 HUKS key 丢失时拒绝重建覆盖。
- 不输出探针明文、密钥、私有路径或设备标识；异常仅返回允许列表中的代码。

这是平台验证，不是生产 `SecureKeyProvider` 实现，也不是业务数据迁移。生产密钥适配、丢失/损坏交互和加密 Hive 仍需专门测试。HUKS 会话/GCM 参数依据[OpenHarmony 官方开发说明](https://github.com/openharmony/docs/blob/master/en/application-dev/security/UniversalKeystoreKit/huks-encryption-decryption-arkts.md)及当前 SDK 类型定义；使用的接口均早于 API 23。

构建成功、模拟器通过、6.1 真机通过分别记录。API 23 SDK 基线编译、6.1 ARM64 真机、Rust/FRB、CENC 媒体、业务界面均尚未完成；G1 尚不能整体打勾。
