# Readlater 实现与验证状态

日期：2026-09-21。本文只记录当前代码和日志能证明的事实，不把未覆盖的真实使用场景写成已完成。

## 当前结论

Android 首期主体功能已经实现。最新全量 Flutter 测试 77 项通过、静态分析零问题；最终设备集成测试和 arm64 release 构建通过。系统文件选择器手工导出、导入 ZIP 后已显示“资料库已恢复”。设备测试同时验证了独立空资料库恢复、重开及正文、分析摘要和附件字节一致。上述证据属于 Android 实现验证，不代表整个产品或长期研究效果已验收。

## 已实现范围

- Android Flutter App：资料、RSS、研究、设置四个主入口；Android 是第一期交付平台，代码结构保留后续跨端复用空间。
- 本地资料库：SQLite 状态快照、不可变本地资产、网页正文和图片、文字、图片、PDF、笔记、分析结果、研究运行、主题和偏好均保存在本地。
- 收藏入口：应用内收藏链接、添加文字、导入文件，以及 Android 系统分享文本、链接和文件。
- 网页解析：普通博客和微信公众号正文解析；提取失败时保留链接并显示失败状态。
- RSS：订阅、刷新、浏览条目；用户选中条目后才进入保存和分析流程。
- 模型配置：用户配置服务地址、文本模型、多模态模型、搜索服务和个人 Key；模型 Key 与搜索 Key 分开保存。
- 分析与知识积累：个性化总结、观点卡片、来源引用校验、历史资料关联、兴趣推断、明确反馈优先、主题综述。
- 外部研究：用户确认后执行多轮搜索和模型分析，遵守单次调用预算，保存来源、结论和未解决问题。
- 持续追踪：按主题授权，含频率、用量上限、暂停、延后补查、通知门槛和范围变化撤销授权。
- 备份恢复：ZIP 导出和恢复，包含原始资料和生成成果；恢复会保留当前设备模型配置，不从备份静默恢复外部服务地址或授权追踪。
- Android 原生能力：持久化分享收件箱、PDF 原生渲染批处理、通知、文件打开、对异常 content URI 和长文件名的处理。

## 最新验证证据

| 类别 | 证据 | 结果 |
| --- | --- | --- |
| 静态分析 | [final77-analyze.log](evidence/final77-analyze.log) | `flutter analyze`：No issues found。 |
| Flutter 测试 | [final77-tests.log](evidence/final77-tests.log) | 77 项测试通过。覆盖模型、存储、内容解析、模型协议、控制器、UI、备份恢复和原生 MethodChannel 契约。 |
| Android 设备集成 | [redirect-device.log](evidence/redirect-device.log) | 通过设备存储、HTTP 夹具、PDF、研究和自动主题流程；向独立空资料库恢复并重开后，正文、分析摘要和附件字节均与备份前一致。 |
| Release 构建 | [redirect-build.log](evidence/redirect-build.log) | 最终 arm64 release 构建成功，日志大小 21.2MB。版本 0.1.0，minSdk 24、targetSdk 36；release 配置使用 debug 签名，仅用于个人测试。 |
| 离线阅读观察 | [final-offline.xml](evidence/final-offline.xml)、[final-library.xml](evidence/final-library.xml) | 移除到夹具服务的连接并重启 release App 后，已保存网页正文与绿色示例图片均可查看；见 [离线截图](evidence/readlater-android-offline.png)。 |
| 手工 ZIP 备份恢复 | [restore-result.xml](evidence/restore-result.xml) | 经系统文件选择器导出 `Download/readlater-backup-20260921-032219.zip` 后导入，界面显示“资料库已恢复”；未据此宣称完成卸载重装验证。 |
| 真实网页解析抽查 | [live-capture-check.log](evidence/live-capture-check.log) | `https://paulgraham.com/read.html` 提取标题 `The Need to Read`、正文 2478 字符、图片 5 张。 |
| 真实微信受限页处理 | [wechat-live-green.log](evidence/wechat-live-green.log)、[wechat-block-page.log](evidence/wechat-block-page.log) | `mp.weixin.qq.com/s/5ptDDKoVxCLYKLCX9pBnkw` 返回验证页；解析器明确报“未获取到微信公众号正文”，没有把验证提示误保存为正文。 |
| 原生分享异常修复 | [native-share-red.log](evidence/native-share-red.log)、[native-share-green.log](evidence/native-share-green.log) | 旧版本遇到受权限保护的 content URI 会触发 `SecurityException`；修复后同类场景不再崩溃。 |
| 长 PDF 文件名修复 | [long-share-red.xml](evidence/long-share-red.xml)、[long-share-green.xml](evidence/long-share-green.xml) | 旧版本长文件名会丢失扩展名；修复后保留 `.pdf` 并展示为 PDF 项。 |
| 分享重建复核 | [recreation-red/result.txt](evidence/recreation-red/result.txt)、[density-red/result.txt](evidence/density-red/result.txt) | 进程重建、显示密度变化引发重建后各记录 `count=1`，此轮未复现重复分享；文件名中的 red 不代表复现失败，更不是高密度 PDF 压力测试。 |

