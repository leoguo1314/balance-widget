# 本地调试签名与公开源码隔离

DevEco 的证书、私钥、Profile、密码及设备标识仅保存在本机。公开 `build-profile.json5` 必须是严格 JSON，`app.signingConfigs` 为空，产品无 `signingConfig` 引用。

使用本机配套 Node.js，在 `harmony` 目录运行：

```powershell
$node = 'D:\HarmonyosDevTools\command-line-tools\tool\node\node.exe'
& $node tools/local-signing.mjs save
```

`save` 将现有签名材料与产品引用保存到被 Git 忽略的 `build-logs/local-signing/signing.local.json`，保持当前 IDE 配置。工具会先确认整个私有目录被忽略且没有已跟踪文件。DevEco 只生成唯一 `default` 签名却漏填产品引用时，备份自动补上对应的 `default` 产品引用。没有签名材料时会拒绝覆盖旧备份。

提交公开源码前：

```powershell
& $node tools/local-signing.mjs public
git add build-profile.json5
& $node tools/local-signing.mjs check
```

`public` 会先备份当前已有签名，再清除签名材料和产品签名引用，写入严格 JSON。API、SDK、模块和其他构建设置保持当前配置。`check` 单独检查 Git 暂存区中的公开配置以及私有目录的忽略状态，不显示任何签名值；只有通过后才提交。

本地继续调试时：

```powershell
& $node tools/local-signing.mjs apply
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/build-hap.ps1 -LocalSigning
```

`apply` 将私有备份合入当前源码配置，保留当前 SDK/API 和其他构建改动，不操作 Git 暂存区。IDE 可以保留这份本地签名配置；提交其他文件时逐项暂存，并先运行 `check`。暂存 `build-profile.json5` 前再次运行 `public`。本地签名生效期间不要把该文件的 diff 或内容贴入公共日志，也不要使用 `git add -f` 添加私有目录。

工具不安装 Git 钩子或过滤器，不改 `.gitignore`，不自动暂存文件。JSON5 由本机官方 DevEco/Hvigor 自带的 `json5` 库解析；默认查找已安装路径，也可传 `--json5-module '官方安装目录\node_modules\json5\lib\index.js'`。解析失败不会显示配置片段。
