# V2 UI implementation report

Task 3 implemented in `lib/ui/`, with `test/v2_ui_test.dart` and the attachment interaction update in `test/detail_updates_test.dart`.

## Delivered

- Unified warm white `#FAF8F3`, deep green `#476B4F`, system sans-serif theme, 12dp controls and readable expanded text sizes.
- Compact library rows with search, active/archive/trash scopes, unread/analyzed/error filters, long-press batch selection, select-all, single and batch lifecycle management. Permanent deletion and empty-trash require confirmation. Empty scope and no search results are distinct.
- Reading page uses original/analysis/notes tabs, analysis-first when present, open layout, 17sp/1.7 main text and independently expanded attachments. Archived/trashed content stays readable; analysis and suggested research are disabled. Purged content stops rendering stale copies.
- Developer logs include category/status/entity filtering, timeline, request/response, HTTP/model/request IDs, actual usage (or missing-data explanation), export and confirmed clear. Debug switch and retention/capacity explanations are visible. Item/topic/run failures link to related logs.
- Settings preserve all newer fields when saving, expose 3/7-day trash retention with destructive shortening confirmation, separate inferred interests from explicitly confirmed interests, and link to developer tools.
- RSS saved entries show archive/trash state and open their existing item. Source labels use controller lifecycle-aware labeling.
- Four destinations stay mounted in IndexedStack, preserving search, filters and scroll state. Shell feedback occupies layout space above navigation; only error or notice is displayed at a time, and snackbars replace their predecessor.

## Verification

- First executable UI run: 19 passed, 2 failed. A failure revealed ambiguous per-row menus during batch selection; those menus are now suppressed so only the batch menu is active. The other failure was an outdated tooltip test finder.
- Final command: `flutter test test/v2_ui_test.dart test/ui_test.dart test/detail_updates_test.dart test/library_status_test.dart` — **22 tests passed**.
- `flutter analyze lib/ui test/v2_ui_test.dart test/detail_updates_test.dart` — **No issues found**.
- New tests exercise actual controller-backed archive/trash/restore/purge, destructive cancellation, retained scope/search across navigation, reading tabs and notes, disabled analysis on archives, entity-filtered diagnostics, timeline and request/response/usage rendering, confirmed log clearing, preservation of settings fields, widths **320 / 390 / 430 at 1.8× text scale**, all four shell pages and reader/developer views. All tests use local fixtures and no real model/network requirement.
- Test process required sandbox escalation for Flutter's localhost test socket. Initial sandbox-only run could not bind localhost; approved escalation ran normally.

## Integration notes

- Parent owns controller/model/service review, full suite, Android build and device-level visual verification; this UI slice does not claim device or real provider validation.
- Research log navigation filters by run ID from research detail, by item ID from article detail and by topic ID from topic detail. Parent was notified to keep diagnostic entity IDs aligned with these routes.
- Log export uses the existing file picker API. Native file-destination selection is not exercised by these widget tests.

## Independent-review follow-up

- Reproduced the small-screen keyboard defect before editing: with 320×640 viewport, 1.8× text and 300px bottom keyboard inset, the fixed library header left the empty-result message inaccessible (`hitTestable` failed).
- Replaced the fixed header/expanded-list split with one `CustomScrollView`; search, scope/filter controls, retention notice, rows and empty states can all scroll. Search retains focus and state, while batch controls remain accessible in the app bar.
- Related developer logs now match either `entityId` or `inputItemIds`, covering failed capture/extraction tasks that have no direct entity ID.
- Added regressions for keyboard-constrained populated/empty trash, search focus after scrolling, batch control reachability, and capture-task log navigation through input IDs.
- Final targeted suite after review: **24 tests passed**. Static analysis of `lib/ui` and `test/v2_ui_test.dart`: **No issues found**.

## Citation polish follow-up

- Reader analysis text now maps known source IDs to numbered citations such as `[1]` and hides missing/deleted declared source IDs as `[未知来源]` instead of exposing raw internal IDs.
- Source rows now display numbered, human-readable labels and lifecycle-aware missing-source text without showing the backing ID in the reading UI. Tap behavior still uses the stored ID internally.
- Ordinary bracketed prose such as `[API]` is preserved unless it matches a declared source ID or a generated local source ID pattern.
- Regression: `article analysis renders citations without internal source ids` first failed against the old UI, then passed after the display-layer fix.
- Final related suite: `flutter test test/detail_updates_test.dart test/ui_test.dart` — **13 tests passed**.
- Static analysis: `dart analyze lib/ui/common.dart lib/ui/item_detail.dart test/detail_updates_test.dart` — **No issues found**.
