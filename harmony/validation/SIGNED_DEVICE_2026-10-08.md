# 调试签名与真实设备验证（2026-10-08）

本记录是 23:10 完成的原生存储与网络基线，产物摘要对应当时版本。随后修复小数输入与导航自动刷新，最新主 HAP 和真机页面结果见 [后续验证](DECIMAL_AUTO_REFRESH_2026-10-08.md)。基线两包在本机 `build-logs/deliveries/baseline-20261008-2310/` 留存；主包当前标准输出路径已由新版替换。

华为账号由用户本人登录，DevEco 自动签名生成本项目的合法调试证书与 Profile。私钥、密码、证书、Profile、设备标识和真实账户数据留在本机，不提交到仓库。公开的结构化结果见 [安装与页面](SIGNED_DEVICE_RESULT_2026-10-08.json)及[原生存储与网络](NATIVE_DEVICE_RESULT_2026-10-08.json)。

## 最终真实产物

用户更新 DevEco Studio 后，最终使用 Studio `26.0.0.851`、Hvigor `6.26.8`、JBR `25.0.2`、Node `24.14.1`，API 26 / ETS `26.0.0.105`。实际 SDK 根目录为 `D:\HarmonyosDevTools\DevEco Studio\sdk`；Hvigor 入口为 `D:\HarmonyosDevTools\command-line-tools\bin\hvigorw.bat`。

| 产物 | 本机路径 | 字节数 | SHA-256 |
| --- | --- | --- | --- |
| 已签名主应用 | `D:\GithubRepo\balance-widget-harmonyos-7\harmony\entry\build\default\outputs\default\entry-default-signed.hap` | 397617 | `e89234c8d6f80255684d6578050569513ebde2a46d79a673f29cd869f36b6e59` |
| 已签名测试包 | `D:\GithubRepo\balance-widget-harmonyos-7\harmony\entry\build\default\outputs\ohosTest\entry-ohosTest-signed.hap` | 255109 | `590b1cfca3905fd1855563fa764b4bb7ff0310ba7a3cbee926d4ee45c00aa3a6` |

在 `harmony` 目录完整构建主应用：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/build-hap.ps1 -LocalSigning -SdkHome 'D:\HarmonyosDevTools\DevEco Studio\sdk'
```

主应用日志 `build-logs/compile-20261008-230732-675.txt`：`BUILD SUCCESSFUL in 40 s 399 ms`，34 tasks，33 executed，1 up-to-date。包装脚本实际执行 `clean assembleHap`，检查新 HAP 内的模块配置、资源和 ArkTS 字节码，并核对产物时间、大小及摘要。

主应用构建之后，测试模块用同一工具环境执行 `assembleHap`，命令详见 [原生测试说明](../entry/src/ohosTest/README.md)。`build-logs/signed-native-tests-build-20261008-delivery.txt`：`BUILD SUCCESSFUL in 6 s 852 ms`，34 tasks，33 executed，1 up-to-date。测试构建未再执行会清除主包的 `clean`。

官方 `hap-sign-tool.jar verify-app` 对以上两个最终 HAP 均返回 0，代码签名、SHA-256 摘要及权限签名通过。主包的 `verify-profile` 结果 `verifiedPassed=true`。本机日志为 `signature-delivery-main-20261008.txt`、`signature-delivery-main-profile-20261008.txt` 和 `signature-delivery-test-20261008.txt`；提取的签名材料仅留在被 Git 忽略的 `build-logs`。

## 真机安装、启动和页面

`verify-device.ps1` 在 USB 连接的 `LMR-AL00`、API 26、系统 `7.0.0.109(SP6C00E105R10P5)` 上安装最终主包，确认 Bundle Manager 中包名 `com.leoguo.balancewidget`、EntryAbility 启动成功、应用过滤布局中可见“API 余额”标题，并取得有效 PNG 截图。结果 `build-logs/device-20261008-230857-464/result.json` 为 `passed`，其中 HAP 摘要匹配上表。截图仅保留本机。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/verify-device.ps1 -HapPath 'entry/build/default/outputs/default/entry-default-signed.hap'
```

首次启动曾出现 `TypeError: Cannot read property parameters of undefined`，随后系统报生命周期超时。将 `EntryAbility` 改为 `want?.parameters?.refresh` 后，重新签名、安装和可见页面验证通过。不会把启动命令返回成功单独当作页面成功。真实用户账户未经测试编辑或删除。

## 最终原生存储测试

最终测试包实际签名、安装后执行：

```powershell
& $HdcPath -t $DeviceId shell 'aa test -b com.leoguo.balancewidget -m entry_test -s unittest /ets/testrunner/OpenHarmonyTestRunner -s timeout 120000 -w 120000'
```

