# 阅读设计验收记录

日期：2026-09-26。基线 `fdf4655`，独立分支 `feat/reading-design`。

## 已实现

- 今日、资料库、RSS、研究入口、文章分析、主题／研究报告和设置使用统一阅读层级。
- 分析先显示短导读，观点改为带标题的连续正文；发现、认知变化、影响及重要限制可直接阅读，证据按需展开并保留原文定位。
- 三种外观即时切换并持久保存；保留长观点的阅读位置、展开状态以及未保存的模型配置草稿。
- 新增可选导读、观点短标题和章节结构；旧记录、全文检索和 Markdown 导出兼容，不自动重新调用模型。简短或无效章节结构回退至原完整报告，引用仍需验证。
- 本次未引入依赖，`pubspec.lock` 未改变。原工作区微信抓取恢复改动未纳入本分支。

## 验证结果

| 检查 | 实际结果 |
| --- | --- |
| `bash tool/check.sh android` | 通过：格式、静态分析、13 个 Git 钩子场景、231 个单元／Widget 测试、Android release 构建 |
| `test/reading_appearance_test.dart` | 11 个测试通过；包括设置草稿保护和通知权限说明不受按钮挤压 |
| 阅读矩阵 | 三预设 × 320／390／430 宽度 × 1／1.8 字体缩放；12 条长观点的离线样本 |
| Android 阅读流程 | 三预设导航、滚动、证据展开、原文定位及实际文字选择、返回状态保持、研究与设置；21 张实际设备截图 |
| 独立审查 | code-reviewer 与 flutter-reviewer 均 APPROVE；最后通知布局调整另经 flutter-reviewer 复核 |

最终检查使用 Flutter 3.47.5（`6a19cca564`）、Dart 3.13.4、JDK 21.0.12；Android 36 arm64 模拟器，1080 × 2340，440 dpi。

修复并验证了简短章节覆盖全文、旧摘要重复导出、重复观点 ID、附入研究来源编号冲突、长观点中段切换预设的位置变化、标签文字对比度、页签字号和通知设置正文过窄问题。

设备复验命令（先设置项目工具链及 `ANDROID_HOME`、`JAVA_HOME`）：

```sh
READLATER_SCREENSHOT_DIR=dist/reading-design/screenshots flutter drive \
  --driver=test_driver/device_screenshots.dart \
  --target=integration_test/reading_design_test.dart -d emulator-5580
```

构建 release 后运行设备测试需让 Flutter 重新生成测试插件注册；此步骤不使用 `--no-pub`。复验曾遇模拟器短暂离线以及旧注册缺失，恢复连接并重新生成后以最终执行结果为准。

## 三种风格

| 外观 | 设计重点 | Android 实际截图 |
| --- | --- | --- |
| 阅读刊物（默认） | 舒展正文、轻分隔 | [分析页](screenshots/editorial-analysis.png) |
| 紧凑研究工具 | 缩减间距，保留正文字号和操作尺寸 | [分析页](screenshots/compact-analysis.png) |
| 数字杂志 | 大标题、章节色面、更多留白 | [分析页](screenshots/magazine-analysis.png) |

其他页面：[今日](screenshots/editorial-today.png)、[资料库](screenshots/editorial-library.png)、[展开证据](screenshots/editorial-evidence.png)、[研究正文](screenshots/magazine-research.png)、[设置](screenshots/editorial-settings.png)。

全部 21 张截图及设备结果保留在本地 `dist/reading-design/screenshots/`，本目录收录其中 8 张。截图使用合成离线数据，没有私人阅读内容。

## 安装包与边界

- APK：`build/app/outputs/flutter-apk/app-release.apk`，arm64，约 22.7 MB，版本 `0.3.0+3`。
- SHA-256：`4f6436064280bd299c7618b780cf6b38a28f5f5609bd4d9fabfa92f2a164ecbf`。
- 沿用项目现有个人测试签名配置；未发布、未上传，也未合并 main。
- 本次验证覆盖模拟器和离线夹具，未验证物理手机、真实模型供应商输出质量或所有厂商的后台行为。系统分享／通知／后台能力没有因本次视觉工作迁移框架。
