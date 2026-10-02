# Readlater：长篇分析 UI 与 React Native 迁移评估

调研日期：2026-09-23。性质：只读代码盘点、第一方资料调研与方案建议；没有实施迁移、安装依赖或验证 RN 原型。文档保存在视觉分支的独立 worktree。

## 结论

1. 当前观点页的主要问题是缺少信息优先级和逐层展开；仅调颜色、字号、留白无法解决长篇模型输出。上一轮短摘要截图不代表真实长文体验通过。
2. React Native 能实现接收分享、通知和受系统约束的后台处理；它不会让应用获得无限后台常驻能力。平台规则同时约束 Flutter、RN 与原生应用。
3. 对这个项目，整体迁移成本中高：UI、Dart 业务逻辑与测试需重写，Kotlin 系统逻辑可部分保留但 FlutterEngine/MethodChannel 运行时不能直接沿用。若目的只是改善阅读体验，优先在现有实现改信息结构；若有长期 TypeScript/React 生态目标，先验证原生能力再决定迁移。

## 代码依据与范围

检查的是主工作区 `feat/personal-insights-background` 的正在开发快照，含未提交的 V3 工作；不把它当成已验收版本。此前视觉 worktree 的 `22b8c7c` 仍基于 V2，两者范围不同。以下规模是本次读取时的近似盘点，不是稳定主线承诺。

| 范围 | 文件与行数（含空行） | 迁移含义 |
| --- | --- | --- |
| Dart 实现 | 24 文件，约 11,655 行 | 需重新实现为 TypeScript 或原生模块 |
| 其中 UI | 12 文件，约 5,071 行 | 页面、导航、交互状态与可访问性重做 |
| Kotlin | 6 文件，约 1,048 行 | 系统逻辑可提取，Flutter 运行时集成需改 |
| 单元/Widget 测试 | 18 文件，约 5,353 行 | 测试意图与夹具可复用，测试代码多数重写 |

本地证据：

- `/Users/tomato/Documents/code/readlater/lib/ui/item_detail.dart`：`_AnalysisSection` 展开完整 summary、结构化观点、旧版 insights、connections、questions；`_StructuredInsightTile` 又展开 change、impact、unknowns 和全部 evidence。
- `/Users/tomato/Documents/code/readlater/lib/services/intelligence_service.dart`：模型同时返回兼容用 insights 和 structuredInsights；不能默认把两套内容都展示给用户。
- `/Users/tomato/Documents/code/readlater/lib/core/store.dart`：SQLite 内以 app_state/runtime_state JSON 快照持久化，迁移必须维护事务和数据版本。
- `/Users/tomato/Documents/code/readlater/android/app/src/main/kotlin/app/readlater/readlater/ReadlaterRuntime.kt`：直接持有 FlutterEngine 与 MethodChannel，负责分享队列、通知、PDF 渲染与后台入口。
- `/Users/tomato/Documents/code/readlater/docs/superpowers/specs/2026-09-22-readlater-v3.md`：正在实现的 checkpoint、取消、调用预算、来源状态、通知 outbox 与后台恢复都应计入迁移验收。

## 长篇观点页应怎样改

以下是设计提案，不是已完成的改动。

| 层级 | 默认展示 | 展开后的内容 |
| --- | --- | --- |
| 核心结论 | 一小段可扫读的结论，目标约 80–120 字 | 完整总结，保留原始长回答 |
| 关键发现 | 先展示 3–5 条，每条用结论句作标题 | 全部观点；每条的解释、适用条件和个人影响 |
| 证据与局限 | 来源数量、存在重要限制/待核实的提示 | 引文、段落/PDF 页定位、反证与未知 |
| 与我的关系 | 新增/重复/冲突等有依据的关系摘要 | 与旧资料和个人笔记的完整对照 |
| 下一步 | 少量可选的研究问题 | 全部建议，外部研究仍逐次确认 |

实施要求：

- 结构化观点有效时，以它作为主要呈现；旧 insights 作为历史数据回退，不重复铺开。
- 用真正的语义字段承载标题、结论、依据与限制。Markdown 能改善排版，但不能自己判断哪段最重要；不要用任意截断、正则拆句冒充语义摘要。
- 对旧长文本提供完整展开，不自动重跑模型、不静默丢内容。摘要过长时折叠展示，不把视觉限长变成数据截断。
- 每张观点只设一个主要阅读焦点，证据按需展开；重要反例和不确定性需有首层提示，避免折叠后把不确定结论误呈现为确定事实。
- 新验收使用 5,000–10,000 字分析、10 条以上观点、长引文、缺少结构化字段等夹具，覆盖 320/390/430 宽、1.8 倍字、展开状态保留与来源跳转。短文截图不能替代它。

## React Native 原生能力

### 接收其他软件分享

