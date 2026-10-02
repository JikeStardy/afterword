# 当前分支整合清单

日期：2026-10-02。输入为本轮开始时的 19 个分支固定提交；新增整合分支不计入输入数量。冻结后主题分支的新提交不自动纳入。最初盘点保存在 [原始快照](branch-history/2026-10-02-initial-branch-inventory.md)，当前验收见 [整合记录](BRANCH_CONSOLIDATION.md)。

从 main `095173c` 创建独立 worktree，普通合并知识对话 `a1ed61b`，再合并盘点文档 `1e8f2cd`。两个早期分支通过行为核对和历史归档承接，不能声称其提交已成为 main 的祖先。

| 输入分支 | 固定提交 | 整合方式 |
| --- | --- | --- |
| `main` | `095173c` | 整合基线，保留统一字号及网页导入修复 |
| `fix/reading-import` | `095173c` | 基线已包含 |
| `fix/separate-apk-artifacts` | `685020c` | 基线已包含 |
| `fix/cloud-test-signing` | `db1f817` | 基线已包含 |
| `chore/github-actions` | `61cf69e` | 基线已包含 |
| `chore/afterword-branding` | `c2b8b89` | 基线已包含 |
| `feat/integrated-android-release` | `e05b998` | 基线已包含 |
| `feat/app-debug-diagnostics` | `a9befd4` | 基线已包含 |
| `feat/reading-design` | `f0c5688` | 基线已包含 |
| `feat/wechat-capture-recovery` | `1134d56` | 基线已包含 |
| `feat/personal-insights-background` | `fdf4655` | 基线已包含 |
| `chore/git-development-standards` | `ba3ce4e` | 基线已包含 |
| `feat/fox-icon-design-kit` | `276fcaf` | 随知识对话祖先链包含 |
| `feat/fox-app-integration` | `5d371db` | 随知识对话祖先链包含；补齐新 UI 图标别名 |
| `fix/analysis-payload-budget` | `04f7e6a` | 随知识对话祖先链包含 |
| `feat/knowledge-dialogue` | `a1ed61b` | 本轮普通合并，保留知识对话与数据兼容 |
| `docs/branch-inventory` | `1e8f2cd` | 本轮普通合并，原盘点快照另行保留 |
| `feat/readable-analysis` | `c272217` | 行为承接与历史归档，补 PDF 页图设备回归 |
| `feat/visual-refinement` | `c799077` | 由新版阅读设计承接，独有文档与截图归档 |

旧分支逐提交行为对应、八份原样归档文件及 SHA-256 见 [历史索引](BRANCH_HISTORY.md)。旧模型和样式不重新覆盖新版实现。

## 工作区与 Git 边界

- 整合工作区：`/private/tmp/readlater-consolidate`。主工作区保留 `feat/knowledge-dialogue`，不改变用户 checkout。
- 两份未跟踪文件 `docs/research/github-actions-build.md`、`docs/research/wechat-webview-feasibility.md` 不纳入提交。
- 原分支、标签、现存 worktree 和两条失效登记均保留；本轮不清理。
- main 的接收方式为在整合工作区切换 main，以 `--ff-only` 接收已验证提交。main 若在接收前前进，先重新整合、验证，禁止强制移动引用。
- 只合入本地 main，不推送、不发布、不升级依赖或应用版本。
