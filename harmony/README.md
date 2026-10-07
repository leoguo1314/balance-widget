# API 余额 · HarmonyOS 7 手机原生版

这是上游 BalanceWidget 的 Stage 模型原生移植工程，放在独立的 `harmony/` 目录中。Android Java、RemoteViews、AlarmManager 无法直接编译成此工程的 HAP，手机界面与服务卡片使用 ArkTS/ArkUI 实现。

**当前状态：源码初版，业务逻辑测试通过；尚未经过华为 SDK 编译、签名、模拟器或真机验证。当前没有可安装的 HAP。**

目标为 HarmonyOS 7 / API 26 手机：`compileSdkVersion`、`targetSdkVersion`、`compatibleSdkVersion` 均为 `26.0.0`，工程 `modelVersion` 也为 `26.0.0`。没有承诺旧版本系统兼容性。

## 已实现的源码

| 能力 | 鸿蒙实现 |
| --- | --- |
| 余额总览 | 原生 ArkUI 余额、统计、设置三个页签 |
| 账户与多个 Key | 每条凭证独立配置、查询、阈值和历史；最多 50 条 |
| 同账户去重 | 用户填相同账户组时，同平台组内取最大值；独立账户默认相加 |
| 查询与缓存 | 四个并发请求；超时或错误保留最后成功值并标缓存，未成功过则显示待查询 |
| 安全凭证 | AssetStoreKit 安全资产库，设备首次解锁后可读；不写入普通偏好、日志或导出文件 |
| 历史统计 | ArkData SQLite，变化时至少隔五分钟采样，不变时六小时采样，保留 180 天 |
| 桌面服务卡片 | 2×4 卡片，一页四项；翻页读取缓存，点击刷新打开应用查询 |
| 定时刷新 | 应用前台 2–360 分钟；桌面卡片由系统调度，当前页至多查询四项 |
| 低余额提醒 | 用户授权通知后启用，同账户最多每天提醒一次 |
| MiMo 登录 | 小米官方控制台 WebView；余额接口验证成功后保存会话 |
| 阿里云余额 | BSS `QueryAccountBalance`、RPC V1 HMAC-SHA1 签名；使用 AccessKeyId/Secret |
| 导出 | 用户通过文件选择器导出配置与历史，凭证引用清空；没有导入功能 |

金额增加只作为「余额增加」展示，不自动推断充值订单。消耗是快照差值的估计；两个快照之间的充值、消费、退款混合发生时无法还原真实账单。区间的第一个差值可能跨越区间起点，长时间未查询也会降低统计精度。美元折算率由用户手动设置，初始值 7.2 只是配置默认值。

更换凭证、接口、币种、请求方式或 JSON 路径会使该条目的历史进入新修订版，并清理旧余额，避免把不同账户的差异算作消费或充值。已发出的旧查询不能覆盖新配置。AssetStoreKit 按 900 字节分片存储长会话，完整读取后再解码；保存失败不降级为明文。

## 平台范围与验证边界

保留上游 16 个平台的配置，另有 WorkBuddy 网关与自定义平台。这里的「预设」表示请求及解析适配器已写入，**不表示已用真实 Key 验证在线接口**。

| 平台 | 解析/查询方式 | 特别说明 |
| --- | --- | --- |
| DeepSeek | `balance_infos[].total_balance` | 按所选 CNY/USD 读取 |
| SiliconFlow | `data.totalBalance` 等 | 优先总余额 |
| Moonshot、Novita | `data.available_balance` 等 | 优先可用余额 |
| OpenRouter | `total_credits - total_usage` | 需要账户余额查询权限 |
| Fireworks | 账户列表中可识别余额最大值 | 沿用上游口径；多组织账户请对照控制台核验 |
| 阿里云百炼 | 阿里云 BSS 账户余额 | 不是 DashScope 专属额度；需最小查询权限的 AccessKey |
| 小米 MiMo | 控制台 Cookie + 余额查询接口 | 登录流程和会话有效期待真机验证 |
| 七牛云 AI | 当前月份 `total_fee` | 后付费消费，排除总余额和余额差值消费估计 |
| ModelScope | 免费服务 | 无余额查询接口，不计入总额 |
| WorkBuddy | POST `/panel/api/balance_all`，汇总 `accounts[].credits` | 积分不计入人民币总额；手机访问电脑网关应填写电脑局域网 IP |
| 智谱、优云、火山、讯飞、书生、阶跃 | 沿用上游地址和余额候选字段 | 部分上游接口本来就未全量验证；可能需要后续更新 |
| 自定义 | HTTPS 地址 + GET 或空 JSON POST + JSON 路径 | 余额接口需单独提供，支持聊天接口不等于支持余额查询 |

