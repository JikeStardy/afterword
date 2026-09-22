# Git 与开发规范验收记录（2026-09-22）

## 交付状态

- 仅本地 Git，没有远端或云端 CI；现有 Git 身份未修改。
- main / 带说明的 v0.2.0 均指向首次已交付版本基线 67e89a3。
- 规范保留在 chore/git-development-standards，尚未合并 main。
- 2ad7e5a 独立整理两处测试格式；7c300aa 添加规范与工具；028ded1 修复审查与干净克隆发现的问题。最后的文档记录提交见 git log。
- 业务源码、公共接口、数据结构、依赖版本和应用版本没有改变。
- 本仓库 core.hooksPath=.githooks；新克隆需自行运行 bash tool/setup-dev.sh。

## 验证结果

| 验证 | 结果 |
| --- | --- |
| 首次暂存审核 | 167 文件；锁文件和 Gradle Wrapper 纳入；产物、私有配置和运行数据排除；没有检测到私钥或长 live-key 特征 |
| 基线与格式整理 | 两次全量测试各 133 项通过 |
| 最终 bash tool/check.sh full | 格式零改动、静态分析无问题、13 个临时 Git 场景通过、133 项 Flutter 测试通过 |
| 正常功能提交 | 使用已安装的实际 pre-commit，fast 通过后提交成功 |
| 钩子行为 | 文档无需 SDK；格式／分析错误、禁止文件、空白错误、部分暂存和未跟踪源码均拦截；重复安装幂等，已有钩子不被遮蔽 |
| 审查修复 | 源码移入 docs 仍检查源码；测试不继承外层 Git 配置；两项均有失败后通过的回归 |
| 干净本地克隆 | 从仓库克隆，移除克隆自动建立的本地 origin；重新解析锁定依赖、安装钩子，无原项目构建目录拷贝 |
| 克隆 bash tool/check.sh android | 全部检查通过，Android arm64 release 构建成功，21.7 MB；构建后 Git 工作区干净 |
| 真实 SDK 拒绝路径 | 临时克隆实际提交格式错误及未定义标识符，各自被拒绝；HEAD、暂存树、状态和测试源文件内容均保持不变 |
| 锁文件 | 构建前后 SHA-256 一致：501009effc9ac094b6b31162e6d086c61cc8cda7798888f34c887c3c2ab9c21a |

工具链：Flutter 3.47.5 / Dart 3.13.4，JDK 21，Android SDK 36；测试未使用真实模型供应商凭据。此次仅修改协作工具、规范和测试格式，没有重新执行设备 UI 流程；之前版本的设备验证仍是其历史证据。

## 干净构建发现与处理

1. sqlite3 3.6.0 原生库下载遇到 Dart TLS 握手失败。使用保持证书验证的 HTTPS curl 从该依赖的官方 GitHub release 重新下载，按依赖自身钩子固定 SHA-256 校验后写入本次克隆的生成缓存；未复制旧项目缓存、未关闭 TLS、未更改依赖。
   - 文件：libsqlite3.arm64.android.so。
   - SHA-256：0c2d3bfc8c87abceb21ed72a4bb49964121c5fe1a8ef3848d83ba907d01b6161。
   - 原始地址：https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.6.0/libsqlite3.arm64.android.so
2. 当前 Flutter 的 --no-pub 会跳过 release 插件注册文件重建，测试后直接构建会错误引用 integration_test。android 检查改用标准 release 流程，并核对 pubspec.lock；真实克隆已验证成功。fast / full 保持使用已有依赖。

## 工作区与证据

本次按用户明确的目录与功能分支约定原地执行，没有建立额外 worktree；每次提交均审阅暂存内容。执行期间出现的 docs/research/wechat-webview-feasibility.md 属于任务外未跟踪文档，保留原样，不纳入本次提交，因此不能把整个目录宣称为完全干净。

本次原始日志保存在忽略目录 .superpowers/verification/git-development-standards/，包括基线、最终完整检查、审查问题的失败复现、真实 SDK 拒绝测试和克隆 Android 构建记录。它们不随 Git 克隆分发；本记录保留命令与结果。新环境可按 CONTRIBUTING 重新验证。
