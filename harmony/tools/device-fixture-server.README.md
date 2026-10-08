# 真机合成余额夹具

仅供开发验证，版本 `1.0.0`，不调用外部服务、不记录请求头、Authorization 或请求体。只能绑定回环地址，默认 `127.0.0.1:41727`。测试账户只填写虚构 Key `synthetic-device-validation`；服务忽略凭证，可通过 HTTP 状态制造错误。设备到本机回环的转发由验证操作者另外配置。

在 `harmony` 目录启动（Ctrl+C 停止）：

```powershell
& 'D:\HarmonyosDevTools\DevEco Studio\tools\node\node.exe' .\tools\device-fixture-server.mjs
```

查看版本、服务状态和默认余额：

```powershell
node .\tools\device-fixture-server.mjs --version
Invoke-RestMethod http://127.0.0.1:41727/status
Invoke-RestMethod http://127.0.0.1:41727/balance
```

本机控制余额、错误状态和延迟：

```powershell
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:41727/control -ContentType 'application/json' -Body '{"balance":93.25,"httpStatus":200,"delayMs":0}'
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:41727/control -ContentType 'application/json' -Body '{"httpStatus":503}'
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:41727/control -ContentType 'application/json' -Body '{"httpStatus":200,"delayMs":30000}'
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:41727/control -ContentType 'application/json' -Body '{"balance":100,"httpStatus":200,"delayMs":0}'
```

`GET /balance` 的 JSON 为 `{"balance":100}`，账户的余额 JSON 路径为 `balance`。控制只影响随后进入的余额请求；已进入的请求使用原配置。状态提供余额请求总数，便于确认应用确实发起网络访问。失败状态依然返回合成余额 JSON，客户端应按照 HTTP 状态判断错误。

`balance` 接受有限数值；`httpStatus` 接受 200–599，但排除不能携带正常 JSON 响应体的 204、205、304；`delayMs` 接受 0–60000 整数。控制为部分更新，未知字段、无效 JSON、非 JSON 内容类型及超过 2048 字节的请求均被拒绝。绑定失败直接以非零退出，不自动换端口。

验证服务行为：

```powershell
& 'D:\HarmonyosDevTools\DevEco Studio\tools\node\node.exe' --test .\tools\device-fixture-server.test.mjs
```

这些测试只验证本机 HTTP 夹具，不能证明鸿蒙应用或真机验证成功。缓存、历史、超时与错误显示必须通过应用另行观察和记录。
