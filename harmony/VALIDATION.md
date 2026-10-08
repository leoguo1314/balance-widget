# 验证记录

更新日期：2026-10-08。基于上游 `main` 的 `294d6444ac15f7f6ce6a9f17cc8a0c2a7a7cd7c5`，Android 版本 26.10.448。

## 小数汇率与导航自动刷新（23:40）

修复汇率输入框使用整数输入类型的问题，改用官方 `InputType.NUMBER_DECIMAL`；增加打开页面、返回前台、导航切换和再次点击当前导航的自动查询。仅在主页面可见且应用处于前台时运行定时查询，正在进行的查询不会重复启动；刷新保留未保存的设置输入，汇总使用已保存的汇率。

官方 API 26 `clean assembleHap` 成功：152.747 秒，34 个任务全部执行；新主签名 HAP 399643 字节，SHA-256 `fa6603bc06129287a233be2c32cac8aa71f4bd8698207a5c0897aee1faf90e51`。官方签名与摘要校验、真机安装、启动和可见应用验证均通过；65 项 Node 测试通过，无跳过。

真机实际验证 `7.25` 输入、保存、进程重启后读取、导航切换期间保留未保存输入、未点击刷新按钮时余额更新时间改变，以及再次点击当前“余额”导航刷新。测试完成后恢复了原汇率与刷新间隔。完整记录见 [小数与自动刷新验证](validation/DECIMAL_AUTO_REFRESH_2026-10-08.md)，脱敏结果见 [JSON](validation/DECIMAL_AUTO_REFRESH_RESULT_2026-10-08.json)。本次未等待完整五分钟计时周期，也未单独复测后台返回和账户编辑返回；这些触发点已编译，设备观察范围以上述用例为准。

## 原生存储与网络基线结果（23:10）

已使用本机官方 API 26 SDK 生成本人合法调试签名 HAP，并在 LMR-AL00 / HarmonyOS 7 API 26 手机上完成安装、启动、可见应用布局及截图验证。该结果证明主应用可以在当前手机运行，不代表所有余额平台、卡片、通知或 MiMo 登录已完成验收。

| 检查 | 结果 | 证明范围 |
| --- | --- | --- |
| 华为账号与本项目调试签名 | 已完成 | DevEco 为 `com.leoguo.balancewidget` 与当前手机生成调试 profile；材料仅保存在本机 |
| 官方 SDK `clean assembleHap` | 成功 | 最终 23:07 构建成功 40.399 秒；34 个任务中 33 个执行、1 个无需更新；ArkTS 应用/卡片编译、资源及签名打包 |
| 主签名 HAP | 397617 字节 | SHA-256 `e89234c8d6f80255684d6578050569513ebde2a46d79a673f29cd869f36b6e59` |
| 官方主包签名验证 | 通过 | `signature-delivery-main-20261008.txt`，profile 验证为 true |
| 真机安装与 Bundle Manager 检查 | 通过 | 签名 HAP 安装成功文本与已安装包名同时确认 |
| 真机启动与可见 UI | 通过 | EntryAbility 启动成功、应用包名布局匹配、`API 余额` 标题可见、应用截图获取成功 |
| Node 源码/业务/构建与签名隔离检查 | 65/65 通过，0 跳过 | 更新工具后最终重跑；原有 60 项加 5 项本机 HTTP 夹具检查；合成输入，不包含真实 API Key 或在线平台账户 |
| 合成余额 HTTP 夹具 | 5/5 本机 HTTP 用例通过 | 包含在上述 65 项中；验证本机服务行为 |
| `entry_test` 签名 HAP | 255109 字节，官方签名验证通过 | SHA-256 `590B1CFCA3905FD1855563FA764B4BB7FF0310BA7A3CBEE926D4EE45C00AA3A6`；最终 SDK 构建成功 6.852 秒，已签名安装并执行 |
| 原生 Core 与安全资产 | 通过 | `CoreParsingAndGrouping`、`VaultUnicodeRoundTrip`，包含长 UTF-8 分片往返与删除 |
| 原生 Stage Context 与 ArkData | 通过 | `ContextReady`；ApplicationContext 的 Stage 标识、数据库/偏好目录和存储 API 存在性检查通过 |
| 原生 SQLite/Preferences | 通过 | `HistoryPersistence`、`RepositoryLifecycle`，包含新实例读取、凭证替换、修订版、余额持久化、无凭证导出和自身测试账户/资产/历史行清理 |
| 完整存储原生测试套件 | 五项全部通过 | `native-delivery-storage-run-20261008.txt`，`PASS NativeDeviceSuite` / `TestFinished-ResultCode: 0` |
| 手机 HTTP 合成余额测试 | 最终包五项全部通过 | `native-delivery-http-run-20261008.txt`，包含诊断补丁，经 HDC 反向端口转发实际请求本机服务，`PASS FixtureHttpTestSuite` / `TestFinished-ResultCode: 0` |

