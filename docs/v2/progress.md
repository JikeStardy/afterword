# 新版执行记录 — plan: docs/superpowers/plans/2026-09-22-v2.md

- 2026-09-22：核对 lib 与用户项目一致；两处均非Git仓库，工作副本复用既有Flutter工具链。只在工作副本编辑，最后向用户项目交付；不初始化Git。
- baseline: work/readlater-v1-baseline（lib/test/integration_test/pubspec，供独立审查diff）。
- 分工：data=models/store，diagnostics=独立日志/IntelligenceService，UI=lib/ui，主代理=AppController/整合/集成测试。接口冲突由上方实施约定固定。
- 1–4进行中；5未开始。所有已有业务行为需保留，旧来源不明结果可读但不能自动用作新分析输入。

## 整合与审查进展

- Task1 模型/备份完成，16测试通过。Task2 日志/模型调用完成，独立审查发现的Cookie/Basic认证脱敏和numeric id问题已RED→GREEN，31测试通过。
- Task3 统一UI完成，审查后补了小屏键盘滚动与inputItemIds日志定位回归，24测试通过。
- Task4 controller整合完成：间接来源排除、在途取消、原始附件晚到、搜索来源URL祖先、过期回收站及来源标签。生命周期审查4条发现已写失败测试后修复；修改主题问题时阻止旧研究迟到回写。
- 全量Flutter测试130项通过，证据 docs/v2/full-tests.log。静态检查仅8个大括号info，已用dart fix修复，正在重新分析与Android设备测试。
- Ruling: 缩短保留期经界面明确确认后立即清理到期资料，与界面承诺一致；平时仍启动/恢复前台补清理。
- Ruling: 旧数据未知来源的自动推断兴趣重新计算，用户明确偏好保留；原有备份UI测试改为明确确认的兴趣，以验证真实用户意图的恢复。
- Ruling: 现有工程不属于Git仓库，保留基线目录进行独立对比审查，不初始化Git。
- 交付门禁仍待：设备截图检查、集成测试结果、最终APK构建及项目/源码包同步；不据目前单元测试宣布目标完成。

## 最终验收 — 2026-09-22

- Tasks 1–5 完成。最终全量 133 测试通过，flutter analyze 无问题。
- Android API 36 完整设备流程和截图导出通过；已目视核对统一主题、引用序号和研究步骤时间线。
- release 0.2.0+2 arm64 构建成功；包名、API 24/36、签名已核对，安装及冷启动成功。
- 所有独立审查发现关闭。引用改动同步覆盖资料分析与主题综述，普通方括号文本保留。
- 交付 APK、源码 ZIP、截图与 SHA256SUMS；原项目预先备份，按文件校验同步。真实供应商与用户个人密钥未测试，见 V2_DELIVERY.md。
