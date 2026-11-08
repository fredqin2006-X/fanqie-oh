# 番茄OH

番茄OH 是基于 [ch6vip/fqapp](https://github.com/ch6vip/fqapp) 移植的 HarmonyOS 客户端，提供小说阅读、漫画、短剧/漫剧播放与听书。

- 最低系统：**HarmonyOS 6.1.0（API 23）**，支持 6.1 及以上版本。
- 发布目标：ARM64 手机；Flutter-OH + ArkTS + Rust/C。
- 当前版本：**1.2.1（128）**。内部构建号从测试版继续递增。
- 源码与反馈：[fredqin2006-X/fanqie-oh](https://github.com/fredqin2006-X/fanqie-oh)。
- 下载：[v1.2.1 Release](https://github.com/fredqin2006-X/fanqie-oh/releases/tag/v1.2.1)。

## 功能

- 小说、漫画、听书与短剧入口，收藏、历史、本地书籍与备份。
- 原生视频播放、弹幕、倍速、全屏与强制横屏，返回后恢复方向。
- 根据系统开孔和安全区避让内容，处理旋转后旧边距造成的画面偏移。
- 设置 → 短剧 → 默认分辨率；未设置或所选档位不可用时选最高可用分辨率。
- 听书后台媒体会话与后台播放。
- 新版首页分类与 OLED 主题、九宫格阅读点击区、仿真翻页、文本替换及缓存续读。
- 听书句级高亮、字幕与离线音频，短剧自动缓存、画质记忆、解码器选择与系统画中画。
- 横屏长按临时 2 倍速、双击快退/快进与暂停、滑动调进度/亮度/音量，以及账号书架和历史导入。

## 下载与安装

Release 提供 ARM64 **未签名** HAP 和 SHA-256 校验清单。此包需使用 DevEco Studio 配置匹配设备的开发签名/profile 后安装；不是商店签名包。签名后文件摘要会变化，应重新计算校验值。

应用显示名和应用内品牌为“番茄OH”。技术包名、bundle ID 与备份格式标识保留，便于兼容已有数据；bundle ID 为 `com.fqapp.harmony.fqapp`。请勿为安装降级而清除已有数据。

## 从源码构建

固定工具版本和准备步骤见 [工具链说明](docs/toolchain.md)。使用 PowerShell 7，准备 Flutter-OH `3.44.9+ohos-0.0.1-canary1`、DevEco Studio/SDK、Rust 与 OHOS 目标。SDK、引擎和本机依赖缓存不随源码发布。

```powershell
git clone https://github.com/fredqin2006-X/fanqie-oh.git
Set-Location fanqie-oh
# 可用 FQ_FLUTTER_ROOT / FQ_DEVECO_ROOT 指定本机安装目录
. ./tools/environment.ps1 | Out-Null
Push-Location app
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
Pop-Location
# build-native.ps1 内的 RUSTUP_HOME/CARGO_HOME 使用本机工具目录，异机请按实际安装调整
./tools/build-native.ps1 -Target ohos-arm64
./tools/build-hap.ps1 -Target ohos-arm64 -Mode release
```

输出：`app/build/ohos/hap/entry-default-unsigned.hap`。每次 HAP 构建尝试后须审查源码与 `docs/builds/` 记录并做本地 Git 提交。构建不依赖安卓参考源码；`verify-upstream-ui.ps1` 是有本地上游参考时才执行的可选比对。

## 验证与维护

2026-11-08 的源码已同步安卓 `1.0.201+206`，修复 Issue #1 听书自动翻页/同步，并同步书架分组、书旗书源、新主题及 AI 阅读。用户确认本轮真机验收完成；设备型号、系统版本和逐项结果未提供。实现范围及验收边界见 [同步记录](docs/upstream/2026-11-08-android-followup.md) 和 [本轮验证](docs/acceptance/2026-11-08-upstream-port.md)。

- [v1.2.1 发布说明与验证范围](docs/releases/v1.2.1.md)、[v1.2.0 发布说明](docs/releases/v1.2.0.md)、[v1.0.0 历史发布](docs/releases/v1.0.0.md)
- [变更日志](CHANGELOG.md)、[交付历史](docs/delivery.md)
- [模拟器横屏与安全区验证](docs/acceptance/2026-10-17-emulator-rotation.md)
- [移植执行手册](鸿蒙移植执行手册.md)、[上游改动记录](docs/upstream-changes.md)
- [依赖矩阵](docs/plugin-matrix.md)、[源码基线](docs/source-baseline.json)、[历史构建记录](docs/builds/)

旧验收文档是相应日期的证据快照；最新状态以发布说明为准。模拟器结果、构建成功与用户真机反馈分别记录。没有推定用户设备的精确系统版本，也没有将其扩展为所有 API 23 设备和异常场景均已验证。

## 许可证与致谢

上游：[ch6vip/fqapp](https://github.com/ch6vip/fqapp)，移植基线提交 `5938f25dab2015f502ded1f2079ec2a51b8b4bc6`。本项目保留上游 **GPL-3.0** 许可证与作者署名；第三方依赖遵循各自许可证，详见 [第三方说明](NOTICE.md)。番茄OH 是独立移植项目。

源码仓库不含安卓只读参考目录、HAP、签名材料、设备凭据、用户数据、SDK、缓存及本地原始日志。HAP 仅作为 Release 附件发布。仅供个人学习研究使用。
