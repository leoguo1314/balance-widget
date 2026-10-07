# Windows 本机 API 26 原生构建证据

日期：2026-10-07（Asia/Shanghai）。执行目录：`D:\GithubRepo\balance-widget-harmonyos-7`。

从源码 ZIP 安全恢复 Git 关联，接续远端 `harmonyos-7` 的 `b97ae2515afa4b44812c5a6d4b94bcd736ef52cb`。使用 mixed reset 建立索引，没有硬重置或覆盖工作文件。最初下载文件与该提交一致；后续差异为本次修复。

## 实际工具版本

| 工具 | 版本 / 本机位置 |
| --- | --- |
| DevEco Studio | `26.0.0.821`，`D:\HarmonyosDevTools\DevEco Studio` |
| Command Line Tools | `26.0.0.821`，`D:\HarmonyosDevTools\command-line-tools` |
| SDK ETS | API `26`，`26.0.0.105`，Command Line Tools 的 `sdk/default` |
| Node.js | `24.14.1`，工具包自带 `tool/node/node.exe` |
| Hvigor | `6.26.4` |
| ohpm | `26.0.0.630` |
| Java | Studio JBR OpenJDK `25.0.2`，`JBR-25.0.2+1-329.117-nomod` |
| hdc | `3.2.0f` |

## 真正执行的构建

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\harmony\tools\build-hap.ps1 -CheckOnly
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\harmony\tools\build-hap.ps1
```

包装脚本实际运行官方 Hvigor：

```text
hvigorw.bat --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon
```

真实失败并已修复的项目：

1. `form_config.json` 的空 `scheduledUpdateTime` 不符合 SDK 时间格式，移除未使用字段。
2. AppScope 的 `color` 资源数组不能为空，添加应用背景资源。
3. HTTP 头对象和两个 Select 的 map 回调缺少 ArkTS 所需的显式类型。
4. API 26 的 `NotificationContent.contentType` 接受旧枚举；改用接受 `notificationManager.ContentType` 的正式 `notificationContentType` 字段。

成功日志：`harmony/build-logs/compile-20261007-223507-366.txt`（原始日志留在本机，不提交）。关键输出：

```text
Finished :entry:default@CompileArkTS... after 6 s 753 ms
Finished :entry:default@PackageHap... after 725 ms
WARN: No signingConfig found for product default
Finished :entry:assembleHap... after 1 ms
BUILD SUCCESSFUL in 12 s 332 ms
33 tasks in total: 18 executed, 15 up-to-date
```

同次执行结构检查及 Node 业务回归 `45/45` 通过。SDK 仍有可抛异常与 TextDecoder 弃用警告；构建没有隐藏警告。编译成功不代表所有设备行为通过。

## 未签名原生中间产物

| 项目 | 实际结果 |
| --- | --- |
| HAP | `D:\GithubRepo\balance-widget-harmonyos-7\harmony\entry\build\default\outputs\default\entry-default-unsigned.hap` |
| 字节数 | `356091` |
| SHA-256 | `D46F2B8C0C93A37DB4849C2D2ED6E0D4B63904C285381FDBE383A8EF4A0DDB9F` |
| bundleName | `com.leoguo.balancewidget` |
| minAPIVersion / targetAPIVersion | `260000026` / `260000026`（SDK 打包后的 API 26 编码） |
| 入口 / 设备类型 | `EntryAbility` / `phone` |
| 原生应用字节码 | `ets/modules.abc`，`229144` 字节 |
| 原生卡片字节码 | `ets/widgets.abc`，`20400` 字节 |

已实际用 ZIP 读取器检查上述 HAP，包含模块配置、资源索引、页面配置及两份字节码，不是空包或占位文件。此表记录第一次成功产物；后续重新构建的哈希以对应日志和设备验证记录为准。

## 设备与签名条件

本机 `hdc list targets` 找到一台 USB 手机，型号 `LMR-AL00`，API `26`，系统 `7.0.0.109(SP6C00E105R10P5)`。序列号、UDID 和完整 profile 不进入公共记录。初始 `bm dump` 确认本项目尚未安装。

本机已有调试签名材料，其 profile 匹配该手机，但包名与 `com.leoguo.balancewidget` 不匹配，不能直接用于本项目。实际打开 DevEco 的“项目结构 → 签名配置”后显示“自动签名失败，请先登录”。需要本人华为账号登录并为本项目生成合法调试 profile；登录由用户完成。

API 26 模拟器存在预置设备配置，但没有已下载镜像；未把预置配置描述成可运行模拟器。

本记录当前证明真实 SDK 编译及未签名 HAP 打包。签名、安装、启动和功能实测必须以另行实际执行的设备记录为准。

## 最终干净构建与可执行测试入口

最终生产构建日志 `compile-20261007-224910-627.txt`，执行 `clean assembleHap`，`BUILD SUCCESSFUL in 10 s 585 ms`；`34 tasks in total: 34 executed, 0 up-to-date`。结构检查通过，Node 回归为原 45 项业务测试加 6 项工具测试，合计 `51/51` 通过。

生产 HAP 路径同上，字节数 `356091`，最终 SHA-256 为 `C4B8E5B23EE120569BC6A39CE70208833275383E09DF365215D409CB0298475F`。ZIP 时间戳会随重新打包变化，以上第一次成功哈希仅对应其原始日志和本机归档。

新建独立 `entry_test` Runner，使用 SDK `TestKit`，覆盖 Core 解析/分组、安全资产 Unicode 分片写读删、SQLite 新实例读取/删除、账户新增/编辑/换凭证/持久化/导出/删除。写入前要求测试模块与主模块目录隔离，合成 UUID 数据在 `finally` 清理，错误及清理失败均返回测试失败；没有真实凭证或外网调用。

最终测试 HAP 构建日志 `native-tests-build-20261007-225040.txt`：`OhosTestCompileArkTS` 用时 `3 s 346 ms`，`BUILD SUCCESSFUL in 7 s 651 ms`，`34 tasks in total: 33 executed, 1 up-to-date`。文件为：

```text
D:\GithubRepo\balance-widget-harmonyos-7\harmony\entry\build\default\outputs\ohosTest\entry-ohosTest-unsigned.hap
bytes=134473
SHA256=3891F495C2CCB53CA8C6840229EA1EAF5912A8B4CE4238239F7791A234D237A1
```

此 Runner 已真正编译，**尚未在设备执行**。签名安装及 `aa test` 命令、结果判定见 `entry/src/ohosTest/README.md`。

新增 `tools/verify-device.ps1`，PS 5.1 解析通过；11/11 离线模拟分支检查通过。实际在已连接 API 26 真机执行无 HAP 参数的验证，设备型号/API 查询通过，`installed_bundle` 检查报告本项目未安装，脚本以非零退出。脱敏原始结果保存为 `DEVICE_PREFLIGHT_2026-10-07.json`；该负向检查不算应用安装或运行成功。
