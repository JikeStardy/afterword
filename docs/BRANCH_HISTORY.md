# 分支历史归档与行为追溯

本文件记录本轮整合中没有直接合并代码的旧分支独有提交。归档只保存历史文档和截图，不把旧业务实现或旧测试搬回当前代码。历史分支中的验收记录保留为当时证据，不能替代本轮 `feat/consolidate-existing-branches` 的当前检查。

归档文件保持从旧提交读取出的字节原样；其中 Markdown 内部的相对链接仍指向旧分支原路径，只作为历史线索，不保证在当前整合目录直接可点击。

固定输入：

| 分支 | 固定提交 | 处理方式 |
| --- | --- | --- |
| `feat/readable-analysis` | `c272217` | 行为核对，历史研究文档归档 |
| `feat/visual-refinement` | `c799077` | 行为核对，历史研究文档、计划、截图归档 |

## 历史资料归档

| 来源分支 | 来源路径 | 归档路径 | SHA-256 |
| --- | --- | --- | --- |
| `feat/readable-analysis` `c272217` | `docs/research/2026-09-22-readable-analysis.md` | `docs/branch-history/feat-readable-analysis/docs/research/2026-09-22-readable-analysis.md` | `af12775ce6d186a2b95e62f7f88eba59423ffd2029425d9bdcb8f6fc477eba1e` |
| `feat/visual-refinement` `c799077` | `docs/research/2026-09-23-react-native-migration.md` | `docs/branch-history/feat-visual-refinement/docs/research/2026-09-23-react-native-migration.md` | `794a6bcbff2fa7ac56e586a96fb8667869108841e513fa03f82c4429ac3e6801` |
| `feat/visual-refinement` `22b8c7c` | `docs/superpowers/plans/2026-09-22-visual-refinement.md` | `docs/branch-history/feat-visual-refinement/docs/superpowers/plans/2026-09-22-visual-refinement.md` | `a0da53484919f2d259f4587e3b740077b4db67315e047f5cada35b455926c73a` |
| `feat/visual-refinement` `22b8c7c` | `docs/visual-refinement/README.md` | `docs/branch-history/feat-visual-refinement/docs/visual-refinement/README.md` | `f583310657e34bb02f3dc8576e60233997b744f8fe640a4558fdc597849de486` |
| `feat/visual-refinement` `22b8c7c` | `docs/visual-refinement/library-large-text.png` | `docs/branch-history/feat-visual-refinement/docs/visual-refinement/library-large-text.png` | `4416cfb480f89cfabeb2be0a9c6f54702015946e6692101c631585ca4c00e8b1` |
| `feat/visual-refinement` `22b8c7c` | `docs/visual-refinement/library.png` | `docs/branch-history/feat-visual-refinement/docs/visual-refinement/library.png` | `507e9d15806a4b1e311159e23d20f93a0b46dfaf0050e600a3fcf9c70923474b` |
| `feat/visual-refinement` `22b8c7c` | `docs/visual-refinement/reader.png` | `docs/branch-history/feat-visual-refinement/docs/visual-refinement/reader.png` | `f56a94ef07c9ace9436cebd05fd50f5a5b8fd9de90d9898b8bd1b68130bac2e9` |
| `feat/visual-refinement` `22b8c7c` | `docs/visual-refinement/settings.png` | `docs/branch-history/feat-visual-refinement/docs/visual-refinement/settings.png` | `a56decb2b4b8c6187bc69f748b3f4a1a29c1b730830f8af71d26ca957467f2fd` |

## 独有提交行为核对

### `4a422fc` `feat(analysis): 分层展示观点并支持原文依据核对`

旧意图：

- `Analysis` 增加结构化观点、短结论和 evidence；旧 `insights` 继续可读。
- 文本 evidence 只能引用当前资料连续原文，不能把模型摘要或关联内容伪装成原文。
- PDF evidence 使用物理页号、附件指纹和待核对标记；页码必须落在实际范围内。
- 阅读详情页把分析正文、结构化观点、解释、影响、未知项和 evidence 分层展示，并支持跳回原文或 PDF 页。

当前处理：**已由当前实现覆盖，旧模型字段被新设计吸收，不回灌旧代码。**

当前证据：

- `lib/core/models.dart` 仍保留 `Analysis.structuredInsights`、`EvidenceAnchor` 的 `sourceVersion`、`blockId`、`quote`、`assetFingerprint` 和 `pdfPage` 字段，并读取历史 `highlights` 到结构化观点。
- `lib/services/intelligence_service.dart` 要求模型返回 `structuredInsights`，并通过 `KnowledgeService.validateStructuredInsights` 校验文本和 PDF evidence。
- `lib/services/knowledge_service.dart` 校验 PDF 页码、来源版本、附件指纹和文本引用范围；无效 evidence 不进入新推理输入。
- `lib/ui/item_detail.dart` 的 `_AnalysisSection` 先展示 brief/summary，再展示结构化观点、解释、影响、未知项、证据列表和原文/PDF 定位；PDF evidence 文案仍标注“图像转录，待核对”。
- `test/integrated_evidence_test.dart`、`test/intelligence_test.dart`、`test/legacy_analysis_compatibility_test.dart`、`test/reading_ui_test.dart`、`test/source_controller_cache_test.dart` 覆盖旧 highlights 兼容、结构化 evidence 校验、PDF 页码与附件指纹、UI 展示和缓存复用。