Android 的原生入口是 ACTION_SEND/ACTION_SEND_MULTIPLE 与 MIME 声明。RN 可以通过原生模块接入；关键是冷/热启动、去重、content URI 临时授权和附件落盘，不是仅让应用出现在分享菜单。分享并不意味着能获得原应用受登录保护的全文。[Android 接收分享](https://developer.android.com/training/sharing/receive)

最新 `expo-sharing` 已支持接收，含 Android intent filter 与 iOS Share Extension/App Group 配置，但文档仍标 experimental；其 iOS 拉起主应用方式不受 Apple 官方支持，不能未经实测就作为可靠生产路径。Android 可先做 PoC；核心收件也可沿用现有 Kotlin 队列后重新封装。iOS 应评估在扩展内保存到 App Group 的方案。[Expo Sharing](https://docs.expo.dev/versions/latest/sdk/sharing/)

### 主动通知

`expo-notifications` 提供本地通知、计划通知、远程推送令牌及点击响应。分析完成后发通知和预先安排提醒，不要求自建推送服务器；若希望手机未执行任务时仍收到服务端新结果，则需要后端加 FCM/APNs 等推送链路。通知调度不等于在该时刻执行一轮 LLM 分析。[Expo Notifications](https://docs.expo.dev/versions/latest/sdk/notifications/)

权限拒绝、关闭通道、冷启动点击定位和去重都要验收。Android 13+ 通知权限与 FGS 启动条件需分别处理，不能把通知权限被拒绝等同于禁止所有前台服务。[Android 通知权限](https://developer.android.com/develop/ui/views/notifications/notification-permission)

Notifee 官方仓库已于 2026-04-07 归档并建议转向 expo-notifications；本次不将它列作新项目默认依赖。[Notifee 维护状态](https://github.com/invertase/notifee)

### 后台处理

| 需求 | 建议机制 | 不能承诺的部分 |
| --- | --- | --- |
| 用户开始分析后切后台/锁屏继续 | Android 原生前台服务，显示进度和取消入口 | 无限执行、永不被系统回收 |
| 周期检查、本地每日摘要 | WorkManager/JobScheduler，或 expo-background-task | 精确准点和一直运行 |
| 系统中断后的恢复 | 持久队列、checkpoint、有限重试与幂等 | 未落盘的内存进度、强停后自行无限重启 |
| 真正全天候外部监测 | 服务端任务加推送 | 沿用“所有任务只在手机本地运行”的架构假设 |

Android 12+ 限制从后台启动前台服务；Android 14+ 要匹配服务类型和权限。目标 Android 15+ 的 dataSync FGS，在应用后台时受每 24 小时累计 6 小时限额约束，同一类型在应用内共享额度，用户回前台可重置；到时必须停止并保留可恢复状态。这不是每个任务都保证获得 6 小时执行权。[后台启动限制](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start)、[服务类型](https://developer.android.com/about/versions/14/changes/fgs-types-required)、[超时规则](https://developer.android.com/develop/background-work/services/fgs/timeout)

Expo BackgroundTask 使用 Android WorkManager 与 iOS BGTaskScheduler；Android 周期下限为 15 分钟，实际调度由系统决定。它适合可延迟工作，不是持续运行 LLM 请求的可靠计时器。[Expo BackgroundTask](https://docs.expo.dev/versions/latest/sdk/background-task/)

“设置→强制停止”与系统回收进程、从最近任务划掉不同，不能承诺强停后自行恢复。Android 15 的 stopped state 需用户交互解除。RN Headless JS 提供的是 Android 后台 JS 执行入口，仍需原生服务和超时管理，不是独立的调度器或保活许可。[强停语义](https://developer.android.com/about/versions/15/behavior-changes-all#stopped-state)、[Headless JS](https://reactnative.dev/docs/headless-js-android)

### iOS 的额外边界

iOS 使用标准 Share Extension 接收内容，建议先写入 App Group 共享容器，再由主应用消费；不要让分享扩展等待整轮 LLM 分析。[Apple Share Extension](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html)

iOS 26 的 BGContinuedProcessingTask 改善了“用户前台发起任务，切后台后继续”的能力，可带 Live Activity 进度与取消。它仍受资源、排队、拒绝和终止约束，不是无人触发的无限驻留；RN 需要相应原生封装，不能因为 expo-background-task 使用 BGTaskScheduler 就假定已支持此新机制。旧版 iOS 还要按已有短刷新/处理机制设计恢复路径。[Apple WWDC25](https://developer.apple.com/videos/play/wwdc2025/227/)、[长任务](https://developer.apple.com/documentation/BackgroundTasks/performing-long-running-tasks-on-ios-and-ipados)

## 推荐的 RN 验证技术栈

- Expo development build + TypeScript + 本地原生模块；需要自定义原生入口，不能只在 Expo Go 里看页面就判定成功。可本机编译，不必购买 EAS 云构建。[development build](https://docs.expo.dev/develop/development-builds/introduction/)、[自定义原生代码](https://docs.expo.dev/workflow/customizing/)
- 根据本次官方 SDK 表，SDK 57 对应 RN 0.86；按 Expo 支持矩阵锁版本。Android 7/API24 起，与当前要求吻合；iOS 16.4 起，若需更老设备须另行决策。[SDK 支持矩阵](https://docs.expo.dev/versions/latest/)
- UI 使用 RN 原生组件及一套自定义阅读设计；不要预期 React 网页组件/CSS 原样搬来。RN 官方也推荐通过框架起步。[RN 入门](https://reactnative.dev/docs/environment-setup)、[核心组件](https://reactnative.dev/docs/intro-react-native-components)
- SQLite、文件、安全存储优先评估 expo-sqlite / expo-file-system / expo-secure-store；先保留业务格式和事务语义。[SQLite](https://docs.expo.dev/versions/latest/sdk/sqlite/)、[文件](https://docs.expo.dev/versions/latest/sdk/filesystem/)、[安全存储](https://docs.expo.dev/versions/latest/sdk/securestore/)
- 分享先试官方实验能力或自有 Kotlin 收件；通知用 expo-notifications；后台持续执行和 PDF 页面转图片保留 Kotlin 系统实现，再通过 Expo Modules/TurboModule 暴露。PDF 查看组件不等于供多模态分析使用的页面渲染器。[RN 原生接口](https://reactnative.dev/docs/native-platform)、[Expo Modules](https://docs.expo.dev/modules/overview/)
- 若用 prebuild/CNG，自定义配置放进 config plugin、本地模块，避免手改生成文件后被重新生成覆盖；也可以显式维护原生工程，接受相应升级责任。[CNG](https://docs.expo.dev/workflow/continuous-native-generation/)

## 成本判断

可复用：产品规则、提示词与 JSON 契约、SQL/备份格式、受控服务夹具、测试用例意图，及部分 Kotlin 文件操作/PDF/通知逻辑。

必须改写或重验：全部 Flutter Widgets/导航/状态、Dart 控制器与服务、JS/原生运行时边界、后台队列单一写入者、取消和迟到结果隔离、日志脱敏、数据升级与自动化测试。RN 的后台 JS 入口不是现有 FlutterEngine 的替代名词，必须重新设计其启动、退出和任务所有权。

已有 SQLite 文件可保留格式，但应用数据目录、应用标识/签名与驱动生命周期需迁移验证；安全存储即使都使用系统 Keystore/Keychain，也不能假定两个框架的数据命名空间和封装格式相同。可用一次性兼容读取或要求重新配置密钥，不能静默丢失。

以下仅为工程量估计，假设一名熟悉 RN/Android 的开发者、Android 优先、功能范围冻结；不是已实测排期，也不是按行数线性换算。AI 可加速编码，但不能省去真机和数据兼容验证。

| 交付范围 | 估计 |
| --- | --- |
| Flutter 内完善长篇观点结构、折叠与相关回归 | 2–5 人日 |
| RN 原生能力 PoC（分享→落盘→后台模拟分析→通知定位） | 3–7 人日 |
| RN Android 达到当前计划功能与可靠性，含迁移/回归 | 20–40 人日，约单人 4–8 周 |

这些范围不是简单相加的承诺；完整迁移含能力验证但若 PoC 揭示库或设备问题则应重新估计。新增 iOS 正式交付单独估计，不能按“跨平台”视为免费获得。

## 建议决策及最小验收

先把长文观点的信息结构确定下来。若长期确实想统一到 React/TypeScript，再做独立 RN PoC；不建议只因当前排版差而全量重写。RN 的收益主要在技术生态和团队熟悉度，不能替代内容设计，也不会解锁平台禁止的常驻能力。

PoC 只验证关键链路：

1. 真机 Chrome/微信/文件管理器分享 URL、文字、多图、PDF；冷启动、热启动均落盘，临时 URI 失效后附件仍可读。
2. 从用户交互开始长任务，切后台/锁屏、断网、取消和系统结束后有明确状态；恢复不丢 checkpoint、不重复计费预算、不写回过期结果。
3. 分析结束通知、拒绝权限、点击冷启动定位；计划提醒与后台内容生成分别验收。
4. 使用副本导入现有数据/备份，核对归档、回收站、来源链和附件，避免以空库演示代替数据迁移。
5. Android 14/15/16 与至少一台实际使用的厂商设备；开发构建与 release 构建都验证生命周期。iOS 若纳入，再单列 Share Extension 和后台继续任务实机验收。

本轮未运行上述 PoC，没有据文档声称实际供应商、设备或 RN 库组合已经通过。
