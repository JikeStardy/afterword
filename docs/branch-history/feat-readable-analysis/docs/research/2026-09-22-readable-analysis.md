# 分层分析展示与可核对引用

## 目标与边界

分析页首先呈现短结论和可区分的观点，解释、依据、关联和后续研究按需展开。原文摘录必须有来源；PDF 图像转录标记为待核对，支持查看实际页图。旧分析保持可读，不自动消耗模型调用补写引用。

浏览器访问与抓取是不同能力。用户确认 Chrome 可以打开微信文章，但本轮没有复现其设备环境。详情页新增“打开原文”入口，复用已有 ACTION_VIEW；由系统处理链接，可能交给浏览器或匹配的应用，不强制 Chrome，也不自动回传正文。Custom Tabs 可以共享承载浏览器的会话，但不允许 App 任意注入脚本读取第三方 DOM；WebView 可读取 DOM，但不继承 Chrome 会话。

官方依据：[Android 内嵌浏览对比](https://developer.android.com/develop/ui/views/layout/webapps/in-app-browsing-embedded-web)、[Chromium Custom Tabs 安全说明](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/security/custom-tabs-faq.md)。

## 数据与兼容性

- Analysis 新增可选 highlights（短标题、解释、evidence）；保留 insights 字符串列表供现有流程使用。已有备份缺少 highlights 时按空列表读取，原有数据版本不变。
- 文本引用只接受当前资料的连续原话，折叠连续空白核验并保留词间边界，不能用关联摘要充当原话。验证标志由服务计算，不信任模型返回的 verified。
- PDF 每批图像附带从 1 开始的实际物理页号。模型转录只允许指向本批提供的页，仍不表示转录正确或已逐字核对。
- PDF 和长文本最终汇总只能复用前序收集的引用，不能从中间摘要生成“原文”。引用丢失或不合法时不展示为证据，保留可读分析。
- 页面清楚区分分析解释、原文摘录、待核对图像转录。未生成引用的历史分析需要用户主动重新分析。

## 验证

测试覆盖旧数据往返、伪造引文过滤、摘要不能冒充原文、PDF 页范围校验、最终汇总引用来源、真实控制器分批和保存链路，以及展示交互。测试使用受控模型响应，不能证明真实供应商遵守结构化输出提示或实际 PDF 转录质量。

### 本轮结果

- `FLUTTER_BIN=<本机已有 Flutter> bash tool/check.sh full` 通过：格式、静态分析无问题，12 个隔离 Git 场景、147 项单元/Widget 测试全部通过。
- code-reviewer 与 flutter-reviewer 独立审查完成。修复了词间空白造成错误核验、NBSP 高亮不一致、图片转录缺少原图入口的问题；回归测试覆盖上述修正。
- 窄屏 360 宽度与实际 1.8 倍文字缩放下验证观点展开、PDF 长标题页图弹窗；已有统一界面测试还覆盖 320/390/430 宽度。
- 用合成内容和本机中文字体生成界面预览并人工检查；不是手机设备截图。
- 没有新增依赖，没有改原生桥接，没有执行真实模型调用、微信正文自动回传或本轮真机安装。未合并 main。

### Android 续验

- 补充设备夹具的结构化观点与引用响应；设备流程检查网页引用已核验、PDF 图像转录待核对及物理页号，并打开两类依据弹窗。PDF 弹窗还必须包含已解码的页图，不能以错误占位通过测试。
- `bash tool/check.sh android` 通过：格式与静态分析、13 个隔离 Git 场景、147 项测试、arm64 release APK 构建；依赖锁文件未改变。
- APK SHA-256：`fb81d5092a321380354225ccbad6b826aca7bcdbf42e76a037390c9b9e11a16f`。版本为个人测试包 `0.2.0+2`。
- TypeScript/JavaScript 与独立代码审查完成，补强了 PDF 解码断言；`node --check tool/fixture_server.mjs` 通过。
- Android 36 / arm64 临时 Pixel 7 模拟器端到端流程通过（`flutter drive --driver=test_driver/device_screenshots.dart --target=integration_test/device_flow_test.dart -d emulator-5554`）。保存 5 张设备截图，人工查看分析页与 PDF 依据页，页图可读、无错误占位。
- 设备流程使用本机固定响应，覆盖原生 PDF 渲染与实际 Flutter 交互，不代表真实供应商、手机 Chrome 会话或微信自动抓取已验证。没有操作个人手机、合并 main 或上传代码。
