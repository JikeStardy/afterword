# 分支整理清单

盘点日期：2026-10-02。以下记录针对整理开始时的 16 个本地分支；本次文档分支 `docs/branch-inventory` 不计入历史分支数量。

整理过程中新增了 `fix/analysis-payload-budget`（创建时为 `5d371db`），由其他任务使用主工作区开展修复，作为进行中的分支保留；本次没有审查或合入其后续修改。本次文档在 `/private/tmp/readlater-branch-inventory` 独立工作区提交。新增这两个分支后，本地共有 18 个分支；清单继续保留原始 16 分支快照，避免把进行中工作混入历史清理候选。

## 当前基线

- 本地 `main`、缓存的 `origin/main` 及远端实际 `main` 均为 `095173c`。通过 `git ls-remote --heads --tags origin` 读取确认，远端仅有 `main`，没有远端标签；本地另有 `v0.2.0` 标签。
- 原工作分支为 `feat/fox-app-integration`（`5d371db`），包含狐狸图标资源及 App 接入。它与 main 分叉：main 独有 1 个提交，它独有 3 个提交。
- 11 个主题分支已完整进入 main，另有 4 个主题分支不是 main 的祖先。后者包含两个需要按实现核对的旧分支，不能仅凭名称或提交时间删除。
- 主工作区有两份未跟踪文档：`docs/research/github-actions-build.md`、`docs/research/wechat-webview-feasibility.md`。本次保留原文件，不纳入整理提交。

## 全部分支

“main 独有 / 分支独有”来自 `git rev-list --left-right --count main...<分支>`，统计提交历史差异，不等于功能差异。短 SHA 均为本次盘点时的分支顶端。

| 分支 | 顶端 | main 独有 / 分支独有 | 状态与处理建议 |
| --- | --- | --- | --- |
| `main` | `095173c` | 0 / 0 | 稳定基线，与远端一致 |
| `fix/reading-import` | `095173c` | 0 / 0 | 与 main 完全相同；关联现存 worktree，先处理该工作区再考虑删除分支 |
| `fix/separate-apk-artifacts` | `685020c` | 1 / 0 | 已合入 main，可列入清理候选 |
| `fix/cloud-test-signing` | `db1f817` | 2 / 0 | 已合入 main，可列入清理候选 |
| `chore/github-actions` | `61cf69e` | 3 / 0 | 已合入 main，可列入清理候选 |
| `chore/afterword-branding` | `c2b8b89` | 6 / 0 | 更名和初版品牌稿已合入 main，可列入清理候选 |
| `feat/integrated-android-release` | `e05b998` | 9 / 0 | Android 0.3.1 整合基线已合入 main，可列入清理候选 |
| `feat/app-debug-diagnostics` | `a9befd4` | 13 / 0 | 诊断功能已合入 main；关联的临时 worktree 已不存在 |
| `feat/reading-design` | `f0c5688` | 13 / 0 | 新版阅读和三种外观已合入 main；关联现存 worktree |
| `feat/wechat-capture-recovery` | `1134d56` | 13 / 0 | 微信收藏恢复已合入 main，可列入清理候选 |
| `feat/personal-insights-background` | `fdf4655` | 14 / 0 | V3 和后台能力已合入 main，可列入清理候选 |
| `chore/git-development-standards` | `ba3ce4e` | 15 / 0 | Git 规范和检查工具已合入 main，可列入清理候选 |
| `feat/fox-icon-design-kit` | `276fcaf` | 1 / 2 | 完整包含于 `feat/fox-app-integration`；以后整合后者即可覆盖此分支 |
| `feat/fox-app-integration` | `5d371db` | 1 / 3 | 待与 main 整合；保留正文导入和字号修复，同时接入品牌图标 |
| `feat/readable-analysis` | `c272217` | 15 / 3 | 旧分析模型已由 V3 承接；历史记录和专用测试需单独核对，不直接合入旧代码 |
| `feat/visual-refinement` | `c799077` | 15 / 2 | 旧视觉方案由新版阅读设计承接；独有迁移评估、方案文档和截图需保留 |

## 待整合的狐狸分支

共有三个 main 尚未包含的提交：

1. `7729b75`：整理长尾狐套装主形参考。
2. `276fcaf`：交付图标库与离线动效样册。
3. `5d371db`：接入 App 和 Android 图标、启动页与原生动效。

main 的独有提交 `095173c` 修复统一字号、网页抓取及正文补充。对这两个分支运行 `git merge-tree --write-tree main feat/fox-app-integration`，得到一个冲突文件 `lib/ui/item_detail.dart`、两处冲突块；分支和工作区未移动：

