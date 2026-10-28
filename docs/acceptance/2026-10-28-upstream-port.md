# 2026-10-28 安卓新增功能移植验证

参考版本、功能清单和平台差异见 [移植记录](../upstream/2026-10-28-android-followup.md)。

## 当前证据

- Android参考同步：874文件逐一SHA-256匹配，独立检出工作区干净。
- Rust主机：192项通过。3项符号链接行为测试因Windows当前进程没有创建符号链接权限未执行；普通文件、空文件、长度限制、目录索引测试已拆除不相关的链接fixture并补跑。
- C原生：73项通过，包含AES、CENC、WSOLA、重采样、畸形输入和FFmpeg媒体比较。
- OHOS原生库：ARM64、x64 release构建成功，源摘要均为 `720927ac961ce740755b4f3cc044df7969ff04309036240280967637ef184241`。
- Flutter全量：2584项通过、13项明确跳过。跳过中的9项真实FRB集成随后使用主机DLL独立执行，9/9通过；其余为平台/SDK特定测试，不计作已通过。
- Dart静态分析：No issues found。原生ArkTS转译行为测试：33/33通过（包含亮度、PiP/TTS/媒体、登录和采集文件）。这些测试替换了OS服务，不能代替设备功能验收。
- UI源码：126个上游页面/组件中118个规范化文本一致；58个资源中56个一致。8个源码适配文件与品牌说明/图标共10处差异记录在 `docs/upstream/ui-parity-review.json`，检查同时锁定两端内容摘要，不接受未审查漂移。
- ARM64 debug HAP：第二次构建成功，包内最低/target均为60100023（HarmonyOS 6.1/API23），编译SDK26.0.0.105；包内ARM64核心与本次剥离后的原生库SHA-256一致。第一轮失败记录已提交。
- 独立源码审查发现的登录关闭异常、迟到页面回调和原生安全区问题均已修复；补充了关闭异常回归，并通过最终ARM64 Release HAP编译。
- 最终包：`FanqieOH-20261028-android-sync-arm64-unsigned.hap`，107338388字节，SHA-256为 `25aa19de1e12f41077122620a6be3f3a07783776eb7accea64147f28d1238a70`。包内为release/debug=false，最低和target仍为60100023，原生核心与构建产物一致。保留1.0.0(126)版本及原bundle ID；本次是未发布、未签名的功能验证包。
- 第三次构建期间仅两份OHPM锁文件从debug HAR切换为release HAR；已核对前后manifest，业务源码无构建中修改。构建记录为 `docs/builds/20261028T144458405Z-04b1a5-release-ohos-arm64.md`。
- ZIP根条目命名另有[OpenHarmony 6.1静态实现依据](https://github.com/openharmony/bundlemanager_bundle_framework/blob/161dd82173c0fc31472f72f571a4876914c5c2a6/interfaces/kits/js/zip/src/zip.cpp#L205-L213)：普通文件使用BaseName，当前输入均为manifest和指定分卷文件；尚未做设备导出验收。

## 设备验收边界

上述构建验证时，`hdc list targets` 没有设备。主机测试和编译不能替代官方账号登录/人机验证、系统PiP、音量键、3倍速听感与时序、后台媒体卡片/耳机/蓝牙、ARM64真实HEVC以及HarmonyOS 6.1/API23真机验收。

上述功能验证阶段没有执行签名、安装、推送、标签或发布。

## 用户反馈与 v1.2.0 发布跟进

用户于 2026-10-28 明确反馈“刚才的更新测试通过；现在提交鸿蒙源码并发布release1.2.0”。此反馈针对前述功能验证包，不补充推定设备型号、系统版本或逐项验收结果。

随后将显示版本升为 1.2.0、构建号升为 127，保持 bundle ID、业务实现与最低 HarmonyOS 6.1/API23 配置。另行构建发布包，版本回归、构建记录、附件摘要及安装方式见 [v1.2.0 发布说明](../releases/v1.2.0.md)。本记录中的历史包名和摘要仍对应升级版本号前的测试包。
