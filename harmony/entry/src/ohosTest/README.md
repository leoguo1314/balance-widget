# 真实设备原生测试

`OpenHarmonyTestRunner` 使用本机 API 26 SDK 的 `@kit.TestKit`，不依赖 Hypium。它执行实际 ArkTS 业务逻辑、AssetStoreKit、ArkData SQLite 和 Preferences；不调用外网，不启动应用主 Ability，不需要真实 API Key。

测试模块名为 `entry_test`。先安装同签名的主 HAP 与测试 HAP，再运行。Runner 在存储测试前用 `application.createModuleContext` 比较测试模块与 `entry` 的数据库和偏好目录；如果目录相同、缺失或创建失败，测试以非零结果结束，不写入主模块数据。Repository 使用新的实例，而非应用共享单例。每次只创建 UUID 条目，并在 `finally` 删除自己创建的账户、资产分片和历史；没有清空全库操作。资产删除后逐片查询，只有空结果或 SDK 的 `NOT_FOUND` 才算删除成功。

测试包含余额解析及同组去重、900 字节边界内跨 UTF-8 字符的凭证往返、安全资产删除、SQLite 新实例读取及删除、账户新增/改名/保留凭证/替换凭证/修订版/余额持久化/无凭证导出/删除。日志仅有 `PASS` 或 `FAIL` 加测试名称。任何断言、原生 API 或清理失败都会使 `finishTest` 的结果码为 `1`。

在 `harmony/` 下，使用本机配套 SDK/Node/Java 环境执行官方 Hvigor（不要和其他构建并发）：

```powershell
& 'D:\HarmonyosDevTools\command-line-tools\bin\hvigorw.bat' --mode module -p product=default -p module=entry@ohosTest -p buildMode=debug assembleHap --no-daemon
```

若工具安装只有 `hvigorw.js`，使用本机 Node 运行该入口并传递相同参数。测试 HAP 一般生成在 `entry/build/default/outputs/ohosTest/`；以真实构建输出为准。未签名 HAP 不能作为安装验证结果；签名配置由本机合法调试签名提供。

将主 HAP 和测试 HAP 安装到选定的 API 26 设备后：

```powershell
& $HdcPath -t $DeviceId shell 'aa test -b com.leoguo.balancewidget -m entry_test -s unittest /ets/testrunner/OpenHarmonyTestRunner -s timeout 120000 -w 120000'
```

`$HdcPath` 和 `$DeviceId` 必须取本机工具路径与 `hdc list targets` 实际返回值。2026-10-07 已在连接设备上只读执行 `hdc shell aa test -h`，确认支持 `-w <wait-time>`。[OpenHarmony 官方 aa 文档](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/tools/aa-tool.md#启动测试框架命令test)说明 `-w` 的单位为毫秒；这里等待测试完成，最多 120 秒。`-s timeout` 是传入测试框架的参数，不能替代命令侧的等待。

验收需同时保存原生命令日志、每项结果及最终 `finishTest` 状态；只有 `PASS NativeDeviceSuite` 与结果码 `0` 可视作通过。单独的 `user test started.`、HDC 退出码为零或等待超时，都不能证明测试通过；缺少最终结果时应记录为未完成。测试源码可编译不等于设备执行成功。此 Runner 不替代可见 UI、桌面卡片、通知授权、MiMo 登录或真实平台余额对照验证。
