# Readlater V3 实现与验证记录

日期：2026-09-23。版本：`0.3.0+3`。分支：`feat/personal-insights-background`。
需求基线：[V3 需求](superpowers/specs/2026-09-22-readlater-v3.md)。

## 实现范围

- 默认「今日」与五页导航；每天至多五项稳定推荐、理由、重复内容来源、跳过、延后、反馈和处理。RSS 增加批量处理、隐藏已处理、暂停及退订。
- 待判断／阅读中／已处理／搁置与归档、回收站分离；已处理仍可参与知识使用，旧归档权限不改变。
- 主题背景、目标、限制、判断、未解决问题和 AI 对话条目；从正文／笔记导入并保留来源，未确认内容不进入推理。资料/context 范围可选，原文、笔记与批注变化标记相关结论过时并合并更新。
- 结构化阅读、字号与位置恢复、高亮、批注自动保存、PDF 页内预览／跳页／页笔记、正文版本保留。失效高亮保留摘录并提示；证据按真实原文验证，无法定位时明确标记。
- 检索覆盖原文、笔记、批注、分析和研究成果，返回命中片段并支持中文关键词；链接规范化、重复提示、抓取／补图／分析分离、带来源 Markdown 导出。
- 单缓存 FlutterEngine、单 AppController、单 SQLite 写入者；原生 `dataSync` 前台服务与有期限唤醒锁。提交保存并入队即返回，单队列优先用户任务，长文／PDF／研究分阶段保存，支持取消、中断恢复、配置核验和有限网络重试。
- 业务成果、任务、阶段进度及通知 outbox 同事务保存；任务 epoch/version 拒绝迟到结果。响应未保存时提示可能重复计费，研究恢复保留调用预算。
- 四类通知配置、结果跳转、多任务结果分组汇总、每日默认本地 20:00；JobScheduler 的 `digestOnly` 冷启动仅整理本地内容，不恢复网络任务或追踪。拒绝通知权限不阻止分析，过期汇总不补发。
- 数据 v3 兼容读取 v1/v2/v3，拒绝未知版本；备份不包含密钥、队列、checkpoint 或通知 outbox。恢复保留设备服务配置、暂停追踪，未知处理中请求转为手动重试。

## 本轮验证

工具链：Flutter 3.47.5 / Dart 3.13.4，Android SDK 36，JDK 21。没有新增依赖或更改依赖锁定版本。

| 检查 | 本轮结果 |
| --- | --- |
| `bash tool/check.sh full` | 通过：格式、静态分析无问题，13 个 Git 钩子场景，177 项单元／Widget 测试 |
| `bash tool/check.sh android` | 通过：再次运行全部 177 项测试并成功构建 Android arm64 release APK，依赖锁文件不变 |
| 独立核心／Flutter 代码复核 | APPROVE；证据定位、恢复指纹、预算、取消、digest 隔离和最终 UI 修复已复核 |
| 独立 Kotlin 代码复核 | APPROVE；前台服务、调度、权限、分享取消、通知跳转和结果聚合均已复核，汇总历史计数及失败文案问题已修复 |

新增行为测试涵盖：数据库／备份兼容、归档及来源撤销、取消后迟到结果、配置与任务版本变化、长文 checkpoint 重用、研究调用预算、笔记／批注并发变化、digest 零网络、通知拒绝与过期去重、证据真实定位、今日稳定性、PDF 页阅读和自动保存、背景导入来源、五页导航、小屏和 1.8 倍字体。受控夹具不代表真实模型质量。

构建产物：`build/app/outputs/flutter-apk/app-release.apk`（约 22.6 MB），
APK 元数据核验为 versionName `0.3.0`、versionCode `3`、minSdk `24`、targetSdk `36`。
SHA-256：`edaba01d99ed6dda7404a2ca99a2546a5179937ee5fd2198c598757e9cc7dced`。

## 尚未通过的设备验收

| 验收环境 | 当前状态 |
| --- | --- |
| Android API 24 | 未运行：没有连接可用设备／模拟器 |
| Android API 33 | 未运行：没有连接可用设备／模拟器 |
| Android API 35 | 未运行：没有连接可用设备／模拟器 |
| Android API 36 | AVD 可创建，模拟器启动失败；未运行 |
| 目标真机后台、锁屏、通知点击及厂商省电 | 未运行：`adb devices -l` 无连接设备 |
| 真实供应商与实际资料回答质量 | 未运行，未使用个人模型／搜索密钥 |
| iOS / macOS | 本轮不在交付范围，未构建验收 |

宿主机现有 Android 模拟器在启动和 `-version` 时均退出，报 `Incompatible processor. This Qt build requires the following features: neon`。尝试无窗口、软件渲染及关闭加速仍不能启动。不能以 APK 编译或平台 mock 代替设备通过证据。

已提供 `integration_test/background_flow_test.dart` 和更新后的 `integration_test/device_flow_test.dart`；专项流程见 [V3_DEVICE_TESTS.md](V3_DEVICE_TESTS.md)。必须在可用的专用设备上完成切后台／锁屏长文与 PDF、系统中断与取消、权限拒绝、冷启动通知定位、系统服务超时、时区变更和每日调度检查后，才能确认全部验收完成。

## 交付边界

保留功能分支，不合并 `main`、不推送或发布。APK 使用项目现有 debug 签名配置，供个人测试。用户原有未跟踪的 `docs/research/` 未纳入提交。