`build-logs/native-delivery-storage-run-20261008.txt`：

```text
PASS CoreParsingAndGrouping
PASS VaultUnicodeRoundTrip
PASS ContextReady
PASS HistoryPersistence
PASS RepositoryLifecycle
TestFinished-ResultCode: 0
TestFinished-ResultMsg: PASS NativeDeviceSuite
user test finished.
```

实际测试覆盖 AssetStore Unicode 分片往返/删除，SQLite 新实例持久化读取/删除，Preferences 账户新增、编辑、凭证保留和替换、修订号、余额与历史持久化、无凭证导出及删除。此前基础 Delegator Context 的 `stageMode=false` 导致存储失败；改为 `getAppContext().getApplicationContext()` 后，Stage、数据库/偏好目录和 ArkData API 检查均通过。

每次显式传入 UUID 命名的独立偏好和数据库，绝不打开主应用默认库。清理仅涉及自己创建的测试账户、资产分片和历史行，并实际读回确认。空的 UUID 数据文件可能保留，不把行数据清理描述成删除所有文件。

## 最终真机网络测试

本机启动 [回环 HTTP 夹具](../tools/device-fixture-server.README.md)，安装测试包后设定并确认反向端口：

```powershell
& $HdcPath -t $DeviceId rport tcp:41727 tcp:41727
& $HdcPath -t $DeviceId fport ls
& $HdcPath -t $DeviceId shell 'aa test -b com.leoguo.balancewidget -m entry_test -s unittest /ets/testrunner/FixtureHttpTestRunner -s timeout 120000 -w 120000'
```

`fport ls` 必须包含该端口的 `[Reverse]` 任务。早期一次运行因转发任务消失而失败，重新建立后通过；最终重新安装测试包后再次确认转发，最终诊断补丁版本的真实结果为：

```text
PASS FixtureHttpSuccessAndHistory
PASS FixtureHttp503RetainsPersistedCache
PASS FixtureHttpRecoveryAndSampling
PASS FixtureHttpTimeoutRetainsPersistedCache
PASS FixtureHttpOwnedDataCleanup
TestFinished-ResultCode: 0
TestFinished-ResultMsg: PASS FixtureHttpTestSuite
user test finished.
```

日志 `build-logs/native-delivery-http-run-20261008.txt`。手机通过实际 NetworkKit/NetClient/BalanceService 发起四次余额请求：成功余额 100；HTTP 503 保留上次余额、时间戳及持久化缓存；恢复余额 42.5 并遵守五分钟历史采样；服务延迟 8000 ms 时客户端超时，保留恢复后的缓存。成功、失败和超时后均使用新 Repository 实例读回验证。凭证为测试源码中的虚构字符串，不调用外部平台。

主机状态记录 `build-logs/native-delivery-fixture-status-20261008.json` 确认余额请求数 4、控制更新数 5，服务恢复到余额 100 / HTTP 200 / 延迟 0。测试数据清理完成才输出 PASS；任何断言或清理失败均返回非零测试结果。验证后已删除本任务反向端口、停止本任务夹具服务，并返回主应用。

## 回归、签名隔离与边界

更新工具链后再次执行业务、签名隔离及本机 HTTP 夹具测试，65/65 通过，0 失败、0 跳过；日志 `build-logs/node-post-update-tests-20261008.txt`。GitHub Actions 已纳入 HTTP 夹具测试。CI 只验证源码配置、Node 逻辑和 Windows 构建包装，不替代上述真实 SDK 或设备测试。

`local-signing.mjs` 的 `public`/`apply` 流程保留本机签名备份，同时让 Git 暂存配置为无签名材料的严格 JSON；`check` 对暂存配置和私密目录忽略状态做实际检查。操作见 [LOCAL_SIGNING.md](../tools/LOCAL_SIGNING.md)。

更新安装期间曾出现 Java 21 签名类链接错误、生成清单缺失和 SDK 文件锁。待配套 JBR 25 恢复、IDE 停止并发构建后，使用更新版 Studio SDK 串行重建，两包的最终构建、签名、安装与测试均通过。此前 22:46 的签名主包及设备结果作为历史保留，最终交付以上表和本记录的最新日志为准。

可见 UI 的账户新增/编辑/删除及错误缓存呈现、桌面卡片添加/翻页/刷新、通知授权及提醒、MiMo 本人登录、各外部平台真实余额与官方控制台对照仍未完成独立验收。原生存储和合成网络通过不等于这些功能已通过；Android 的 VPN 等未移植能力也不属于本次产物。
