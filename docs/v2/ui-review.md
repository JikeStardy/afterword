# V2 UI independent review

Read-only review of `lib/ui/*` against task 3 in `docs/superpowers/plans/2026-09-22-v2.md`, the unified visual specification, and `../readlater-v1-baseline`. No application code changed. Existing 22 passing widget tests were inspected, not rerun. Architecture: built-in ChangeNotifier/AnimatedBuilder, controller injection, imperative Navigator routes.

## Findings

[HIGH] Failed capture logs disappear from the item failure shortcut

File: `lib/ui/developer_page.dart:69`

Issue: Related-only filtering accepts only `task.entityId == widget.entityId`. `captureUrl` creates its capture task without an entity ID (`lib/core/app_controller.dart:448`), then adds the new item ID only to `inputItemIds`. When extraction fails, `_fetch` marks that capture task failed and leaves the item with an error; no analysis child is created. Consequently, the reader's failure-log shortcut opens an empty filtered log list even though the relevant failed capture task exists.

Repro: Make webpage extraction fail (for example with a throwing content-service fixture), save the URL, open its failed item, and tap “查看任务日志”. It shows “暂无匹配日志”; disabling “仅此资料 / 研究” reveals “保存网页”.

Fix: Associate capture/import tasks with the created item, or include matching `inputItemIds` in related filtering. Cover an actual controller-backed failed capture rather than only a diagnostic fixture with a manually assigned entity ID.

[MEDIUM] Existing topic is labeled as a deleted source in its diagnostic detail

File: `lib/ui/developer_page.dart:343`

Issue: All task entity IDs are passed to `controller.sourceLabel`. That resolver currently handles library items and research runs only (`lib/core/app_controller.dart:398`), while synthesis and tracking tasks use topic IDs. A valid topic therefore renders as “关联：来源已删除（topic-id）”.

Repro: Open a synthesis/tracking task belonging to a topic that still exists, including through the failed topic's “查看任务日志” shortcut.

Fix: Resolve topic entities as topic titles in diagnostics, or extend the shared resolver where appropriate.

## Verification boundaries

- Lifecycle menus, archive/trash/restore semantics, permanent-delete confirmation, preservation of settings fields, and IndexedStack state retention match the agreed paths on inspection. Archived/trashed reader actions block new analysis/research. Parent's run-ID child-task diagnostic fix aligns with the research detail route.
- Unified warm-white/green theme and open 17sp/1.7 reader body are present. No critical security issue was identified in the changed UI code.
- Log export matches the locally installed file_picker 13.1.0 `saveFile(bytes:, mimeType:)` API. Native destination selection remains a device-validation gap.
- Additional layout validation is needed with a visible keyboard: `LibraryPage` uses a non-scrolling fixed header (`lib/ui/library_page.dart:111`–166). At 320×640, 1.8× text scale, trash scope, and a roughly 300px keyboard, the two chip rows, search field and retention text can exceed the remaining body height. Existing width tests use height 900 without keyboard insets. This is a concrete validation target, not counted as an executed reproduction.

## Review Summary

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0 | pass |
| HIGH | 1 | block |
| MEDIUM | 1 | info |
| LOW | 0 | note |

Verdict: BLOCK — fix the failed-capture log shortcut before delivery. Findings reflect the review snapshot; parent owns fixes and fresh verification.

## Scoped resolution review — 2026-09-22

The two findings above and the keyboard-layout validation target are resolved. This follow-up supersedes the original BLOCK verdict for this review scope. No application code was edited and no test suite was rerun during review.

- **HIGH resolved:** `DeveloperPage` now includes tasks whose `inputItemIds` contain the selected entity, in addition to direct `entityId` matches. This includes the failed capture task previously omitted. The new widget regression creates a failed capture diagnostic with only an input-ID association, excludes an unrelated task, and opens the matching failure detail. The existing controller capture path records the item in those input IDs.
- **MEDIUM resolved:** `AppController.sourceLabel` now resolves existing topics by title before falling back to deleted-source labeling. `test/lifecycle_controller_test.dart` contains a direct assertion for the topic label.
- **Keyboard gap resolved:** The library header, retention message, result rows, and empty states now share one `CustomScrollView` with slivers. The new 320×640, 1.8× text, 300px keyboard-inset regression verifies no layout exception, retained search focus, reachable populated results, batch controls, no-result text, and empty-trash text.

Evidence inspected: `docs/v2/ui-report.md` records 24 passing targeted UI tests and clean scoped analysis; `docs/v2/full-tests.log` ends with `+130: All tests passed!`. Native file-destination selection remains the previously disclosed device-validation boundary, not an unresolved code finding.

## Review Summary

| Severity | Unresolved count | Status |
|----------|------------------|--------|
| CRITICAL | 0 | pass |
| HIGH | 0 | pass |
| MEDIUM | 0 | pass |
| LOW | 0 | note |

Verdict: APPROVE — the scoped findings and keyboard-layout concern are resolved.
