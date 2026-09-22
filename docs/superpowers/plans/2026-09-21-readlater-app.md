# Readlater 跨端 App Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans for the main integration lane. Native subagents own independent UI and Android slices; all work uses test-first verification and a final independent review.

**Goal:** 实现需求文档中的 Android 首期完整研究 App，保留 iOS/macOS 的 Dart 业务与 UI 复用。

**Architecture:** Flutter Material 3 应用，Dart 领域对象、SQLite 本地资料库和文件资产、设备端 HTTP 内容提取与 RSS、OpenAI-compatible Chat Completions 适配器、独立搜索适配器。Android Kotlin 仅负责分享接收、PDF 光栅化和通知。密钥与备份分离。所有资料和研究成果本地保存。

**Tech Stack:** Flutter 3.47.5 / Dart 3.13.4；sqlite3、http、html、xml、path_provider、file_picker、flutter_secure_storage、archive。Android JDK 21。选择 Flutter 的依据：https://docs.flutter.dev/platform-integration 。

**Spec:** ../specs/2026-09-21-readlater-requirements.md

## Global Constraints

- Android 优先；Mac 第二期；iOS 时期待定，禁止以 Web 原型替代 Android 交付。
- RSS 未选中不分析；库内分析不调用搜索；外部研究有独立确认或主题授权。
- 同时实现多轮研究与持续追踪；前台定期检查与恢复补查满足可延后执行要求。
- 不联网托管资料，不配置产品账号，不实现视频或同步。
- 模型配置使用用户 Key，搜索服务单独配置；没有 Key 时保存仍可使用，显示待配置状态而不伪造分析。
- 当前开发沙箱在 work/readlater-app，验证后的源码及文档同步至用户 readlater 项目；不得覆盖原始需求文档。

## Review Focus

- 微信正文空提取或图片下载失败时不得表示完整离线保存。
- 模型返回的来源引用必须限于实际输入或已检索来源，不能把未知引用变为证据。
- RSS 刷新不得调用模型；追踪未授权、暂停或预算用尽时不得搜索。
- 备份禁止泄漏模型或搜索密钥，恢复验证路径以避免越界写入。
- 进程重启与中断后仍可读取原文；任务状态不能永久卡在处理中。

## 接口与文件责任

- `lib/core/models.dart`：LibraryItem、Asset、Analysis、Topic、Feed、FeedEntry、ResearchRun、AppSettings、AppData；JSON往返。
- `lib/core/store.dart`：本地SQLite加载与事务保存、资产写入、ZIP导入导出；数据库由单一AppController写入。
- `lib/services/content_service.dart`：网页正文/图片抓取、RSS/Atom解析；无模型调用。
- `lib/services/intelligence_service.dart`：模型/搜索HTTP适配，卡片与综述结构校验，调用计数预算。
- `lib/core/app_controller.dart`：ChangeNotifier控制器，保存/分析/RSS/偏好/研究/追踪/备份用例；依赖可注入。
- `lib/platform/native_bridge.dart`、`android/`：Android系统分享、PDF分页图像和通知；不修改领域数据。
- `lib/ui/`、`lib/main.dart`：资料库、阅读、RSS、主题/追踪、偏好/设置、研究授权界面。

## Task 1: 本地数据与恢复

- [x] 测试已实现并通过（历史 RED 顺序不另作追认）：模型往返、SQLite重启读取、备份包含原件不含Key、恶意ZIP路径拒绝测试。
- [x] GREEN：实现模型、SQLite表记录JSON与事务快照、本地资产、版本化ZIP恢复。
- [x] 验证：`flutter test test/store_test.dart`，检查恢复失败不修改现有资料。

## Task 2: 内容接入与RSS

- [x] 测试已实现并通过（历史 RED 顺序不另作追认）：微信公众号`#js_content`、博客article、空页面、相对图片、RSS/Atom夹具测试。
- [x] GREEN：HTTP取正文、删除脚本等非正文节点、离线资产、RSS状态不触发模型、失败保留URL。
- [x] 验证：`flutter test test/content_test.dart`；系统分享和PDF进入Task 4。

## Task 3: 分析、主题、研究与授权

- [x] 测试已实现并通过（历史 RED 顺序不另作追认）：以本地HTTP夹具验证模型JSON、未知来源过滤、未授权不搜索、预算耗尽、暂停和恢复补查。
- [x] GREEN：OpenAI-compatible文本/图像输入、PDF分页图像；生成卡片、关联、兴趣与综述。
- [x] GREEN：Tavily search接口（自有Key）返回证据，Agent按目标迭代，限定调用次数，保存部分与最终结果。
- [x] GREEN：明确反馈优先；重点主题自动更新；追踪前检查范围、授权、时间和上限，仅重要变化通知。
- [x] 验证：`flutter test test/intelligence_test.dart test/controller_test.dart`。

## Task 4: Android入口与移动界面

- [x] 测试已实现并通过（历史 RED 顺序不另作追认）：桥接调用和窄屏资料保存/阅读/RSS选择/授权/设置交互测试。
- [x] GREEN：持久分享收件箱、PDF分页、通知权限；Material 3温暖纸张色系，四个主入口：资料、RSS、研究、设置。
- [x] GREEN：清晰空状态和失败状态、来源回看、离线图片、笔记、文件导入、备份恢复、Key输入、偏好编辑、研究记录与追踪控制。
- [x] 验证：`flutter test`，`flutter analyze`，`flutter build apk --debug`。

## Task 5: 集成与验收

- [x] 模拟器安装启动、系统分享、文字资料从界面保存后重启读取、RSS夹具挑选、图片/PDF、独立空库备份恢复；笔记字段持久化由控制器测试验证。
- [x] 使用本地HTTP服务验证真实网络协议和Agent全过程，明确区别受控夹具与用户真实API联调。
- [x] 独立代码/安全审查；修复发现后重新运行有影响的测试。
- [x] 将源码、锁文件、实现文档和APK同步到项目；交付APK副本及验收记录。文件哈希与源码归档内容逐项核对。
- [x] 按AC-01至AC-25逐项记录证据和仍需用户长期实际使用验证的部分。

## 实现默认值

文本模型兼容Chat Completions `/chat/completions`，模型名由用户填写；图片通过image_url data URL输入；PDF在Android渲染分页图像后分批分析。外部搜索独立使用Tavily，默认每次最多6次网络工具/模型调用，持续追踪默认24小时，可在界面调整；这些是实现默认值，不改写用户需求。默认只在前台运行与恢复时补查，不承诺手机关闭时后台常驻。研究范围变化使旧授权失效。备份不包含API Key。

## Progress

- 环境：Flutter、JDK、Android SDK 已就绪；77 项测试与最终 Android 设备集成测试通过，release APK 已构建。
- 文档阶段不初始化Git的约束针对前一交付；本轮同样无需建立Git仓库来实现功能。
- 由于尚无Git历史，使用文件级测试证据和本进度记录替代技能中的commit/worktree账本脚本。

- 最终设备验证：自动主题生成未增加外部搜索；独立空资料库恢复后重开，正文、分析摘要和图片字节一致；release 重启后离线正文与图片可读。详见 docs/ACCEPTANCE.md。
