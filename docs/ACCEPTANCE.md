# Readlater 验收映射

本文按需求文档中的 AC-01 至 AC-25 记录 Android 首期实现、验证证据和剩余限制。表内“已验证”只表示列出的具体路径已有证据，不表示整个产品、真实供应商或长期使用效果已验收。状态含义：

- **已验证**：已有自动测试、设备集成测试、构建日志或手工观察日志支持。
- **部分验证**：核心路径有证据，但真实样本、手工流程或长期使用仍有限制。
- **未验证**：当前代码可能有相关能力，但没有足够证据支撑验收结论。

## 验收总览

| 场景 | 状态 | 当前证据 | 限制 |
| --- | --- | --- | --- |
| AC-01 微信文章收藏 | 部分验证 | [content_test.dart](../test/content_test.dart) 覆盖 `#js_content` 与懒加载图片解析；[wechat-live-green.log](evidence/wechat-live-green.log) 证明真实微信验证页会明确失败而不是误保存。 | 尚缺真实可访问微信公众号文章的成功样本；字段覆盖率不能只由夹具证明。 |
| AC-02 普通博客收藏 | 已验证 | [content_test.dart](../test/content_test.dart) 覆盖普通博客解析；[live-capture-check.log](evidence/live-capture-check.log) 从 `paulgraham.com/read.html` 提取 2478 字符和 5 张图片；[final-offline.xml](evidence/final-offline.xml) 显示离线正文可读。 | 不保证所有博客模板都能同等提取。 |
| AC-03 提取失败 | 已验证 | [library_status_test.dart](../test/library_status_test.dart) 覆盖失败标签；[wechat-live-green.log](evidence/wechat-live-green.log) 记录受限微信页返回明确 `FormatException`；代码保留链接和失败状态。 | 失败原因文案仍是通用提示，未细分所有网站反爬或登录场景。 |
| AC-04 文字记录 | 已验证 | [controller_test.dart](../test/controller_test.dart) 的 `unconfigured model never prevents saving original notes` 验证文字、笔记和重开存储；[ui_test.dart](../test/ui_test.dart) 验证既有资料详情展示及冷启动分享文字恢复。 | 未做大规模文本输入性能验证。 |
| AC-05 图片分析 | 已验证 | [intelligence_test.dart](../test/intelligence_test.dart) 覆盖多模态分析使用 vision model 和 image blocks；[device_flow_test.dart](../integration_test/device_flow_test.dart) 验证 Android 图片文件导入并完成夹具模型分析。 | 多模态真实供应商兼容性未验证。 |
| AC-06 PDF 分析 | 已验证 | [native_bridge_test.dart](../test/native_bridge_test.dart) 覆盖 PDF 批量渲染；[device_flow_test.dart](../integration_test/device_flow_test.dart) 覆盖真实 Android PDF 流程；[long-share-green.xml](evidence/long-share-green.xml) 证明长 PDF 文件名保留扩展名。 | 超复杂或扫描型 PDF 的真实识别质量依赖模型供应商，未验证。 |
| AC-07 RSS 未选中 | 已验证 | [ui_test.dart](../test/ui_test.dart) 的 `rss entries stay browsable until user selects them` 覆盖未选中只浏览；[content_test.dart](../test/content_test.dart) 覆盖 RSS/Atom 解析。 | 未做大量订阅源压力测试。 |
| AC-08 RSS 选中 | 已验证 | [controller_test.dart](../test/controller_test.dart) 的 `RSS remains unanalysed until selected, then joins regular analysis` 验证选中后保存、分析和重复选中去重；[device_flow_test.dart](../integration_test/device_flow_test.dart) 验证设备上添加订阅不触发分析、选中后入库。[ui_test.dart](../test/ui_test.dart) 只验证未分析条目及按钮展示。 | 真实订阅源质量和抓取频率未做长期验证。 |
| AC-09 默认成果 | 已验证 | [intelligence_test.dart](../test/intelligence_test.dart) 覆盖个性化分析、观点卡片和来源引用；[ui_test.dart](../test/ui_test.dart) 覆盖详情分析和研究建议边界。 | 真实模型输出质量未验证；来源约束由测试夹具验证。 |
| AC-10 关联既有资料 | 已验证 | [controller_test.dart](../test/controller_test.dart) 覆盖研究证据参与后续分析和主题综述；[intelligence_test.dart](../test/intelligence_test.dart) 验证已有资料作为相关来源进入分析。 | 真实语义关联质量取决于模型表现和资料规模。 |
| AC-11 自由收藏与主题 | 已验证 | [ui_test.dart](../test/ui_test.dart) 覆盖资料与研究入口；[controller_test.dart](../test/controller_test.dart) 覆盖添加主题、主题综述和资料独立保存。 | 主题信息架构仍是首版交互，没有真实长期使用反馈。 |
| AC-12 自主主题更新 | 已验证 | [controller_test.dart](../test/controller_test.dart) 覆盖自动主题和综述、综合状态恢复、失败可重试；[intelligence_test.dart](../test/intelligence_test.dart) 覆盖综述引用校验；[device_flow_test.dart](../integration_test/device_flow_test.dart) 断言自动主题已就绪、综述与来源完整且未额外搜索。 | 自动发现主题的质量未经过真实资料库长期验证。 |
| AC-13 偏好可纠正 | 已验证 | [models_test.dart](../test/models_test.dart) 覆盖明确兴趣和推断兴趣分离；[controller_test.dart](../test/controller_test.dart) 覆盖移除推断兴趣后不会在下一轮自动分析中重新出现；[backup_export_test.dart](../test/backup_export_test.dart) 覆盖恢复后偏好字段刷新。 | UI 层偏好编辑只覆盖核心字段，复杂偏好管理仍可继续打磨。 |
| AC-14 兴趣与认同 | 已验证 | [intelligence_test.dart](../test/intelligence_test.dart) 覆盖 explicit/inferred preferences 分开传递；[models_test.dart](../test/models_test.dart) 覆盖 attention 与 explicit interests 分离。 | 当前主要通过数据模型和 prompt 约束实现，未做真人误判评估。 |
| AC-15 研究确认边界 | 已验证 | [intelligence_test.dart](../test/intelligence_test.dart) 的授权拒绝零出站请求；[controller_test.dart](../test/controller_test.dart) 的 `unconfirmed external research is blocked before network`；[ui_test.dart](../test/ui_test.dart) 覆盖详情页研究建议需确认。 | 云端总结允许调用模型，与外部搜索授权边界需在用户文案里持续保持清晰。 |
| AC-16 多轮研究 | 已验证 | [intelligence_test.dart](../test/intelligence_test.dart) 覆盖预算内多轮搜索、证据保存和撤销授权检查；[device_flow_test.dart](../integration_test/device_flow_test.dart) 覆盖 Android 设备上的研究链路。 | 当前端到端研究使用本地夹具搜索和模型服务，未验证真实搜索服务。 |
| AC-17 持续主题授权 | 已验证 | [controller_test.dart](../test/controller_test.dart) 覆盖追踪授权、频率、预算和通知门槛；UI 详情页显示追踪控制。 | 长期定期运行未做真实多天观察。 |
| AC-18 范围扩大 | 已验证 | [controller_test.dart](../test/controller_test.dart) 覆盖主题问题变化会撤销追踪授权；研究确认仍需显式 `confirmed`。 | 更复杂的“范围扩大”语义判断目前依赖主题字段变化，不是自然语言安全分类器。 |
| AC-19 延后与补查 | 已验证 | [controller_test.dart](../test/controller_test.dart) 覆盖 due tracking、resume 和补查；应用启动、前台恢复和分享恢复会触发 `resume`。 | 手机系统后台限制下的实际调度表现未做长期设备测试。 |
| AC-20 暂停追踪 | 已验证 | [controller_test.dart](../test/controller_test.dart) 覆盖追踪暂停不会继续启动新轮次；UI 提供暂停按钮。 | 在途任务停止粒度仍以当前实现的轮次检查为准。 |
| AC-21 有意义的通知 | 已验证 | [controller_test.dart](../test/controller_test.dart) 的 tracking notification gate 场景覆盖重要发现、结论变化、需要决策和无重要变化。 | Android 系统通知权限、厂商推送限制只做基础原生调用覆盖。 |
| AC-22 本地使用 | 已验证 | [store_test.dart](../test/store_test.dart) 覆盖 SQLite 重开仍保留原始和生成内容；[final-offline.xml](evidence/final-offline.xml) 展示断网后正文可读；无账号或后台依赖。 | 云端模型和外部搜索不可离线运行，符合需求边界。 |
| AC-23 备份恢复 | 已验证 | [store_test.dart](../test/store_test.dart) 覆盖资产引用、schema 和恢复；[backup_export_test.dart](../test/backup_export_test.dart) 覆盖 ZIP 导出、恢复和偏好刷新；系统文件选择器已导出 `Download/readlater-backup-20260921-032219.zip` 并导入，[restore-result.xml](evidence/restore-result.xml) 显示“资料库已恢复”；[redirect-device.log](evidence/redirect-device.log) 验证独立空资料库恢复、重开及正文、分析摘要和附件字节一致。 | 未覆盖手工卸载重装。 |
| AC-24 自有模型配置 | 已验证 | [settings_page.dart](../lib/ui/settings_page.dart) 提供服务地址、文本模型、多模态模型、搜索服务和 Key；`settings separate model and search keys` 测试通过；`authenticated cloud endpoints reject cleartext before transmitting credentials` 测试通过。 | 真实供应商兼容性未验证；当前只证明 OpenAI-compatible 和搜索夹具协议路径。 |
| AC-25 真实使用复盘 | 部分验证 | 观点卡片、来源引用、主题综述和研究运行已有自动测试；需求文档已删除固定使用周期承诺。 | 需要用户真实资料积累后的复盘，当前不能用夹具测试冒充“研究实际推进”。 |