查询默认只接受 HTTPS，使用系统 CA 校验，不自动跟随重定向，响应上限 1 MiB。内置平台地址固定，防止误向其他域发送凭证。自定义/网关 HTTP 需在该条目明确开启允许开关；它会以明文传输凭证。接口原始响应不显示到 UI，JSON 解析错误不会回显其中可能包含的密钥。

## 在 DevEco Studio 中构建

1. 安装华为官方 **DevEco Studio 26.0.0** 开发套件，确认带有 HarmonyOS 26.0.0 SDK。不要用 Android Studio、旧 API 12/14 SDK 或只安装 OpenHarmony SDK 来替代。
2. 打开本仓库的 **`harmony/` 目录**，同步 Hvigor 工程。官方开发套件的 `modelVersion` 是 `26.0.0`，对应 Hvigor 6.26.x、Node.js 24。
3. 将目标设备设置为手机。项目默认 bundleName 是 `com.leoguo.balancewidget`；如需更改，必须与后续签名配置使用的包名一致。
4. 首先执行 `Build → Build Hap(s)`，修复 SDK 提示的类型/API 或 UI 编译问题。此仓库的 Node 测试不能代替这一步。
5. 在 Project Structure → Signing Configs 中配置本人华为开发者账号和调试签名。签名证书、私钥、profile 和密码都保存在本机，不提交到仓库。
6. 连接 HarmonyOS 7 手机或 API 26 模拟器，运行 `entry`。仅使用已经签名且与设备调试 profile 相符的 HAP 安装。

本仓库没有包含签名配置和证书，也未申请 AppGallery 上架或开放特殊系统权限。

## 命令行验证与构建

业务检查只依赖 Node.js 24，不需要向测试提供任何真实 API Key：

```bash
node harmony/tools/check-project.mjs
node --test harmony/tests/*.test.mjs
```

使用官方 Command Line Tools 26.0.0 构建的示例（路径替换为实际安装位置）：

```bash
export DEVECO_COMMANDLINE_HOME=/opt/harmony-command-line-tools
export DEVECO_SDK_HOME="$DEVECO_COMMANDLINE_HOME/sdk"
export PATH="$DEVECO_COMMANDLINE_HOME/bin:$PATH"
bash harmony/tools/build-hap.sh
```

也可设置 `HVIGORW` 指向官方可执行文件。脚本检查工具存在后执行 `assembleHap`；缺少工具时以退出码 2 结束，不产生假安装包。产物通常在 `entry/build/default/outputs/default/`；真机安装仍需签名。

GitHub Actions 的 `Harmony core checks` 仅运行项目结构与逻辑测试。它**不声称**编译 HAP；官方 SDK、签名和真机回归需要另外执行。

## 与 Android 版的差异

Android 的 mihomo/VPN 服务、代理订阅、应用锁、生物识别、皮肤、壁纸取色、页面排序、手工充值修正、订单管理和备份导入尚未移植。当前使用手机已有网络连接，卡片没有常驻后台进程。Android 应用内部的设备密钥与鸿蒙安全资产库不能直接互通，请在鸿蒙版重新输入凭证。应用卸载会删除安全资产与本地数据。

真机验收清单见 [VALIDATION.md](VALIDATION.md)。上游代码遵循 AGPL-3.0，本目录继续使用相同许可证，参见根目录 [LICENSE](../LICENSE)。

## 官方依据

- [HarmonyOS 26.0.0 开发套件版本与兼容性](https://developer.huawei.com/consumer/en/doc/harmonyos-releases/deveco-studio-new-features-2600)
- [升级适配至 API 26（HarmonyOS 7）](https://developer.huawei.com/consumer/en/doc/harmonyos-releases/upgrade-adaptation)
- [获取官方命令行工具](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/ide-commandline-get)
- [OpenHarmony HTTP API](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-network-kit/js-apis-http.md)
- [安全资产存储](https://github.com/openharmony/docs/blob/master/en/application-dev/security/AssetStoreKit/asset-js-add.md)
