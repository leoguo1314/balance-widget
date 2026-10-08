# 真实设备原生测试

`OpenHarmonyTestRunner` 使用本机 API 26 SDK 的 `@kit.TestKit`，不依赖 Hypium。它执行实际 ArkTS 业务逻辑、AssetStoreKit、ArkData SQLite 和 Preferences；不调用外网，不启动应用主 Ability，不需要真实 API Key。

测试模块名为 `entry_test`。先安装同签名的主 HAP 与测试 HAP，再运行。Runner 使用 `delegator.getAppContext().getApplicationContext()` 获取标准 Stage ApplicationContext；仅将基础 Context 断言为其他类型不会补齐 Stage 包装。测试为 HistoryStore 和 Repository 显式传入独立 UUID 数据库名及 Preferences 名，而不是依赖不同模块的目录。模块 Context 的目录不同不构成数据隔离保证，不能据此访问主应用默认库。Repository 使用新的实例，而非应用共享单例。每次只创建 UUID 条目，并在 `finally` 删除自己创建的账户、资产分片和历史行；隔离 UUID 对应的空数据库/偏好文件可能保留，没有清空全库操作。资产删除后逐片查询，只有空结果或 SDK 的 `NOT_FOUND` 才算删除成功。

测试包含余额解析及同组去重、900 字节边界内跨 UTF-8 字符的凭证往返、安全资产删除、Stage Context 与 ArkData API 可用性、SQLite 新实例读取及删除、账户新增/改名/保留凭证/替换凭证/修订版/余额持久化/无凭证导出/删除。日志只包含 `PASS` 或 `FAIL`、测试名称、失败阶段/数字错误码，以及 Context/API 存在性布尔值，不打印目录内容、异常原文或凭证。任何断言、原生 API 或清理失败都会使 `finishTest` 的结果码为 `1`。

2026-10-08 最终测试 HAP 已完成官方 SDK 签名构建、官方 `verify-app` 验证、真机安装及实际执行。产物为 `entry/build/default/outputs/ohosTest/entry-ohosTest-signed.hap`，255109 字节，SHA-256 `590B1CFCA3905FD1855563FA764B4BB7FF0310BA7A3CBEE926D4EE45C00AA3A6`。构建日志 `build-logs/signed-native-tests-build-20261008-delivery.txt` 记录成功 6.852 秒，34 个任务中 33 个执行、1 个无需更新；实际运行日志 `build-logs/native-delivery-storage-run-20261008.txt` 记录以下五项全部通过：

| 测试项 | 真机结果 |
| --- | --- |
| `CoreParsingAndGrouping` | PASS |
| `VaultUnicodeRoundTrip` | PASS |
| `ContextReady` | PASS |
| `HistoryPersistence` | PASS |
| `RepositoryLifecycle` | PASS |