## 对应测试和日志

日志随源码放在 `docs/evidence/`。测试源文件位于 [test](../test/) 和 [integration_test](../integration_test/)。

| 证据文件 | 说明 |
| --- | --- |
| [final77-tests.log](evidence/final77-tests.log) | 最新全量 Flutter 测试 77 项通过。 |
| [final77-analyze.log](evidence/final77-analyze.log) | 最新静态分析零问题。 |
| [redirect-device.log](evidence/redirect-device.log) | 最终 Android 模拟器集成测试通过，覆盖真实应用存储、HTTP、PDF、研究、自动主题和独立空资料库完整恢复及重开。 |
| [redirect-build.log](evidence/redirect-build.log) | 最终 arm64 release APK 构建成功，日志大小 21.2MB；使用 debug 签名，供个人测试。 |
| [live-capture-check.log](evidence/live-capture-check.log) | 真实普通博客成功抽取；真实微信验证页样本仍为不可提取内容。 |
| [wechat-live-green.log](evidence/wechat-live-green.log) | 真实微信受限页明确失败，不误报为保存成功。 |
| [native-share-red.log](evidence/native-share-red.log) / [native-share-green.log](evidence/native-share-green.log) | 原生分享 content URI 崩溃的红绿修复证据。 |
| [long-share-red.xml](evidence/long-share-red.xml) / [long-share-green.xml](evidence/long-share-green.xml) | 长 PDF 文件名丢扩展名的红绿修复证据。 |
| [final-offline.xml](evidence/final-offline.xml) / [final-library.xml](evidence/final-library.xml) | Android release UI 离线正文阅读和资料库观察证据；[截图](evidence/readlater-android-offline.png) 已确认示例图片正常渲染。 |
| [restore-result.xml](evidence/restore-result.xml) | 系统文件选择器导出 ZIP 后导入，界面显示“资料库已恢复”。 |
| [recreation-red/result.txt](evidence/recreation-red/result.txt) / [density-red/result.txt](evidence/density-red/result.txt) | 进程重建、显示密度变化重建后均为 `count=1`，此轮观察未复现重复分享；不是 PDF 压力测试。 |

## 未作为通过条件的内容

- 视频支持不在第一期实现范围内。
- iPhone 和 Mac 没有验收构建；当前只保留跨端复用设计空间。
- 同步、账号和运营后台未实现，符合“暂不同步、个人自用”的需求边界。
- 真实模型供应商、真实搜索服务、更多真实公众号文章和长期主题效果仍需要后续现场验证。

## 最终 release 界面补查

通过「添加文字」输入 `Readlater-device-note` 并保存，强制停止后重新启动 App，资料列表仍包含该条内容。设备界面证据：[note-reopened.xml](evidence/note-reopened.xml)。

## 公开微信公众号补查

使用当前 ContentService 实际请求三条额外公开链接，均返回“未获取到微信公众号正文”；未把检索引擎中的文章介绍代作采集成功。见 [wechat-public-samples.log](evidence/wechat-public-samples.log)。AC-01 仍为部分验证。