主产物路径：`D:\GithubRepo\balance-widget-harmonyos-7\harmony\entry\build\default\outputs\default\entry-default-signed.hap`。

测试产物路径：`D:\GithubRepo\balance-widget-harmonyos-7\harmony\entry\build\default\outputs\ohosTest\entry-ohosTest-signed.hap`。

最新主应用构建日志为 `build-logs/compile-20261008-230732-675.txt`，记录 `BUILD SUCCESSFUL` 40.399 秒，34 个任务中 33 个执行、1 个无需更新。安装与启动证据在 `build-logs/device-20261008-230857-464/result.json`，整体状态为 `passed`；该目录还有脱敏布局与本机应用截图。最终测试包构建日志为 `build-logs/signed-native-tests-build-20261008-delivery.txt`，构建成功 6.852 秒，34 个任务中 33 个执行、1 个无需更新；官方 `verify-app` 成功后已签名安装。最终 Node 检查日志为 `build-logs/node-post-update-tests-20261008.txt`，65/65 通过且 0 跳过。存储原生测试 `build-logs/native-delivery-storage-run-20261008.txt` 与手机 HTTP 测试 `build-logs/native-delivery-http-run-20261008.txt` 分别五项 PASS，最终均为 `TestFinished-ResultCode: 0`。`build-logs/` 被 Git 忽略；完整签名材料、设备标识与可能含用户数据的截图不放入公共记录。

可提交的脱敏最终记录见 [签名安装结果](validation/SIGNED_DEVICE_RESULT_2026-10-08.json) 和 [存储与 HTTP 原生测试结果](validation/NATIVE_DEVICE_RESULT_2026-10-08.json)。

手机 HTTP 测试覆盖成功查询与历史、503 保留持久化缓存、恢复与采样、超时保留持久化缓存及自身测试账户/资产/历史行清理。最终交付包包含后续诊断补丁，并已完整重跑通过。服务端观测余额请求 4 次、控制更新 5 次，完成后恢复 `balance=100`、`httpStatus=200`、`delayMs=0`。隔离 UUID 对应的空数据库或偏好文件可能保留，未声称文件全部删除。此前一次执行因 HDC 反向转发消失失败，重新设置转发后通过；转发失效不作为平台余额接口结果。

先前签名构建 `build-logs/compile-20261007-231354-922.txt` 成功 9.582 秒，主 HAP 为 397621 字节、SHA-256 `fbd3e583b6e5afdf6d5cabe30446410f4c8c99155da0c054fa644bfb3417245b`，其安装与启动记录 `device-20261007-231429-022/result.json` 也通过。22:45 构建 `compile-20261008-224525-910.txt` 成功 13.274 秒、34 个任务全部执行，主 HAP 为 397612 字节、SHA-256 `E677E63E05D6F22BE12EC32030884F4CA057EEF3DFE84043BC47C2EF2ED65841`，`device-20261008-224624-120/result.json` 通过。早期原生测试构建 `signed-native-tests-build-20261008-2240.txt` 成功 9.832 秒，34 个任务中 18 个执行、16 个无需更新；首次完整通过记录为 `native-device-test-run-20261008-2241.txt`，后续 `native-final-storage-run-20261008.txt`、`native-http-reverse-port-run-20261008.txt` 也通过。以上为历史结果，当前交付包以最新大小、摘要及 delivery 日志为准。

