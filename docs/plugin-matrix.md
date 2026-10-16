# G1 依赖兼容性矩阵

> 后续实施更新：下面的“未验”表格保留初始静态审查基线。正式依赖已解算、固定 path/SHA，原应用 HAP 已构建并在模拟器运行；当前动态结果以 [实施验收记录](acceptance/2026-10-16-porting.md) 为准。具体 vendored 来源与变更见 [上游差异](upstream-changes.md)。所有 HarmonyOS 6.1 真机项仍未验，不能把旧静态表或新的模拟器结果当成完整平台通过。

核查日期：2026-10-16。范围：只读参考源码 `fqapp-source-code-android/fqapp-master` 的 `pubspec.yaml`、`pubspec.lock`、Dart 通道入口，公开发布包的元数据及一方鸿蒙适配源码。此文的“已核查”仅指静态证据；本项审查没有安装插件、执行正式全量 `pub get`、编译 HAP 或验证设备功能。

## 1. 当前结论

1. 工具链候选为 [CPF-Flutter/flutter_flutter](https://gitcode.com/CPF-Flutter/flutter_flutter) 的 `3.44.9+ohos-0.0.1-canary1`，固定提交 `39285df71a97ffe0c23241dcc459d997a9d8b7c6`；本轮工具链检查提供的 Dart 实测版本为 `3.12.2`。完整版本输出及最小工程结果由 `toolchain.md` 和构建记录维护。它满足参考工程 `sdk: ^3.12.2` 的数值下限，仍是 canary，不能因此声明全部框架、插件和 API 23 已兼容。
2. 参考锁文件的 SDK 下限是 Dart `>=3.12.2 <4.0.0`、Flutter `>=3.44.0`。已查询所有直接 hosted 依赖的精确发布版本及关键间接依赖；下表列出的版本均存在，所核查的 SDK 约束与该工具链数值兼容。SDK 中 `flutter_test` 固定的 `test_api 0.7.11`、`matcher 0.12.19`、`meta 1.18.0`、`collection 1.19.1` 等，以及 `flutter_localizations` 固定的 `intl 0.20.2`、`path 1.9.1`，均与参考锁文件对应值一致。
3. **没有发现足以断言“原始 hosted 依赖图必然不可解”的静态证据；但尚未执行正式全量依赖解算，不能把“数值满足”写成“pub get 已通过”。** SDK 的数值下限已具备继续验证的条件。完整 OHOS 依赖图还未确定：当前 hosted 平台包缺少 `ohos` 注册，需为下列插件选择、固定和验证实现；解算成功本身也不会证明平台插件可用。
4. **不能把现成鸿蒙标签全部替换后直接宣称有可复现的全量组合。** 已查到的 Connectivity 适配是 `7.0.0`，不满足原工程 `^7.3.1`；三个官方插件 fork 的 OHOS 子依赖仍指向活动分支；安全存储适配是独立包。需明确处理这些差异后运行全量解算、分析和构建，锁文件与 Git SHA 才能构成可复现证据。
5. FRB `2.13.0` 的正式 Dart 发布源码已包含 OHOS 动态库加载分支。G2 仍须证明当前 Rust/C 源码交叉编译、库打包、导出符号、异步调用、取消和生命周期，不能把这一静态分支写成 FRB 真机验证通过。

G1 状态：**依赖清点与候选来源已形成；正式 OHOS 全量解算、平台能力构建及 HarmonyOS 6.1/API 23 真机验证未完成。** 不降低系统下限，不通过无约束整体升级消除约束问题。

## 2. 直接依赖及纯 Dart / Flutter 层

下表“SDK”来自当日 `https://pub.dev/api/packages/<包名>/versions/<锁定版本>` 的官方发布元数据。未列出硬件最低 API 的纯 Dart 包不能单独给出 HarmonyOS 兼容承诺；其安装下限仍由工程、引擎及原生依赖共同决定。

| 包 | 参考锁定版本 | 发布 SDK 约束（Dart；Flutter） | 分类、Dart API 与移植处理 | 构建 / 真机 |
| --- | --- | --- | --- | --- |
| `http` | 1.6.0 | `^3.4.0`；无 | Dart 网络；先保持 API，验证 DNS/TLS、代理、取消和错误语义 | 未验 / 未验 |
| `archive` | 4.5.2 | `>=3.0.0 <4.0.0`；无 | Dart 归档；保持 TXT/EPUB 展开大小、文件数及路径保护 | 未验 / 未验 |
| `html` | 0.15.6 | `^3.2.0`；无 | Dart HTML；保持固定 0.15.6 与正文夹具 | 未验 / 未验 |
| `xml` | 7.0.1 | `^3.11.0`；无 | Dart XML；保持 API，以 EPUB/目录夹具验证 | 未验 / 未验 |
| `image` | 4.12.0 | `^3.0.0`；无 | Dart 图像；验证封面解码、缩放及内存限制 | 未验 / 未验 |
| `flutter_riverpod` / `riverpod` | 3.4.3 / 3.4.3 | 均 `^3.12.0`；前者 `>=3.0.0` | Flutter/Dart 状态；保持 API，回归路由、异步刷新、旧结果隔离 | 未验 / 未验 |
| `hive_ce` | 2.22.0 | `^3.4.0`；无 | 生产 Dart 存储；保留 box schema、AES 密钥及业务键 | 未验 / 未验 |
| `hive_ce_flutter` | 2.5.0 | `^3.4.0`；`>=3.44.0` | Flutter 初始化；间接依赖路径能力及 `material_ui` | 未验 / 未验 |
| `hive` / `hive_flutter` | 2.2.3 / 1.1.0 | 均 `>=2.12.0 <3.0.0` | 上游保留供旧测试；null-safe 包的 Dart 3 SDK 上限重解释适用，不能只看到 `<3.0.0` 就判定解算失败；旧测试仍要实际运行 | 未验 / 未验 |
| `cached_network_image` | 4.0.0 | `^3.12.0`；`>=3.44.0` | Flutter 缓存图片；保留 URL 会话前缀、缓存与失败重试，间接插件见下表 | 未验 / 未验 |
| `flutter_cache_manager` | 3.4.2 | `>=3.8.0 <4.0.0`；无显式下限 | Flutter/Dart 缓存；依赖 `path_provider ^2.1.5` 和 **`sqflite ^2.4.2`**，并非没有平台依赖的纯 Dart 包 | 未验 / 未验 |
| `lottie` | 3.6.1 | `^3.11.0`；`>=3.41.0` | Flutter 渲染；不改动画 API，验证引擎、帧率和资源 | 未验 / 未验 |
| `flutter_svg` | 2.3.0 | `^3.9.0`；`>=3.35.0` | Flutter 渲染；连同 vector_graphics 编译、shader/引擎路径验证 | 未验 / 未验 |
| `flutter_lucide` | 1.43.0 | `>=3.4.3 <4.0.0`；`>=1.17.0` | 字体图标；保持 API，检查字体打包和字形 | 未验 / 未验 |
| `cupertino_icons` | 1.0.9 | `^3.9.0`；无 | 字体资源；保持版本，验证打包 | 未验 / 未验 |
| `flutter_rust_bridge` | **2.13.0** | `>=3.9.2 <4.0.0`；无 | Dart FFI runtime；与 Rust crate / codegen 固定一致，见第 4 节 | 未验 / 未验 |
| `path_provider` | 2.1.6 | `^3.10.0`；`>=3.38.0` | 平台插件；hosted 版无 OHOS 声明，候选 fork 见第 3 节 | 未验 / 未验 |
| `shared_preferences` | 2.5.5 | `^3.9.0`；`>=3.35.0` | 平台插件；hosted 版无 OHOS 声明 | 未验 / 未验 |
| `url_launcher` | 6.3.2 | `^3.6.0`；`>=3.27.0` | 平台插件；hosted 版无 OHOS 声明 | 未验 / 未验 |
| `flutter_secure_storage` | 9.2.4 | `>=2.12.0 <4.0.0`；`>=2.0.0` | 平台插件；hosted 版无 OHOS 声明 | 未验 / 未验 |
| `connectivity_plus` | 7.3.1 | `>=3.2.0 <4.0.0`；`>=3.7.0` | 平台插件；hosted 版无 OHOS 声明 | 未验 / 未验 |
| `flutter_test` | SDK | 使用固定 Flutter-OH SDK | 开发测试；需实际运行，mock 通道不等同设备证据 | 未验 / 不适用 |
| `flutter_lints` | 6.0.0 | `^3.8.0`；无 | 开发静态规则；不表示运行功能可用 | 未验 / 不适用 |
| `shared_preferences_platform_interface` | 2.4.2 | `^3.9.0`；`>=3.35.0` | 测试直接依赖；接口与实现须一起核对 | 未验 / 未验 |
| `fake_async` | 1.3.3 | `^3.3.0`；无 | 开发假时钟；沿用生命周期/取消测试 | 未验 / 不适用 |

Dart 3 对 null-safe 旧包的 SDK 上限处理见 [Dart 3 官方迁移说明](https://dart.dev/resources/dart-3-migration#dart-3-backwards-compatibility)。此处理仅解决 SDK 约束，不保证旧包的源代码、平台实现或测试兼容。

关键间接包也有框架下限：`sqflite 2.4.3`、`material_ui 1.1.1`、`cupertino_ui 1.0.2` 均要求 Dart `^3.12.0` / Flutter `>=3.44.0`；`material_ui` 带 shader，必须包含在实际编译与页面验证中。[sqflite 发布元数据](https://pub.dev/api/packages/sqflite/versions/2.4.3)、[material_ui 发布元数据](https://pub.dev/api/packages/material_ui/versions/1.1.1)、[cupertino_ui 发布元数据](https://pub.dev/api/packages/cupertino_ui/versions/1.0.2)

## 3. 平台插件的一方候选来源

以下 SHA 由当日 `git ls-remote` 核对；已读取所列提交下的对应 `pubspec.yaml`。它们是**待集成候选**，不是已经采用或通过本项目验收的版本。API 23 安装下限要看最终工程及产物 metadata；目前未取得这些插件与本轮 3.44.9 canary / API 23 的成套构建和真机证据。

| 原包 / 锁定版本 | 鸿蒙候选、精确 ref 与源码路径 | SDK/API 证据、Dart API 差异与处理 | 构建 / 真机 |
| --- | --- | --- | --- |
| `path_provider` 2.1.6 | [CPF-Flutter/flutter_packages](https://gitcode.com/CPF-Flutter/flutter_packages)，tag `provider-v2.1.5-ohos-1.0.1` → `7cc9f4cfbd464943096dc7c87288252c543df5cb`；根包 `packages/path_provider/path_provider` 为 2.1.5，OHOS 包 `packages/path_provider/path_provider_ohos` 为 2.2.17 | Dart `^3.6.0` / Flutter `>=3.27.0`；声明 OHOS default_package 与 Dart 注册。2.1.5 满足根工程 `^2.1.0` 及缓存包 `^2.1.5`；属已说明的小版本回退。fork 将 foundation 约束改成 `<2.6.0`，不能照抄原锁文件。优先保持应用侧 getApplicationSupportDirectory 等 API；冷启/升级/缓存目录必须验证。最低 API 23 未验 | 未验 / 未验 |
| `shared_preferences` 2.5.5 | 同一仓库，tag `shared_preferences-v2.5.4-ohos-1.0.1` → `19bd50ff6d5eaa96f18c63796c51e1b4e78a7480`；`packages/shared_preferences/shared_preferences` 与 `shared_preferences_ohos` 均 2.5.4 | Dart `^3.9.0` / Flutter `>=3.35.0`；根包声明 OHOS，OHOS 包有原生及 Dart 注册。2.5.4 满足根 `^2.3.0`。核对 Legacy/Async/WithCache 实际使用面及类型、持久化、错误与退出重开；最低 API 23 未验 | 未验 / 未验 |
| `url_launcher` 6.3.2 | 同一仓库，tag `url_launcher_v6.3.2-ohos-1.0.2` → `f31db0d72e7a1d91dd023325a23dc2fba4b6ce4b`；`packages/url_launcher/url_launcher` 为 6.3.2，另需固定 `packages/url_launcher/url_launcher_ohos` | Dart `^3.6.0` / Flutter `>=3.27.0`；根包声明 OHOS。应用 launchUrl API 尽量保留，Android 设置/默认应用等意图须另行适配。launch mode、取消与无目标失败均未验；最低 API 23 未验 | 未验 / 未验 |
| `flutter_secure_storage` 9.2.4 | [CPF-Flutter/fluttertpc_flutter_secure_storage](https://gitcode.com/CPF-Flutter/fluttertpc_flutter_secure_storage)，annotated tag `9.2.4-ohos-1.0.0` 的 **peeled commit** 为 `ecc4257040163da3c4dd64d4fced5d4d24676a53`；采用候选是独立包 `flutter_secure_storage_ohos` 1.2.2，路径同名 | 独立包 Dart `>=2.19.6 <4.0.0` / Flutter `>=2.5.0`；文档记录 3.35.7-OH / SDK 6.0.1(21) 等历史组合，不能推作 API 23 验收。该提交中的原 `flutter_secure_storage` 9.2.4 本身仍无 OHOS 声明。独立包提供同名 Dart 类及原生 MethodChannel；需在 `SecureKeyStorage` 边界明确接入和注册方式，避免同时导入同名类。不能将加上包或捕获 MissingPluginException 当成密钥持久化完成 | 未验 / 未验 |
| `connectivity_plus` 7.3.1 | [CPF-Flutter/flutter_plus_plugins](https://gitcode.com/CPF-Flutter/flutter_plus_plugins)，tag `connectivity_plus-7.0.0-ohos.1.0.0` → `9514235dda402b432b860a31c69d4dc5153891f5`；`packages/connectivity_plus/connectivity_plus` 为 7.0.0 | Dart `>=3.2.0 <4.0.0` / Flutter `>=3.7.0`；有 OHOS 注册，文档仅历史 SDK 12/21 组合。**7.0.0 不满足根 `^7.3.1`**，不得作为无差异直接替换。选项是比较 7.0→7.3.1 API/修复后受控引入 OHOS 实现，或明确维护应用适配层/受审查的版本差异；List 结果、订阅取消及前后台恢复均需测。API 23 未验 | 未验 / 未验 |
| 间接 `sqflite` 2.4.3 | [CPF-Flutter/flutter_sqflite](https://gitcode.com/CPF-Flutter/flutter_sqflite)，annotated tag `2.4.2-ohos-1.0.0` 的 **peeled commit** 为 `5ef0761001378455e872e46d1c0620d39dcc1002`；`sqflite` 与 `sqflite_ohos` 均 2.4.2 | Dart `^3.5.0` / Flutter `>=3.7.0`；根包声明 OHOS，OHOS 包有 Dart 注册。2.4.2 满足缓存包 `^2.4.2`。根包使用同一仓库 `path: ../sqflite_ohos`，须确认 pub 能解析仓库内相对路径并锁定同一提交；不可把它错误解释为本机工程路径。验证缓存数据库创建、升级、并发、清理和跨重启。插件文档存在 system_basic 权限提示，集成时核对实际权限声明与普通应用可用性，不能擅自提高签名应用等级；API 23 未验 | 未验 / 未验 |

固定顶层 SHA 不足以完全固定依赖树。上述 `path_provider`、`shared_preferences`、`url_launcher` 的对应 OHOS 子包依赖分别仍写着 `br_path_provider-v2.1.5_ohos`、`br_shared_preferences-v2.5.4_ohos`、`br_url_launcher-v6.3.2_ohos` 活动分支，并使用旧仓库别名。集成时应为每个 OHOS 子包固定上述同一提交及正确 path，记录精确来源覆盖原因，并检查新锁文件的 `resolved-ref`；不能让一次解算无意追随分支变动。

用于复核的精确源码：[path_provider pubspec](https://raw.gitcode.com/CPF-Flutter/flutter_packages/raw/7cc9f4cfbd464943096dc7c87288252c543df5cb/packages/path_provider/path_provider/pubspec.yaml)、[Preferences pubspec](https://raw.gitcode.com/CPF-Flutter/flutter_packages/raw/19bd50ff6d5eaa96f18c63796c51e1b4e78a7480/packages/shared_preferences/shared_preferences/pubspec.yaml)、[URL pubspec](https://raw.gitcode.com/CPF-Flutter/flutter_packages/raw/f31db0d72e7a1d91dd023325a23dc2fba4b6ce4b/packages/url_launcher/url_launcher/pubspec.yaml)、[安全存储 OHOS pubspec](https://raw.gitcode.com/CPF-Flutter/fluttertpc_flutter_secure_storage/raw/ecc4257040163da3c4dd64d4fced5d4d24676a53/flutter_secure_storage_ohos/pubspec.yaml)、[Connectivity pubspec](https://raw.gitcode.com/CPF-Flutter/flutter_plus_plugins/raw/9514235dda402b432b860a31c69d4dc5153891f5/packages/connectivity_plus/connectivity_plus/pubspec.yaml)、[sqflite pubspec](https://raw.gitcode.com/CPF-Flutter/flutter_sqflite/raw/5ef0761001378455e872e46d1c0620d39dcc1002/sqflite/pubspec.yaml)。

## 4. FRB / Rust / 原生资产

- 参考 Dart runtime、生成文件、Rust crate 及 codegen 基线均为 **2.13.0**，不为绕过问题修改生成文件或混用版本。
- 已读取 [pub.dev 2.13.0 正式发布归档](https://pub.dev/api/archives/flutter_rust_bridge-2.13.0.tar.gz) 的 `lib/src/loader/_io.dart`。其第 60 行把 `Platform.operatingSystem == 'ohos'` 与 Android 分支共同处理，通过 `ExternalLibrary.open('lib$stem.so')` 加载；`ExternalLibrary` 内部使用 `dart:ffi` 的 `DynamicLibrary.open`。本项目生成的 stem 为 `fqapi_core`，即需要真实 OHOS ARM64 `libfqapi_core.so`。
- 这排除了“该 runtime 一定因未识别 ohos 而加载失败”的猜测，但不证明库已存在或能够装载。仍需构建 `aarch64-unknown-linux-ohos`、检查 ELF/ABI/依赖和生成符号、打包进正确 ABI 目录，再执行 version/init/health/request/cancel/shutdown/restart。Tokio、reqwest、rustls/ring、DNS、随机数、文件与 loopback 分别验证。
- 参考锁文件通过其他平台实现间接带入 `jni 1.0.3`、`jni_flutter 1.0.3`、`objective_c 9.5.0`、`hooks 2.0.2`、`code_assets 1.2.1` 等。其存在不等于 HAP 中需要 Android/iOS 原生库；须检查 OHOS 目标的插件注册与 native-assets/hook 实际选择，不擅自复制 `.dll`、Android NDK `.so` 或 iOS 库，也不未经证据将它们一律判作解算阻塞。
- C CENC 核心仍是后续 G3 的独立门槛；FRB 能加载不等于加密媒体、随机读取或 Flutter surface 可用。

## 5. 应用自定义通道

此处没有可直接登记为“已有鸿蒙实现”的包。对应精确实现 ref 将随本仓库新增代码提交固定；当前只读来源为参考基线 `5938f25dab2015f502ded1f2079ec2a51b8b4bc6` 的 Dart 契约及 Android 行为。以下实现均要求最低 HarmonyOS 6.1/API 23，尚无构建或真机结果。

| Dart 通道 | OHOS 接入目标 / Dart API 边界 | 完成门槛 | 构建 / 真机 |
| --- | --- | --- | --- |
| `fqapp/native_player`、`fqapp/native_player/events` | ArkTS 媒体、原生解密桥及 Flutter 输出表面；保留 Dart 事件/生命周期契约 | 明文与 CENC、Range/seek、首帧、音频、切页销毁、迟到事件隔离；先 G3 再接完整媒体 UI | 未验 / 未验 |
| `fqapp/reader`、`fqapp/reader/events` | 亮度、沉浸、保亮、安全区和字体；会话原值恢复 | 退出/后台恢复、旧会话不得覆盖新会话、系统返回和字体选择 | 未验 / 未验 |
| `fqapp/system_tts`、`fqapp/system_tts_events` | Core Speech Kit；能力差异通过 Dart 契约明确表达 | API 23 中文、语速、停止、跨章及后台策略；缺失范围事件不可伪造 | 未验 / 未验 |
| `fqapp/local_books` | 文档选择与沙箱导入 | TXT/EPUB、取消、异常文件、重开；保留大小与路径限制 | 未验 / 未验 |
| `fqapp/library_backup` | 系统保存/选择，沿用 JSON 预览与合并 | Android version 1 备份、重复导入幂等、错误与取消不假成功 | 未验 / 未验 |
| `fqapp/share` | 系统分享 | 成功/取消/无目标结果准确 | 未验 / 未验 |
| `fqapp/downloads` | 用户选择 TXT 输出文件并写入 | UTF-8、文件名、取消、磁盘满与写失败 | 未验 / 未验 |

还需验证 Flutter 内置方向、系统栏、剪贴板、返回键等平台通道；只实现七个应用通道不代表完整平台覆盖。

## 6. 下一步依赖门槛

1. 在受控 `app/` 进行最小 SDK / Stage 工程验证；保持最低 `6.1.0(23)`。最小工程的少量依赖解算通过不能冒充本表正式全量图通过。
2. 决定 Connectivity 的受控适配策略及安全存储接入方式，为根包和所有 OHOS 子包锁定 SHA/path；记录偏离参考 lock 的每一项，包含由 fork 限制造成的传递版本变化。若使用 override，列出为何必要、绕过了什么约束与新增验证责任。
3. 在受控工程运行正式依赖解算，保存退出码、SDK 版本和锁文件差异；确认所有 git 包 `resolved-ref`，无活动分支漂移。失败先区分 SDK、版本约束、包源/网络和原生插件问题，不把网络失败写成包不兼容。
4. 执行 Dart 分析与相关原有测试，至少覆盖 storage、图片缓存、取消/生命周期以及 TXT/EPUB 夹具；之后构建检查插件注册和 ABI。每次 HAP 构建尝试都遵循根目录本地规则，留下脱敏构建记录并本地提交。
5. G1 设备验收必须实际验证持久目录、Preferences 和安全密钥读写、杀进程重开及缺失/损坏错误。安全存储异常必须可见且保护旧数据，不利用上游明文/空库降级路径把通道缺失伪装成通过。
6. API 23 真机缺失时分别记录编译、模拟器、较高系统设备结果，G1 的 6.1 真机项继续未验；随后 G2/G3 通过前不批量导入全部页面。

只有正式全量解算、构建与对应设备证据产生后，才将上表相应状态改为已通过，并指向具体构建记录及验收记录。