最终结果为 `TestFinished-ResultCode: 0` / `TestFinished-ResultMsg: PASS NativeDeviceSuite`。此前 2026-10-07 的存储失败已通过 Context 修复后重测解决：基础 Delegator Context 的 `stageMode=false`，通过 `getApplicationContext()` 后 `stageMode=true`，数据库/偏好目录和 ArkData API 存在性检查均为 true。此修复使用平台的标准 ApplicationContext 包装，相关实现可见 [OpenHarmony Context 源码](https://gitee.com/openharmony/ability_ability_runtime/blob/master/frameworks/js/napi/app/context/context.js)。主应用 HAP 已独立通过安装、启动和可见 UI 验证，结果见 [VALIDATION.md](../../../VALIDATION.md)。

`FixtureHttpTestRunner` 另外执行手机到本机 [合成余额服务](../../../tools/device-fixture-server.README.md) 的真实 HTTP 请求，使用虚构凭证、独立 UUID 存储和 HDC 反向端口转发，不访问真实余额平台。包含诊断补丁的最终测试包实际运行日志 `build-logs/native-delivery-http-run-20261008.txt` 记录以下五项全部通过：

| HTTP 测试项 | 真机结果 |
| --- | --- |
| `FixtureHttpSuccessAndHistory` | PASS |
| `FixtureHttp503RetainsPersistedCache` | PASS |
| `FixtureHttpRecoveryAndSampling` | PASS |
| `FixtureHttpTimeoutRetainsPersistedCache` | PASS |
| `FixtureHttpOwnedDataCleanup` | PASS |

最终结果为 `TestFinished-ResultCode: 0` / `TestFinished-ResultMsg: PASS FixtureHttpTestSuite`。服务端观测 `balanceRequests=4`、`controlUpdates=5`，结束后控制恢复为 `balance=100`、`httpStatus=200`、`delayMs=0`。此前一次运行因 HDC 反向转发消失失败，重新建立转发后通过；运行 HTTP 测试前必须确认本机服务和转发仍有效。最终包已覆盖诊断补丁，不沿用旧版本通过记录作为最终包证据。

历史构建 `signed-native-tests-build-20261008-2240.txt` 成功 9.832 秒，34 个任务中 18 个执行、16 个无需更新；首次存储完整通过记录为 `native-device-test-run-20261008-2241.txt`，其后 `native-final-storage-run-20261008.txt`、`native-http-reverse-port-run-20261008.txt` 也通过。当前交付摘要和运行结果以 delivery 日志为准。

在 `harmony/` 下，使用本机配套 SDK/Node/Java 环境执行官方 Hvigor（不要和其他构建并发）。最终交付环境为 Studio 26.0.0.851、Hvigor 6.26.8、Node.js 24.14.1、JBR 25.0.2、API 26 / ETS 26.0.0.105；实际测试构建命令为：

```powershell
$env:DEVECO_SDK_HOME = 'D:\HarmonyosDevTools\DevEco Studio\sdk'
$env:NODE_HOME = 'D:\HarmonyosDevTools\command-line-tools\tool\node'
$env:DEVECO_NODE_HOME = $env:NODE_HOME
$env:JAVA_HOME = 'D:\HarmonyosDevTools\DevEco Studio\jbr'
$env:PATH = "$env:NODE_HOME;$env:JAVA_HOME\bin;D:\HarmonyosDevTools\command-line-tools\bin;$env:PATH"
& 'D:\HarmonyosDevTools\command-line-tools\bin\hvigorw.bat' --mode module -p product=default -p module=entry@ohosTest -p buildMode=debug assembleHap --no-daemon
```

先执行主包的 `clean assembleHap`，再执行测试包的 `assembleHap`；测试构建不添加 `clean`，避免删除同一 `entry` 构建目录中的主包产物。

若工具安装只有 `hvigorw.js`，使用本机 Node 运行该入口并传递相同参数。测试 HAP 一般生成在 `entry/build/default/outputs/ohosTest/`；以真实构建输出为准。未签名 HAP 不能作为安装验证结果；签名配置由本机合法调试签名提供。

将主 HAP 和测试 HAP 安装到选定的 API 26 设备后：

```powershell
& $HdcPath -t $DeviceId shell 'aa test -b com.leoguo.balancewidget -m entry_test -s unittest /ets/testrunner/OpenHarmonyTestRunner -s timeout 120000 -w 120000'
```

执行手机 HTTP 测试时，先在本机启动合成余额服务，再建立转发并运行另一个 Runner：

```powershell
& $HdcPath -t $DeviceId rport tcp:41727 tcp:41727
& $HdcPath -t $DeviceId shell 'aa test -b com.leoguo.balancewidget -m entry_test -s unittest /ets/testrunner/FixtureHttpTestRunner -s timeout 120000 -w 120000'
```

`$HdcPath` 和 `$DeviceId` 必须取本机工具路径与 `hdc list targets` 实际返回值。2026-10-07 已在连接设备上只读执行 `hdc shell aa test -h`，确认支持 `-w <wait-time>`。[OpenHarmony 官方 aa 文档](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/tools/aa-tool.md#启动测试框架命令test)说明 `-w` 的单位为毫秒；这里等待测试完成，最多 120 秒。`-s timeout` 是传入测试框架的参数，不能替代命令侧的等待。

验收需同时保存原生命令日志、每项结果及最终 `finishTest` 状态；存储套件要求 `PASS NativeDeviceSuite`，HTTP 套件要求 `PASS FixtureHttpTestSuite`，并分别确认结果码 `0`。单独的 `user test started.`、HDC 退出码为零或等待超时，都不能证明测试通过；缺少最终结果时应记录为未完成。测试源码可编译不等于设备执行成功。这两个 Runner 不替代可见 UI、桌面卡片、通知授权、MiMo 登录或真实平台余额对照验证。
