#!/usr/bin/env bash
set -euo pipefail
root=$(git rev-parse --show-toplevel) || { echo '请在 Git 工作仓库中运行安装命令。' >&2; exit 1; }
cd "$root"
[[ -x .githooks/pre-commit && -x tool/check.sh ]] || { echo '项目钩子或检查脚本缺失／不可执行。' >&2; exit 1; }
configured=$(git config --get core.hooksPath || true)
if [[ -n "$configured" && "$configured" != .githooks ]]; then
  printf '检测到已有 core.hooksPath=%s；保留原配置，请人工协调。\n' "$configured" >&2
  exit 1
fi
if [[ -z "$configured" ]]; then
  default_hooks=$(git rev-parse --git-path hooks)
  for hook in "$default_hooks"/*; do
    [[ -e "$hook" || -L "$hook" ]] || continue
    [[ "$hook" == *.sample ]] && continue
    printf '检测到已有钩子 %s；安装会遮蔽它，已停止并保留原文件。\n' "$hook" >&2
    exit 1
  done
fi
git config --local core.hooksPath .githooks
echo '本仓库已启用 .githooks（可重复运行）；未修改全局 Git 配置。'
