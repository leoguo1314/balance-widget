# 小数汇率与导航自动刷新验证

日期：2026-10-08。修复整数输入类型过滤汇率小数点，以及主页面和导航进入时未主动查询的问题。

## 改动

- 汇率输入使用官方 API 26 `InputType.NUMBER_DECIMAL`，保存仍校验有限数值、正数及不超过 100。
- 主页面显示、从后台返回、切换余额/统计/设置，以及再次点击当前导航时触发查询；默认五分钟前台定时查询继续工作，间隔是可选调整。
- 页面隐藏或应用进入后台时停用定时查询；查询进行中不启动重复请求。
- 异步余额更新只同步账户/余额，不覆盖尚未保存的汇率及间隔。汇总使用已保存的汇率。

## 官方 SDK、签名与安装

实际执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File harmony/tools/build-hap.ps1 -LocalSigning -SdkHome 'D:\HarmonyosDevTools\DevEco Studio\sdk'
```

Studio 26.0.0.851、Hvigor 6.26.8、Node 24.14.1、JBR 25.0.2、API 26 / ETS 26.0.0.105。`compile-20261008-232628-688.txt` 记录 `BUILD SUCCESSFUL in 2 min 32 s 747 ms`，34 tasks，34 executed，0 up-to-date。另一次完整 Node 回归 65/65，通过且无跳过，日志 `decimal-auto-refresh-node-tests-20261008.txt`。

- 主签名包：`D:\GithubRepo\balance-widget-harmonyos-7\harmony\entry\build\default\outputs\default\entry-default-signed.hap`。
- 大小：399643 字节。
- SHA-256：`fa6603bc06129287a233be2c32cac8aa71f4bd8698207a5c0897aee1faf90e51`。
- 官方 `verify-app` 校验代码签名、摘要和权限签名，退出码 0；日志 `build-logs/decimal-auto-refresh-signature-20261008.txt`。
- `verify-device.ps1` 实际安装、包名查询、启动、可见标题与截图均通过；结果 `build-logs/device-20261008-233154-828/result.json`。截图、原始页面和个人设置备份仅保留本机。

## 真机 UI 结果

使用官方 HDC / UITest 操作实际 TextInput、按钮和导航，不编辑源数据文件，不读取凭证。`7.25` 是本次测试输入，未作为用户的最终汇率。

| 用例 | 结果 |
| --- | --- |
| 输入包含小数点的 `7.25` | 字段实际内容完全匹配 |
| 未保存时切换统计、余额、设置 | 输入仍为 `7.25`，未被异步查询覆盖 |
| 保存小数 | 观察到“设置已保存” |
| 强制停止并重新启动后进入设置 | 读取到 `7.25`，证明实际持久化 |
| 切换统计、设置、余额，不点击刷新按钮 | 余额页面的成功更新时间改变 |
| 再次点击当前余额导航 | 成功更新时间再次改变 |
| 恢复用户原设置并重启读取 | 原汇率、原间隔均完全匹配 |

UITest 的 `inputText` 会向原内容追加，初次注入没有替换旧文本；随后用官方键码 Ctrl+A (`2072`/`2017`) 全选替换，再验证完全匹配。这个工具输入细节与小数支持无关。测试结束后主应用已返回余额页，用户账户和凭证未修改。

脱敏、机器可读结果见 [DECIMAL_AUTO_REFRESH_RESULT_2026-10-08.json](DECIMAL_AUTO_REFRESH_RESULT_2026-10-08.json)。本次未等待完整五分钟计时周期，后台返回与账户编辑返回未单独实机复测。此前原生存储和网络基线见 [SIGNED_DEVICE_2026-10-08.md](SIGNED_DEVICE_2026-10-08.md)；服务卡片、通知、MiMo 和外部平台完整对照仍按既有清单验收。