真机首次启动暴露的空 Want 参数问题已修复并重新构建安装。2026-10-07 的原生测试中 Core/Vault 已通过，但 History 与 Repository 失败，整套结果码为 1；后续诊断确认基础 Delegator Context 的 `stageMode=false`。现使用 `delegator.getAppContext().getApplicationContext()` 获取标准 Stage ApplicationContext，实际诊断的 Context、数据库/偏好目录、Stage 标识及 ArkData API 均可用，并于 2026-10-08 完成五项重测通过。存储测试继续使用独立 UUID 数据库和 Preferences 名称，主应用使用默认存储名称；不以模块目录差异推断隔离，只清理自身合成账户、资产和历史。此隔离方案与实际通过条件见 [原生测试说明](entry/src/ohosTest/README.md)。

调试配置使用 [本地签名隔离工具](tools/LOCAL_SIGNING.md) 的 `save/public/apply/check` 流程。公开源码保留严格 JSON、空 `signingConfigs` 和无产品签名引用；本地私有备份在被 Git 忽略的目录，暂存区由工具单独检查。签名隔离工具用例包含在上述 65 项 Node 检查中，不依靠上传证书来复现验证。

## 交接及首次未签名构建的历史记录

| 检查 | 结果 | 证明范围 |
| --- | --- | --- |
| Node.js 24.19.0 业务测试 | 45/45 通过 | 余额解析、地址策略、缓存、分组汇总、修订版隔离、采样、统计、分页、无凭证卡片数据 |
| 签名与 Node 原生 crypto 交叉测试 | 包含在上述 45 项中 | SHA-1、HMAC-SHA1、UTF-8、Base64、RPC URL 编码与签名 |
| TypeScript 5.9.3 严格类型检查 | `Core.ts` 与 `Signing.ts` 通过 | 只证明两个纯逻辑文件的 TS 类型；不证明 ArkTS UI 或系统 Kit 兼容 |
| 项目结构脚本 | 通过 | JSON 配置、API 26 参数、页面/卡片入口、资源与本地 import 引用、网络选项 |
| Windows 本机 Node.js 24.14.1 回归 | 45/45 通过 | 2026-10-07 实际运行；沿用合成输入，不包含真实凭证 |
| 官方 API 26 SDK 原生构建 | `assembleHap` 成功 | ArkTS 应用/卡片字节码、资源编译及未签名 HAP 打包；见 [构建证据](validation/NATIVE_BUILD_2026-10-07.md) |
| USB 真机条件检查 | API 26 手机可用 | LMR-AL00，HarmonyOS 7.0.0.109；设备标识留在本机 |
| 本项目调试签名（首次编译时） | 当时等待用户账号登录 | 当时已有 profile 为其他包名；此条件已在后续本人账号登录和新 profile 生成后解决 |
| 新增构建/本地签名检查用例 | 6/6 通过，总计 Node 51/51 | 本机 JSON5、签名脱敏、API/资源/网络约束与默认 CI 模式；不证明签名有效 |
| 独立 `entry_test` 原生测试 HAP（首次） | 官方 SDK 未签名编译和打包通过 | 当时仅证明 Runner 编译；后续签名与设备结果见上方最新记录 |
| 设备验证脚本 | PS 5.1 语法、11/11 离线分支通过 | 安装/启动业务错误、错误 API、多设备、不可见 UI 等返回非零；离线用例不是设备运行 |
| 真机安装状态检查（首次） | 当时未安装；脚本正确返回非零 | [脱敏原始结果](validation/DEVICE_PREFLIGHT_2026-10-07.json)，当时未执行 unsigned HAP 安装或应用启动 |

测试使用合成 JSON 与测试字符串，不包含真实凭证，不会调用聊天接口。

## Windows 本地构建准备

用户已提供 DevEco Studio、Command Line Tools、DevEco Testing 的本机安装目录。已增加 `tools/build-hap.ps1`，默认匹配 Studio 与 Command Line Tools 的路径，记录工具版本、SDK 信息、检查结果与原生构建日志。Testing 留待设备测试阶段。资源检查改用跨平台 `basename`；扫描排除依赖、缓存与构建目录，避免重复构建时把生成文件当成源码。CI 增加 Windows 执行平台，以及 Windows PowerShell 语法、原生命令输出和错误退出码传播检查。

