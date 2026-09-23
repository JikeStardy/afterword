# 手机诊断报告接收

RSS 的 `HandshakeException: Connection terminated during handshake` 表示建立 HTTPS 安全连接时连接被终止，尚不能据此断定是 RSS XML 格式错误。应先通过手机上的诊断开关复现一次，再检查报告里的失败阶段、目标主机、重定向、耗时和异常类型。浏览器成功不代表应用的 TLS 栈、代理和网络路径相同；不要通过关闭证书验证修复此错误。

## 手机上记录和准备诊断包

进入「设置 → 开发者 → App 事件与诊断包」。默认 INFO 记录操作结果和错误；打开日志级别开关进入 DEBUG，记录详细步骤，然后回到 RSS 页面重现问题。DEBUG 只在当前进程内生效：切到后台再返回仍保持，进程重启恢复 INFO。此开关不会开启“记录模型完整交互”。

回到诊断页，按时间、级别等条件筛选并生成诊断包。「诊断包预览」显示报告 ID、事件/任务数量、大小、时间范围和上传目标。包不包含模型完整请求、响应或资料正文；「导出文件」和「上传到电脑」使用同一份本地快照。上传失败保留快照，可直接重试。接收工具将 ZIP 原样存到电脑工作目录，不解压。

「配置电脑接收端」填写完整地址和上传令牌后保存。端点保存在手机本地，令牌使用既有安全存储，重启后仍可读取；与临时 DEBUG 开关的生命周期不同。接收端不会补出手机未记录的 TLS 协商信息。

## 家庭局域网上传到电脑

手机与电脑连接同一可信家庭 Wi-Fi。需要 Node.js 22 或更新版本，无额外依赖。在仓库根目录打开终端，输入一个单独生成的随机令牌，输入不回显，也不将令牌字面量写进 shell 历史：

```zsh
read -rs 'READLATER_DIAGNOSTIC_TOKEN?诊断上传令牌: '
printf '\n'
export READLATER_DIAGNOSTIC_TOKEN
node tool/diagnostics_receiver.mjs --host 电脑局域网IP --port 18766 --output dist/diagnostics
```

将「电脑局域网IP」替换成电脑实际地址，如 `192.168.1.2`。手机完整接收地址相应填写 `http://192.168.1.2:18766/diagnostics`，令牌填写刚才输入的值。手机中的 localhost 指向手机自身，不能填电脑文件路径。Bash 的读取语法为 `read -rs -p '诊断上传令牌: ' READLATER_DIAGNOSTIC_TOKEN`。

电脑防火墙放行测试手机到 18766 端口；若仍无法连接，检查路由器是否开启设备隔离。HTTP 在内网明文传输，仅在可信家庭网络使用，不要配置公网端口转发。应用只接受明确的局域网/回环 IP 作为 HTTP 目标，其他目标要求 HTTPS。测试结束后停止接收服务、撤销临时防火墙规则并执行 `unset READLATER_DIAGNOSTIC_TOKEN`。

不指定 `--host` 时，接收端默认只监听 `127.0.0.1:18766`，默认目录为被 Git 忽略的 `dist/diagnostics/`。通过 USB 调试连接手机时，可运行默认命令 `node tool/diagnostics_receiver.mjs`，执行 `adb reverse tcp:18766 tcp:18766`，手机端点填 `http://127.0.0.1:18766/diagnostics`；多设备时为 adb 加 `-s 设备编号`。用完执行 `adb reverse --remove tcp:18766`。远程接收需另行部署受控 HTTPS 服务。

## 上传协议

- `POST /diagnostics`，不接受其他路径或查询字符串。
- `Authorization: Bearer <配置的令牌>`。
- `Content-Type: application/zip`；请求体是原始 ZIP 字节，不是 JSON 或 multipart；不接受内容压缩编码。
- `X-Report-Id` 是 16–80 个英文字母、数字、下划线或连字符。相同报告重试必须保留 ID 和原始字节。
- 单包最多 64 MiB，接收端同时限制声明长度及实际流量。请求头最多 8 KiB，总请求超时 120 秒，空闲连接超时 30 秒。

成功返回 HTTP 201 和 `{ "reportId": "…", "bytes": 123, "sha256": "…" }`。完全相同的重试返回 HTTP 200；同一 ID 对应不同内容返回 HTTP 409，不覆盖原报告。手机应核对 ID、字节数和 SHA-256 后再显示上传成功。401 表示令牌不匹配，413 表示包过大，415 表示格式不匹配；500 不代表报告已保存，重试仍需使用相同 ID 和字节。

接收端使用服务端生成的临时文件名、限制权限的文件和目录、同步写入及排他硬链接发布，避免并发重试覆盖。断连和失败会清理本次临时文件。进程被强制终止可能留下 `.incoming-*`；确认没有接收进程写入后再处理这些文件。服务不自动删除已接收报告，按需清理并避免磁盘耗尽。输出目录应只由可信本机用户管理，不应放在他人可修改的共享目录。工具只做传输存储，不保证 ZIP 合法或内容已脱敏；不要自动解压未知报告。

## 提供分析与验证

上传成功后，文件位于 `dist/diagnostics/<reportId>.zip`。告诉分析者 reportId，以及复现时间、订阅主机、Wi-Fi/蜂窝和是否启用代理；不要发送令牌。日志和报告不得加入 Git。需要离线分析时可以从手机直接导出同一报告。

```sh
node --check tool/diagnostics_receiver.mjs
node --test tool/diagnostics_receiver.test.mjs
```

行为测试覆盖鉴权、非法 ID、请求类型、声明/分块超限、真实字节与摘要、相同/不同内容的并发重试、断连清理和磁盘写入失败。它们验证接收协议，不证明真实 RSS 服务已恢复。

## 设备回归流程（仅专用测试设备）

启动 RSS 夹具与诊断接收端，将测试接收令牌设为设备测试约定值后，将 `18765`、`18766` 两个端口通过 `adb reverse` 映射到专用模拟器。运行 `integration_test/diagnostic_flow_test.dart` 的第一阶段，再结束 App 进程，第二阶段增加 `--dart-define=DIAGNOSTIC_RESTART_VERIFY=true`。两阶段均使用 `flutter drive --keep-app-running --driver=test_driver/device_screenshots.dart --target=integration_test/diagnostic_flow_test.dart -d <测试设备>`；不要省略 `--keep-app-running`，默认 drive 清理会卸载 App，不能用于验证重启保留。第二阶段检查 INFO、历史日志、诊断包和配置。不要在个人生产配置上运行设备夹具。
