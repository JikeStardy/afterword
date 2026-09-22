#!/usr/bin/env bash
set -euo pipefail

# Re-enter under a command-line Git override to continuously test isolation.
if [[ ${1:-} != --isolated-child ]]; then
  GIT_CONFIG_PARAMETERS="'core.hooksPath'='outside-hooks'" bash "${BASH_SOURCE[0]}" --isolated-child
  exit
fi

# Exercise real Git commits in disposable repositories, with an SDK adapter
# that injects formatter/analyzer failures without running Flutter per case.
project=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
for file in .githooks/pre-commit tool/check.sh tool/setup-dev.sh; do
  [[ -x "$project/$file" ]] || { echo "FAIL: executable $file is missing" >&2; exit 1; }
done
suite=$(mktemp -d "${TMPDIR:-/tmp}/readlater-hooks.XXXXXX")
trap 'rm -rf -- "$suite"' EXIT
mkdir -p "$suite/sdk" "$suite/template"
cat > "$suite/sdk/dart" <<'SDK'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == 'format --output=none --set-exit-if-changed lib test integration_test test_driver' ]]
if [[ -f FORMAT_FAIL ]]; then echo 'fixture: formatter failure' >&2; exit 1; fi
SDK
cat > "$suite/sdk/flutter" <<'SDK'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == 'analyze --no-pub' ]]
if [[ -f ANALYZE_FAIL ]]; then echo 'fixture: analyzer failure' >&2; exit 1; fi
SDK
chmod +x "$suite/sdk/"*
export FLUTTER_BIN="$suite/sdk/flutter"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
# Hooks inherit Git's environment; never let an outer index/worktree leak in.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS || true
count=0

new_repo() {
  count=$((count + 1))
  repo="$suite/case-$count"
  mkdir -p "$repo"
  git -C "$repo" -c init.templateDir="$suite/template" init -q -b test
  git -C "$repo" config user.name 'Hook fixture'
  git -C "$repo" config user.email 'fixture@example.invalid'
  mkdir -p "$repo/.githooks" "$repo/tool" "$repo/lib" "$repo/test" "$repo/integration_test" "$repo/test_driver" "$repo/.dart_tool"
  cp "$project/.githooks/pre-commit" "$repo/.githooks/"
  cp "$project/tool/check.sh" "$project/tool/setup-dev.sh" "$repo/tool/"
  printf 'void main() {}\n' > "$repo/lib/main.dart"
  printf '{}\n' > "$repo/.dart_tool/package_config.json"
  printf 'fixture lock\n' > "$repo/pubspec.lock"
  printf 'name: fixture\n' > "$repo/pubspec.yaml"
  printf 'analysis\n' > "$repo/analysis_options.yaml"
  printf '.dart_tool/\n*.log\n' > "$repo/.gitignore"
  printf '# Fixture\n' > "$repo/README.md"
  git -C "$repo" add .
  git -C "$repo" commit -qm 'chore: fixture baseline'
  (cd "$repo" && bash tool/setup-dev.sh > "$suite/install.log")
}

expect_blocked() {
  local message=$1 before_tree before_status after_tree after_status
  before_tree=$(git -C "$repo" write-tree)
  before_status=$(git -C "$repo" status --porcelain)
  git -C "$repo" diff --binary > "$suite/before.diff"
  if git -C "$repo" commit -qm 'test: should be rejected' > "$suite/rejection.log" 2>&1; then
    echo "FAIL: commit unexpectedly accepted ($message)" >&2; exit 1
  fi
  grep -F "$message" "$suite/rejection.log" > /dev/null || { cat "$suite/rejection.log"; exit 1; }
  after_tree=$(git -C "$repo" write-tree)
  after_status=$(git -C "$repo" status --porcelain)
  git -C "$repo" diff --binary > "$suite/after.diff"
  [[ "$before_tree" == "$after_tree" && "$before_status" == "$after_status" ]]
  cmp "$suite/before.diff" "$suite/after.diff"
}

new_repo
(cd "$repo" && bash tool/setup-dev.sh > /dev/null)
[[ $(git -C "$repo" config --local core.hooksPath) == .githooks ]]
printf '// updated\n' >> "$repo/lib/main.dart"
git -C "$repo" add lib/main.dart
git -C "$repo" commit -qm 'feat: valid source change'
echo 'PASS: installation is idempotent; valid source commit succeeds'

new_repo
printf '\nDocumentation only.\n' >> "$repo/README.md"
git -C "$repo" add README.md
FLUTTER_BIN="$suite/no-sdk" git -C "$repo" commit -qm 'docs: no SDK required'
echo 'PASS: documentation commit does not require Flutter'

new_repo
mkdir -p "$repo/docs"
git -C "$repo" mv lib/main.dart docs/main.dart
(export FLUTTER_BIN="$suite/no-sdk"; expect_blocked '找不到 Flutter')
echo 'PASS: moving source into docs still requires source checks'

for failure in FORMAT ANALYZE; do
  new_repo
  printf '// staged\n' >> "$repo/lib/main.dart"
  git -C "$repo" add lib/main.dart
  touch "$repo/${failure}_FAIL"
  expect_blocked 'fixture:'
done
echo 'PASS: formatter and analyzer errors reject without changing index or files'

new_repo
printf 'private fixture\n' > "$repo/.env"
git -C "$repo" add .env
expect_blocked '禁止入库'
new_repo
printf 'log fixture\n' > "$repo/runtime.log"
git -C "$repo" add -f runtime.log
expect_blocked '禁止入库'
echo 'PASS: private paths and force-added ignored files are rejected'

new_repo
printf 'trailing whitespace   \n' >> "$repo/README.md"
git -C "$repo" add README.md
expect_blocked 'whitespace'
echo 'PASS: staged whitespace error is rejected'

new_repo
printf '// staged\n' >> "$repo/lib/main.dart"
git -C "$repo" add lib/main.dart
printf '// unstaged\n' >> "$repo/lib/main.dart"
expect_blocked '未暂存'
new_repo
printf '// staged\n' >> "$repo/lib/main.dart"
git -C "$repo" add lib/main.dart
printf 'void extra() {}\n' > "$repo/lib/untracked.dart"
expect_blocked '未跟踪'
echo 'PASS: partial staging and untracked source are rejected'

new_repo
printf '// staged\n' >> "$repo/lib/main.dart"
git -C "$repo" add lib/main.dart
rm "$repo/.dart_tool/package_config.json"
expect_blocked 'pub get'
echo 'PASS: missing dependency setup gives an actionable failure'

new_repo
git -C "$repo" config --local core.hooksPath custom-hooks
if (cd "$repo" && bash tool/setup-dev.sh > "$suite/conflict.log" 2>&1); then exit 1; fi
[[ $(git -C "$repo" config --local core.hooksPath) == custom-hooks ]]
new_repo
git -C "$repo" config --local --unset core.hooksPath
mkdir -p "$repo/.git/hooks"
printf '#!/bin/sh\nexit 0\n' > "$repo/.git/hooks/pre-push"
if (cd "$repo" && bash tool/setup-dev.sh > "$suite/conflict.log" 2>&1); then exit 1; fi
[[ -f "$repo/.git/hooks/pre-push" ]]
[[ -z $(git -C "$repo" config --get core.hooksPath || true) ]]
echo 'PASS: existing hook configuration and default hooks are preserved'
echo "PASS: $count disposable Git scenarios"