未搬回内容：

- 旧分支 `lib/ui/item_detail.dart` 的具体版式和旧 `analysis_evidence_test.dart`/`analysis_presentation_test.dart` 不直接复制，因为当前阅读页已经包含 V3 阅读设计、全局字号和知识对话入口，旧实现会覆盖较新的结构。

### `c272217` `test(analysis): 验证设备端原文引用与 PDF 页图`

旧意图：

- 设备夹具返回结构化观点与引用。
- 设备流程确认网页引用已核验、PDF 图像转录待核对、页号正确。
- 打开文本 evidence 和 PDF evidence 弹窗；PDF 弹窗必须包含已解码页图，不能用错误占位通过。

当前处理：**已由本轮设备回归覆盖并在 API 36 arm64 模拟器执行通过；旧弹窗布局不重新引入。**

当前证据：

- `integration_test/knowledge_dialogue_device_test.dart` 已覆盖真实 `native.renderPdf`、PDF 页数、`visualEvidence.page`、`assetFingerprint`、`unverified` 和 evidence/visualEvidence 指纹一致。
- `integration_test/device_flow_test.dart` 已补当前综合设备回归：断言 PDF evidence 保留 `sourceVersion`、`pdfPage`、附件 `assetFingerprint` 与 `unresolved`；通过新版证据入口跳转到原文 PDF 页，并检查 `RawImage.image` 非空且可命中点击。该断言承接旧分支“PDF 页图不能用占位通过”的行为要求。
- `tool/fixture_server.mjs` 已补夹具响应，保留传入的 PDF evidence 字段，避免测试只验证文本 evidence。
- `lib/platform/native_bridge.dart`、`lib/ui/item_detail.dart` 保留 PDF 页渲染和 evidence 到原文页的导航能力。

本轮执行证据：

- `device_flow_test.dart` 与 `knowledge_dialogue_device_test.dart` 已在本轮执行通过；综合流程实际展开 PDF 证据、跳到物理页并断言可见 `RawImage.image` 非空，没有用错误占位通过。
- 当前完整验收及边界见 [整合记录](BRANCH_CONSOLIDATION.md)。原始日志与 `pdf-evidence-page.png` 保存在忽略目录 `dist/branch-consolidation/`；历史截图保持原样。

### `22b8c7c` `style(ui): 完善阅读层级与统一视觉细节`

旧意图：

- 统一暖白、深绿、文字层级、输入边界、标签、导航和空状态视觉。
- 资料列表区分范围筛选和状态筛选，显示结果数量和未读信息。
- 阅读页建立标题、辅助信息、正文和分析的阅读节奏。
- 覆盖 320/390/430 宽度、1.8 倍文字、键盘遮挡、筛选计数、焦点保持和笔记保存。

当前处理：**由较新的阅读设计和全局字号实现覆盖，旧截图作为历史外观证据归档。**

当前证据：

- `docs/reading-design/README.md` 和 `docs/reading-design/VALIDATION.md` 记录当前三种外观：阅读刊物、紧凑研究工具、数字杂志。
- `lib/core/models.dart` 定义 `ReadingPreset` 并随设置持久化；`lib/ui/common.dart` 定义阅读布局、显示名和主题；`lib/ui/item_detail.dart`、`lib/ui/library_page.dart`、`lib/ui/research_page.dart`、`lib/ui/rss_page.dart` 使用统一阅读布局。
- `lib/core/models.dart` 和 `lib/core/app_controller.dart` 持久化并校验全局 `readerFontScale`，`test/models_test.dart`、`test/controller_test.dart`、`test/reading_appearance_test.dart` 覆盖保存、恢复和边界。
- `test/v2_ui_test.dart`、`test/reading_ui_test.dart` 继续覆盖阅读页、资料页、键盘和大字体相关行为。

未搬回内容：

- 旧分支的具体 `common.dart`、`library_page.dart`、`rss_page.dart`、`research_page.dart` 样式修改不直接套用，因为当前分支已接入更完整的阅读预设、长尾狐图标和知识对话入口。

### `c799077` `docs: 评估长篇分析设计与 React Native 迁移`

旧意图：

- 只读评估长篇观点页信息结构和 React Native 迁移成本。
- 指出排版问题主要来自信息优先级，而不只是颜色、字号和留白。
- 建议先在 Flutter 内完善长文观点结构；RN PoC 只作为长期技术栈选择的验证。

当前处理：**作为历史研究归档，不作为当前迁移计划。**

当前证据：

- 当前整合仍沿用 Flutter/Dart、Android 原生桥接、SQLite JSON 快照和现有测试夹具；没有引入 RN 或新依赖。
- 结构化观点、证据展开、全局阅读预设和知识对话已经在 Flutter 路线内实现，符合旧研究“先解决信息结构”的方向。

## 本轮不处理的旧差异

两个旧分支从较早基线分叉，`main..c272217` 和 `main..c799077` 显示大量对 V3 文档、诊断、后台、微信恢复和平台文件的删除。这些不是旧分支要保留的业务意图，而是分叉后缺少较新主线提交造成的反向差异；本轮不按删除处理。

旧分支测试夹具和业务代码不直接复制，原因是它们基于 V2/V3 早期结构，会覆盖当前已整合的知识对话、全局字号、长尾狐品牌和最新数据模型。被保留的是可追溯的行为意图与历史证据文件。
