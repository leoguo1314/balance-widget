# 验证记录

日期：2026-10-07。基于上游 `main` 的 `294d6444ac15f7f6ce6a9f17cc8a0c2a7a7cd7c5`，Android 版本 26.10.448。

## 已执行

| 检查 | 结果 | 证明范围 |
| --- | --- | --- |
| Node.js 24.19.0 业务测试 | 45/45 通过 | 余额解析、地址策略、缓存、分组汇总、修订版隔离、采样、统计、分页、无凭证卡片数据 |
| 签名与 Node 原生 crypto 交叉测试 | 包含在上述 45 项中 | SHA-1、HMAC-SHA1、UTF-8、Base64、RPC URL 编码与签名 |
| TypeScript 5.9.3 严格类型检查 | `Core.ts` 与 `Signing.ts` 通过 | 只证明两个纯逻辑文件的 TS 类型；不证明 ArkTS UI 或系统 Kit 兼容 |
| 项目结构脚本 | 通过 | JSON 配置、API 26 参数、页面/卡片入口、资源与本地 import 引用、网络选项 |
| Windows 本机 Node.js 24.14.1 回归 | 45/45 通过 | 2026-10-07 实际运行；沿用合成输入，不包含真实凭证 |
| 官方 API 26 SDK 原生构建 | `assembleHap` 成功 | ArkTS 应用/卡片字节码、资源编译及未签名 HAP 打包；见 [构建证据](validation/NATIVE_BUILD_2026-10-07.md) |
| USB 真机条件检查 | API 26 手机可用 | LMR-AL00，HarmonyOS 7.0.0.109；设备标识留在本机 |
| 本项目调试签名 | 等待用户账号登录 | 现有 profile 为其他包名；DevEco 自动签名界面要求先登录 |
| 新增构建/本地签名检查用例 | 6/6 通过，总计 Node 51/51 | 本机 JSON5、签名脱敏、API/资源/网络约束与默认 CI 模式；不证明签名有效 |
| 独立 `entry_test` 原生测试 HAP | 官方 SDK 编译和打包通过 | Runner 已编译；实际设备执行仍等待签名 |
| 设备验证脚本 | PS 5.1 语法、11/11 离线分支通过 | 安装/启动业务错误、错误 API、多设备、不可见 UI 等返回非零；离线用例不是设备运行 |
| 真机安装状态检查 | 未安装；脚本正确返回非零 | [脱敏原始结果](validation/DEVICE_PREFLIGHT_2026-10-07.json)，未执行 unsigned HAP 安装或应用启动 |

测试使用合成 JSON 与测试字符串，不包含真实凭证，不会调用聊天接口。

## Windows 本地构建准备

用户已提供 DevEco Studio、Command Line Tools、DevEco Testing 的本机安装目录。已增加 `tools/build-hap.ps1`，默认匹配 Studio 与 Command Line Tools 的路径，记录工具版本、SDK 信息、检查结果与原生构建日志。Testing 留待设备测试阶段。资源检查改用跨平台 `basename`；扫描排除依赖、缓存与构建目录，避免重复构建时把生成文件当成源码。CI 增加 Windows 执行平台，以及 Windows PowerShell 语法、原生命令输出和错误退出码传播检查。

Linux 本环境使用 PowerShell 7.6.6 解析脚本并检查工具查找、标准输出/错误日志、成功退出码和非零退出码；均通过。这些只验证脚本包装行为，没有调用鸿蒙 SDK。

以上 Linux 包装检查是交接前的历史记录。2026-10-07 已在用户 Windows 本机实际执行工具发现和原生构建：Studio/Command Line Tools 26.0.0.821、SDK API 26 / 26.0.0.105、Hvigor 6.26.4、ohpm 26.0.0.630、工具包 Node.js 24.14.1、Studio JBR 25.0.2。修复 SDK 检出的卡片配置、空资源及 ArkTS/通知 API 类型问题后，真实 `assembleHap` 成功。

最终干净构建的主产物为 `D:\GithubRepo\balance-widget-harmonyos-7\harmony\entry\build\default\outputs\default\entry-default-unsigned.hap`，356091 字节，SHA-256 `C4B8E5B23EE120569BC6A39CE70208833275383E09DF365215D409CB0298475F`。测试产物为 `entry/build/default/outputs/ohosTest/entry-ohosTest-unsigned.hap`，134473 字节，SHA-256 `3891F495C2CCB53CA8C6840229EA1EAF5912A8B4CE4238239F7791A234D237A1`。两者均为未签名中间产物。已检查应用和卡片 `.abc` 及包内模块 API 参数。完整脱敏证据见 [NATIVE_BUILD_2026-10-07.md](validation/NATIVE_BUILD_2026-10-07.md)；原始日志留在 Git 排除的 `build-logs/`。

同时修复七牛查询及导出文件名的本地日期、通知错误依赖“计入汇总”开关、导出遗漏 Settings 等问题。本机真机已连接；当前需要用户在 DevEco 自行登录，为项目包名生成匹配的调试 profile。

## 尚未执行，安装前必须补做

- 调试签名与 API 26 手机/模拟器安装；校验 bundleName、profile 与设备身份。
- 原生 UI：小屏手机、软键盘、系统返回、长名称、滚动、字体放大和服务卡片尺寸。
- 网络：有效/失效 Key、无网、限流、TLS 错误、请求超时、重定向和前后台切换。
- 至少一个真实 DeepSeek/OpenRouter 账户与控制台余额对比；其他平台逐个核验。部分上游预设地址可能失效。
- MiMo 官方 WebView 登录、Cookie 验证、会话过期后缓存标识、重新登录。
- 安全资产：长 Cookie 分片、首次解锁前读取、重启后读取、存储失败、更换凭证、删除与卸载。
- SQLite：重启持久化、变化/不变采样节奏、不同修订版隔离、180 天清理、文件导出。
- 卡片：添加/删除多个实例、分页、系统定时更新、点击刷新打开应用；FormExtensionAbility 回调后生命周期约 10 秒，需验证网络与存储能在预算内完成，否则保留缓存并使用打开应用刷新。
- 通知：首次授权、拒绝授权、低余额、同账户一天内限频。

结论：已完成真实官方 API 26 SDK 编译和未签名 HAP 打包；签名、安装与功能验收仍须按实测记录确认。没有申请上架或发布商店版本。
