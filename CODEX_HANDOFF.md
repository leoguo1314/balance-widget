# 本地 Codex 执行任务：完成 HarmonyOS 7 手机版编译与验证

用户已要求将本任务交给 Codex 执行。请在用户的 **Windows 本机** 使用已安装的华为工具链继续，目标是生成真实的原生 HAP、修复编译错误，并在具备设备和签名条件时完成安装运行验证。

## 仓库与当前进度

- 用户 Fork：https://github.com/leoguo1314/balance-widget
- 工作分支：`harmonyos-7`；草稿 PR：https://github.com/leoguo1314/balance-widget/pull/1
- 本交接文件之前的代码提交：`eeda0f2436122c5c75fe76b6f8ffe496c8012111`。
- 原生工程在 `harmony/`，目标 HarmonyOS 7 / API 26 / SDK `26.0.0`，bundleName `com.leoguo.balancewidget`。
- 已有余额页、账户配置、安全凭证存储、历史统计、MiMo 登录、低余额通知和 2×4 桌面服务卡片源码。
- 45 项 Node 业务测试、资源引用与配置检查已在 Linux 和 Windows CI 上通过；Windows PowerShell 构建包装的语法、输出记录和非零退出码处理也通过。
- 已完成的 CI：https://github.com/leoguo1314/balance-widget/actions/runs/37634365384
- **尚未完成华为 SDK 原生编译、HAP 签名、模拟器或真机运行。当前没有已验证可安装的 HAP。**
- Android 的 mihomo/VPN 等附加能力尚未移植，详见 `harmony/README.md`。不要把源码初版或逻辑测试成功描述成完整设备适配。

## 用户本机工具目录

| 工具 | 安装目录 |
| --- | --- |
| DevEco Studio | `D:\HarmonyosDevTools\DevEco Studio` |
| Command Line Tools | `D:\HarmonyosDevTools\command-line-tools` |
| DevEco Testing | `D:\HarmonyosDevTools\DevEco Testing` |

目录存在不等于其版本符合要求。请实际确认 SDK API 26、配套 Node.js 24、Hvigor、ohpm 和 Java。使用 Windows 原生 PowerShell 执行 `.ps1`/`.bat`；本任务的 Windows 工具路径不能直接当作 Linux 可执行路径使用。

## 执行步骤

1. 查看 `git status`、分支和远端，读取实际存在的 `AGENTS.md`，以及 `harmony/README.md`、`harmony/VALIDATION.md`。保护用户的本地修改。在 Fork 的 `harmonyos-7` 分支续做；若需要隔离修改，用独立工作目录或 worktree。无需重新 Fork 或新建同样的 PR。
2. 在仓库根目录检查工具，并记录实际版本：

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\harmony\tools\build-hap.ps1 -CheckOnly
   ```

   脚本默认使用上述 Studio 和 Command Line Tools 路径。若 SDK 位于其他位置，用 `-SdkHome '实际 SDK 根目录'` 指定。若现有套件不支持 API 26，确认并补齐官方配套 SDK；不要降低项目的目标 API 来伪造适配成功。许可或账号登录需要用户在本机完成时，报告具体阻塞点。
3. 执行真正的原生编译：

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\harmony\tools\build-hap.ps1
   ```

   根据 `harmony/build-logs/compile-*.txt` 和 DevEco 的诊断逐项修复 ArkTS/ArkUI、系统 Kit、配置、资源及打包错误，持续到 `assembleHap` 成功。检查本次输出的 HAP，记录文件路径与 SHA-256。不得以 Node/TypeScript 测试、PowerShell 检查或空文件替代 SDK 编译。
4. 初次脚本针对未签名源码。DevEco 自动生成的 JSON5、本地签名配置可能影响当前严格结构检查；如遇到这类问题，修正本地构建检查流程，保留 CI 对提交源码的安全约束，不把结构检查错误误当成 SDK 编译结果。后续调试签名和运行可使用 DevEco Studio。
5. 在本机已有合法调试签名、API 26 手机或模拟器可用时，完成签名、安装和启动验证。多个设备存在时确认目标设备。检查原生 UI、添加/编辑/删除账户、缓存与错误提示、历史持久化、服务卡片添加/翻页/刷新、通知授权；按 `harmony/VALIDATION.md` 记录实测结果。真实余额对照需用户在应用内输入凭证，没有凭证时如实保留接口验证未完成项。
6. 修复必要问题后执行相应回归检查，更新 `harmony/VALIDATION.md` 与构建说明。通过验证的源码提交并推送至 `harmonyos-7`，更新现有 PR。保留 Android 工程。不要自动合并 `main` 或宣称已发布商店版本。

## 交付与执行边界

- 交付真实构建产物的本机路径、SHA-256、工具/SDK 版本、实际构建命令、安装启动结果以及仍未完成的项目。
- 区分未签名 HAP、已签名 HAP、成功安装和运行验证；未签名产物只算中间构建结果。
- 签名证书、私钥、profile、密码、真实 API Key、Cookie 和原始私密响应留在本机，不提交 Git，不贴入 PR 或公共日志。日志目录已经从 Git 排除。
- 缺少签名或设备时，先完成仍可执行的编译和修复，再说明确切的剩余条件。不要只停在计划或重复业务测试成功。
- 本任务不要求多智能体并行，也不要求扩展尚未移植的 VPN 等能力；当前优先完成已实现原生版的可编译、可安装和可验证交付。

## 给本地 Codex 的启动指令

> 读取仓库根目录的 CODEX_HANDOFF.md，使用我的 Windows 本机鸿蒙工具链继续执行。自主完成真实 SDK 编译、错误修复、HAP 打包，并在本机签名与设备可用时完成安装运行验证。把源码和验证记录推送到现有 harmonyos-7 分支，交付真实产物路径与实测结果。
