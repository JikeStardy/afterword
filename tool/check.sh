#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

fail() { printf '检查失败：%s\n' "$*" >&2; exit 1; }
mode=${1:-fast}
[[ $# -le 1 ]] || fail '用法：bash tool/check.sh [fast|full|android]'
case "$mode" in fast|full|android) ;; *) fail '用法：bash tool/check.sh [fast|full|android]' ;; esac

flutter=$(command -v "${FLUTTER_BIN:-flutter}") || fail '找不到 Flutter；将 SDK 的 bin 加入 PATH，或设置 FLUTTER_BIN 为 flutter 可执行文件路径。'
[[ -x "$flutter" ]] || fail "Flutter 不可执行：$flutter"
# Resolve launch symlinks so the formatter always comes from the same SDK.
while [[ -L "$flutter" ]]; do
  target=$(readlink "$flutter")
  if [[ "$target" == /* ]]; then flutter=$target; else flutter="$(dirname "$flutter")/$target"; fi
done
flutter="$(cd "$(dirname "$flutter")" && pwd)/$(basename "$flutter")"
dart="$(dirname "$flutter")/dart"
[[ -x "$dart" ]] || fail 'Flutter SDK 中缺少 dart；请检查 FLUTTER_BIN/PATH 是否指向完整 SDK。'
[[ -f pubspec.lock && -f .dart_tool/package_config.json ]] || fail '依赖尚未准备；请先运行 flutter pub get --enforce-lockfile，再重新检查。'

if [[ "$mode" == android ]]; then
  sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
  [[ -n "$sdk" && -d "$sdk/platform-tools" ]] || fail '请设置 ANDROID_HOME（或 ANDROID_SDK_ROOT）为已安装的 Android SDK。'
  if [[ -n ${JAVA_HOME:-} ]]; then
    [[ -x "$JAVA_HOME/bin/java" ]] || fail 'JAVA_HOME 下缺少 bin/java。'
  else
    command -v java > /dev/null || fail '请安装项目要求的 JDK 并设置 JAVA_HOME。'
  fi
fi

for script in tool/*.sh .githooks/*; do
  [[ -f "$script" ]] || continue
  bash -n "$script"
done
"$dart" format --output=none --set-exit-if-changed lib test integration_test test_driver
"$flutter" analyze --no-pub
if [[ "$mode" != fast ]]; then
  bash tool/test-git-hooks.sh
  "$flutter" test --no-pub
fi
if [[ "$mode" == android ]]; then
  # Flutter must regenerate release plugin registrations after test tooling.
  # --no-pub skips that step in the validated SDK; retain the locked versions.
  lock_snapshot=$(mktemp "${TMPDIR:-/tmp}/readlater-lock.XXXXXX")
  trap 'rm -f -- "$lock_snapshot"' EXIT
  cp pubspec.lock "$lock_snapshot"
  build_status=0
  "$flutter" build apk --release --target-platform android-arm64 || build_status=$?
  cmp -s pubspec.lock "$lock_snapshot" || fail '构建改变了 pubspec.lock；已停止，请审阅依赖变化，脚本不会自动恢复或提交。'
  [[ "$build_status" == 0 ]] || exit "$build_status"
fi
printf '检查通过：%s\n' "$mode"