Linux 本环境使用 PowerShell 7.6.6 解析脚本并检查工具查找、标准输出/错误日志、成功退出码和非零退出码；均通过。这些只验证脚本包装行为，没有调用鸿蒙 SDK。

以上 Linux 包装检查是交接前的历史记录。2026-10-07 已在用户 Windows 本机实际执行工具发现和原生构建：Studio/Command Line Tools 26.0.0.821、SDK API 26 / 26.0.0.105、Hvigor 6.26.4、ohpm 26.0.0.630、工具包 Node.js 24.14.1、Studio JBR 25.0.2。修复 SDK 检出的卡片配置、空资源及 ArkTS/通知 API 类型问题后，真实 `assembleHap` 成功。

最终交付前用户已更新 Studio。实际配套环境为 DevEco Studio 26.0.0.851、Hvigor 6.26.8、JBR 25.0.2、Node.js 24.14.1、API 26 / ETS 26.0.0.105，SDK 根为 `D:\HarmonyosDevTools\DevEco Studio\sdk`。主包实际构建命令为：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\harmony\tools\build-hap.ps1 `
  -LocalSigning -SdkHome 'D:\HarmonyosDevTools\DevEco Studio\sdk'
```

首次未签名阶段的干净构建主产物为 `entry/build/default/outputs/default/entry-default-unsigned.hap`，356091 字节，SHA-256 `C4B8E5B23EE120569BC6A39CE70208833275383E09DF365215D409CB0298475F`。当时的测试产物为 `entry/build/default/outputs/ohosTest/entry-ohosTest-unsigned.hap`，134473 字节，SHA-256 `3891F495C2CCB53CA8C6840229EA1EAF5912A8B4CE4238239F7791A234D237A1`。两者均为历史未签名中间产物，后续构建会覆盖输出目录；当前签名产物以最新记录为准。已检查应用和卡片 `.abc` 及包内模块 API 参数。首次编译脱敏证据见 [NATIVE_BUILD_2026-10-07.md](validation/NATIVE_BUILD_2026-10-07.md)；原始日志留在 Git 排除的 `build-logs/`。

同时修复七牛查询及导出文件名的本地日期、通知错误依赖“计入汇总”开关、导出遗漏 Settings 等问题。首次未签名阶段的账号登录阻碍已解决，后续完成了匹配 profile 的签名、真机安装和启动。

## 尚未完成的功能验收

- 合成余额查询、错误缓存和超时状态在可见 UI 中的显示；原生 HTTP 测试已验证请求及存储行为。
- 可见 UI 账户新增、编辑、删除及凭证错误提示；原生测试已验证账户存储生命周期。
- 原生 UI：小屏手机、软键盘、系统返回、长名称、滚动、字体放大和服务卡片尺寸。
- 网络：有效/失效 Key、无网、限流、TLS 错误、请求超时、重定向和前后台切换。
- 至少一个真实 DeepSeek/OpenRouter 账户与控制台余额对比；其他平台逐个核验。部分上游预设地址可能失效。
- MiMo 官方 WebView 登录、Cookie 验证、会话过期后缓存标识、重新登录。
- 安全资产：实际长 Cookie、首次解锁前读取、重启后读取、存储失败、更换凭证、卸载。合成长 UTF-8 分片往返及删除已通过原生测试，但这些生命周期条件仍未验证。
- SQLite：设备重启持久化、变化/不变的实际时间采样节奏、180 天清理、文件选择器导出。新实例持久化及合成账户修订版已通过原生测试，不代替这些完整生命周期验收。
- 卡片：添加/删除多个实例、分页、系统定时更新、点击刷新打开应用；FormExtensionAbility 回调后生命周期约 10 秒，需验证网络与存储能在预算内完成，否则保留缓存并使用打开应用刷新。
- 通知：首次授权、拒绝授权、低余额、同账户一天内限频。

已完成真实官方 API 26 SDK 编译、调试签名主 HAP 打包、当前 API 26 手机安装与启动，存储原生测试及手机 HTTP 合成余额测试分别五项全部通过。上述真实平台、可见 UI 状态、卡片、通知等功能清单仍待逐项验收；没有申请上架或发布商店版本。