- 正文按钮：合并结果应使用 `AfterwordIcon`，同时保留 main 的 `needsRecovery ? '粘贴正文' : '补充正文'` 文案。
- `_ReaderToolbar`：main 已移除页面内字号工具栏并使用统一字号设置。整合时保留 main 的移除结果，避免把旧控件重新引入。

README、资料列表及设置页面在预演中自动合并；自动合并不等于功能验证通过。实际整合应在新功能分支完成冲突处理、相关阅读与品牌测试、full 检查、Android 构建及设备验证，并接受独立审查。

## 两个旧分支的保留范围

[统一交付清单](INTEGRATED_DELIVERY.md) 记录了旧分析与旧视觉能力由 V3、新版阅读设计承接的决定。这是历史设计依据，不能当作本次代码验证结果。`git cherry` 和祖先检查仍显示其独有提交，故不能把它们标记为“已完整合并”。

`feat/readable-analysis` 的独有历史为 `4a422fc`、`a80bfa2` 和 `c272217`。该分支独有 `docs/research/2026-09-22-readable-analysis.md`，以及旧模型专用的 `test/analysis_evidence_test.dart`、`test/analysis_presentation_test.dart`、`test/pdf_evidence_flow_test.dart`。核心模型、界面和设备测试应与当前实现逐项比对；旧测试不能未经适配直接复制进当前模型。

本次独立只读核对确认：`lib/core/models.dart` 已把旧 `highlights` 转为 `structuredInsights`，`test/legacy_analysis_compatibility_test.dart` 覆盖旧结构迁移，`test/integrated_evidence_test.dart` 覆盖引文核验及 PDF 汇总引用复用；阅读页已有观点、可展开证据和段落／PDF 页跳转。这些是静态实现与测试内容证据，本次未执行它们。旧 `c272217` 设备测试中的“证据弹窗包含已解码 PDF 页图”断言未在当前设备测试中原样保留，应在后续整合时核对该验证意图，不能声称所有旧覆盖已等价迁移。

`feat/visual-refinement` 的独有历史为 `22b8c7c` 和 `c799077`。独有资料包括：

- `docs/research/2026-09-23-react-native-migration.md`。
- `docs/superpowers/plans/2026-09-22-visual-refinement.md`。
- `docs/visual-refinement/README.md` 及四张截图。

上述资料目前保留在原分支，可用 `git show <分支>:<路径>` 读取。若以后收拢到主线，先以历史方案标记归档；不因此引入 React Native 迁移或覆盖当前三种外观。

当前 `test/reading_matrix_test.dart` 已包含 320／390／430 宽度和 1.8 倍文字的布局覆盖，`test/v2_ui_test.dart` 保留键盘下结果可达检查；本次只读核对其内容，未重跑测试。

## Worktree 状态

| 路径 | 分支 | 盘点结果 |
| --- | --- | --- |
| `/Users/tomato/Documents/code/readlater` | 原为 `feat/fox-app-integration`，后切到 `fix/analysis-payload-budget` | 初始有两份未跟踪研究文档；其他任务继续在此修复，原文件保留 |
| `/private/tmp/readlater-branch-inventory` | `docs/branch-inventory` | 本次文档的独立工作区，避免干扰主工作区 |
| `/private/tmp/readlater-app-debug` | `feat/app-debug-diagnostics` | 目录不存在，Git 标记为可清理的失效登记 |
| `/private/tmp/readlater-readable-analysis` | `feat/readable-analysis` | 目录不存在，Git 标记为可清理的失效登记 |
| `/Users/tomato/.codex/worktrees/reading-design/readlater` | `feat/reading-design` | 现存；`git status --short --branch` 未显示改动 |
| `/Users/tomato/.codex/worktrees/reading-import-fixes/readlater` | `fix/reading-import` | 现存；`git status --short --branch` 未显示改动 |
| `/Users/tomato/.codex/worktrees/visual-refinement/readlater` | `feat/visual-refinement` | 现存；`git status --short --branch` 未显示改动 |

`git worktree prune --dry-run --verbose` 只报告以上两条失效登记；本次没有执行实际清理。现存工作区的干净状态不证明其中没有被忽略的安装包、日志或其他文件，不直接移除工作区。

## 后续顺序与本次边界

1. 在新功能分支整合 main 与 `feat/fox-app-integration`，解决上述两处冲突并验证。
2. 单独归档两个旧分支的独有文档，核对当前行为是否存在缺口；若发现缺口，增加当前模型的行为测试并修复。
3. 用户明确发起后，再合并 main。分支删除也须明确授权，并先处理 worktree 与需保留的资料；推送另外需要明确指令。

本次只完成分支盘点、远端只读核对与合并预演，没有合并 main、删除分支、改写历史、上传代码或改变业务代码。没有运行 Flutter 或设备验收，不对分支代码的当前可用性作通过声明。