日志随源码放在 `docs/evidence/`。测试源文件见 [test](../test/) 与 [integration_test](../integration_test/)。

## 已修复的主要审查问题

- 内联来源引用会被校验，模型编造不存在的来源不会被标记为完成分析或完成综述。
- 外部研究在每次远端调用前检查授权和预算，撤销授权后不会继续调用。
- 备份恢复会校验 schema、资产引用、路径和大小；恢复不会静默导入备份内的服务端点或追踪授权。
- 未配置模型时仍保存原始资料，并显示“待配置模型”，不把原文保存误报成分析完成。
- 微信验证页和其他空正文页面现在按提取失败处理；正常讨论登录或验证码主题的文章不会被误杀。
- Android 分享收件箱改为持久化处理，应用冷启动会主动恢复待处理分享。
- 原生打开文件、PDF 渲染和分享文件导入加入边界处理，降低 UI 线程阻塞、权限异常和过大文件风险。

## 验证缺口和限制

- 未使用用户真实模型 Key、真实搜索 Key 或具体商业供应商完成在线兼容性验证；当前端到端模型和搜索流程使用本地夹具服务。
- 已测试四条真实公众号链接，均未取得正文；其中首条已确认返回验证页。新增三条公开样本见 [wechat-public-samples.log](evidence/wechat-public-samples.log)。真实可访问文章的成功采集仍未验证。
- `paulgraham.com/read.html` 证明普通博客解析可行，但不能代表所有博客模板都能高质量提取。
- 备份恢复已有单元、widget 和系统文件选择器手工导出导入证据；空资料库恢复及重开校验已通过最终设备集成测试。卸载重装的手工流程未验证。
- 持续追踪的长期效果、主题综述是否真正推进研究，需要真实使用积累后复盘；需求文档已不再承诺固定使用周期。
- iPhone 和 Mac 没有构建、原生分享或平台能力验证；它们属于后续跨端复用和第二期范围。
- 视频仍是后续能力，当前未实现。

## 当前停止条件

最终设备测试和 arm64 APK 构建已通过。交付物包括源码归档、安装包和本地证据；具体校验见 DELIVERY.md。真实供应商兼容性、可访问微信公众号成功样本及长期研究效果保留为明确验证缺口，不作为已经完成的事实。

## 网页跳转修复

网页和订阅跳转后使用最终地址解析相对图片与条目链接；保留原订阅地址作为 RSS/Atom 条目身份的来源，避免刷新时改变既有条目身份。逐跳处理最多 5 次跳转，并拒绝非 HTTP(S) 目标。真实本地 HTTP 回归测试先复现错误，再验证正确路径和稳定身份；证据：[原始失败](evidence/redirect-red.log)、[身份回归失败](evidence/redirect-identity-red.log)、[修复后通过](evidence/redirect-green.log)。全量 77 项测试、设备流程和 release 构建也已通过。
