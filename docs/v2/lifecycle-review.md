# Lifecycle and provenance review

Reviewed 2026-09-22 against `docs/superpowers/plans/2026-09-22-v2.md`, focusing on `lib/core/models.dart`, `store.dart`, and `app_controller.dart`, with the relevant intelligence and settings call sites. Compared the supplied `../readlater-v1-baseline`; this directory has no usable Git index. This is an independent static review. No application code was changed and no parent-owned test suites were rerun.

## Confirmed findings

### [HIGH] Cached research bypasses exclusion of a known library URL

File: `lib/core/app_controller.dart:1094` and `:551`.

Issue: `_executeResearch` initializes `run.inputItemIds` from the origin, preferences, and topic only. Search results never contribute matching library item IDs. `_knowledgeSources` subsequently treats a run with `inputItemIds: []` as reusable and includes both its report and source excerpts, even when a source URL now belongs to an archived or trashed item. The intelligence service's excluded-URL filter applies to new search results, not these cached research inputs. This permits excluded content to return through an indirect prompt path.

Reproduction:
1. Save an active web item A at URL U, with no analysis or inferred interests.
2. Run independent research whose search result includes U. Its input IDs remain empty because it has no origin, topic, or preference ancestors.
3. Archive or trash A.
4. Analyze another item whose terms match that research. `_knowledgeSources` still offers the research report and the excerpt from U because `_reusable([])` is true. A topic previously populated from that research can likewise reuse its overview.

Fix: Record the matching local item IDs when research sources enter the run, retaining their union in every saved snapshot and all dependent outputs. Also account for cached sources whose URLs become associated with excluded library items later; apply that eligibility rule consistently to saved runs, topic previous reports, and derived outputs.

Confidence: high; confirmed by the input construction, progress persistence, and reusable-source code paths. This reproduction has not been executed by this reviewer.

### [HIGH] In-flight image writes attach results after a lifecycle change

File: `lib/core/app_controller.dart:480`–`:496`.

Issue: `_fetch` checks the lifecycle revision after downloading, then awaits image decoding and `store.writeAsset` without checking again before `item.assets.add`. If an item is archived or trashed during either await, the late asset is still attached. The following guard throws, but the cancellation handler saves the already-mutated item, making the late attachment durable.

Reproduction: Start webpage capture with one valid image. Hold `LocalStore.writeAsset` after it starts; archive the item; release the write. The archived item's asset list gains the image and the cancellation handler persists it. The same window exists during asynchronous codec work.

Fix: Check revision after decoding, await the asset into a local variable, check revision again, then attach it. The existing idle cleanup can remove a completed but unreferenced write.

Confidence: high; the mutation is directly after an unguarded await. This reproduction has not been executed by this reviewer.

### [MEDIUM] Shortening trash retention does not apply the promised immediate expiry

File: `lib/core/app_controller.dart:356`–`:360`; user-facing promise at `lib/ui/settings_page.dart:288`.

Issue: `setTrashRetentionDays` saves the new policy without calling `cleanupExpiredTrash`. The settings confirmation promises immediate permanent deletion. Newly expired items and their RSS pointers remain until a later startup, resume, tracking, or backup maintenance pass; they can still be restored in the meantime.

Reproduction: Under the seven-day policy, create an item trashed four days ago with an RSS pointer. Set retention to three days. Both remain present, and `restoreItems` can clear the trash timestamp before any maintenance pass.

Fix: Run expiry cleanup as part of committing the shorter retention policy, preserving the existing purge order and idle attachment cleanup.

Confidence: high; the method has no cleanup call and the UI makes the immediate-effect promise explicitly.

### [MEDIUM] A cancelled old task overwrites the status of its successful retry

File: `lib/core/app_controller.dart:764`–`:769` (analysis cancellation handler); the fetch and synthesis cancellation handlers have the same shared-state pattern.

Issue: `_invalidateTasks` marks in-flight items interrupted immediately, permitting a retry. When the original request eventually finishes, its cancellation handler unconditionally writes `interrupted` and an error to the shared item or topic, even if a newer task has already completed successfully. Result content remains, but the latest successful work is presented as interrupted.

Reproduction: Start analyzing B with its first model response held. Archive unrelated A, which invalidates B and makes it retryable. Analyze B again and complete the second response, producing a ready item. Release the first response: its stale revision triggers the cancellation handler, changing B back to interrupted with an error despite the successful newer result.

Fix: Associate status updates with the operation that owns them, or allow `_invalidateTasks` to set stale-task status and avoid later cancellation writes after a revision change. Apply the same protection to error handlers that can return after a retry starts.

Confidence: high; both requests retain the same mutable entity while their revisions differ. This reproduction has not been executed by this reviewer.

## Inspected paths without additional findings

Nullable input ancestry stays distinct from model-selected citations; unknown legacy outputs remain readable but fail prompt reuse. Analysis and synthesis paths sanitize cached source copies and collect their ancestry. Confirmed interests have a separate persisted field. Restoring a trashed archived item retains its archive timestamp. Permanent removal clears RSS pointers while preserving historical input IDs. Store backup and restore remove expired originals using the original trash timestamp, preserve device service configuration, disable imported debug logging and tracking authorization, and clean only managed unreferenced attachments.

## Speculative concerns

None reported as defects. The findings above are concrete code-path issues; runtime reproduction remains part of the parent integration/verification work. Concurrent edits after this review may change line numbers or resolve the findings.

## Review Summary

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0 | pass |
| HIGH | 2 | warn |
| MEDIUM | 2 | info |
| LOW | 0 | pass |

Verdict: WARNING — resolve the two HIGH issues before delivery; also apply retention changes immediately and prevent stale task status updates.

## Scoped resolution review — 2026-09-22

Re-read only the four reported findings and their fixes. Reviewed the added regression tests in `test/lifecycle_controller_test.dart` and the supplied `docs/v2/full-tests.log`, which ends with **130 tests passed**. No suite was rerun by this reviewer.

| Original finding | Resolution |
|---|---|
| Known library URL omitted from research ancestry | Addressed for the reported reproduction. `_researchUrlInputs` contributes matching IDs at progress and final checkpoints, `_reusableRun` checks current matching URLs, and `_sourceInputs` carries matching IDs into downstream analyses/syntheses. The new test verifies direct and indirect exclusion after archive. |
| Late image attachment | Addressed. `_fetch` checks revision after codec work and after the file write, before attaching. The delayed-write regression also verifies orphan file cleanup. |
| Immediate retention expiry | Addressed. `setTrashRetentionDays` awaits `cleanupExpiredTrash`; the new regression verifies the four-day-old item disappears after selecting three days. |
| Stale task overwrites retry status | Partially addressed. Cancellation handlers no longer mutate the shared entity, and the successful-old-response regression passes. Ordinary late errors still reach unguarded generic catch handlers. |

### Remaining [MEDIUM] portion of the retry-status finding

At `lib/core/app_controller.dart:818`, the generic analysis catch still assigns `item.status = 'error'` without checking the operation revision. Fetch (`:543`) and synthesis (`:1034`) retain the same pattern. Repeat the existing retry regression, but complete the original response with `old.completeError(TimeoutException('late timeout'))` after the retry succeeds. The old request now overwrites the new ready status with error. Production request/response timeouts propagate through the intelligence and diagnostics layers as ordinary exceptions, so this is not limited to fake services.

Check the revision before any generic catch mutates shared entity status/error, or skip those mutations once the operation is invalid. Add the late-error variant to the existing retry regression.

### Review Summary

| Severity | Open count | Status |
|----------|------------|--------|
| CRITICAL | 0 | pass |
| HIGH | 0 | pass |
| MEDIUM | 1 | info |
| LOW | 0 | pass |

Verdict: APPROVE under the severity policy, with one concrete MEDIUM retry-status issue remaining. The original three completed fixes match their regression coverage; the fourth needs the ordinary-error branch protected before it is fully resolved.

## Final scoped confirmation — 2026-09-22

All four original findings are now resolved. The generic catches in `_fetch`, `analyze`, and `synthesizeTopic` check `if (!_valid(revision)) return` before changing the shared entity. Thus a stale ordinary failure is logged for its own task without overwriting a newer task's status or result.

The added `late failure from old analysis does not overwrite newer successful retry state` regression exercises the reported timeout sequence. `docs/v2/late-error-red.log` confirms it failed before the fix with expected `ready` versus actual `error`; the latest `docs/v2/full-tests.log` reports **131 tests passed**, and `docs/v2/analyze.log` reports **No issues found**. These existing artifacts were inspected; no suite was rerun by this reviewer.

Also reviewed `test_driver/device_screenshots.dart` as requested. Its basename allowlist excludes separators and traversal components before constructing the output path. File writes are awaited and failures propagate. The driver checks a minimum eight-byte length and the four-byte PNG marker; the device test separately asserts the complete eight-byte PNG signature before accepting each screenshot. `docs/v2/device-screenshots.log` records a successful driver/device run. No material defect found in this bounded driver review.

### Review Summary

| Severity | Open count | Status |
|----------|------------|--------|
| CRITICAL | 0 | pass |
| HIGH | 0 | pass |
| MEDIUM | 0 | pass |
| LOW | 0 | pass |

Verdict: APPROVE — the four reported lifecycle/provenance findings are resolved, with regression evidence; no additional finding in the requested screenshot-driver slice.

## Research timeline addendum — 2026-09-22

Scoped review of the new `DiagnosticScope.step` helper, the two research call wrappers, and `research records diagnostic timeline steps for every remote call` in `test/intelligence_test.dart`.

No findings. The helper delegates through the current zone's store and executes the body directly when no diagnostic context exists. Search and model calls retain their existing authorization checks, budgets, payloads, and result handling. The wrappers use the existing step implementation, preserving zone-local call attribution, error propagation, and cancellation checks. The regression exercises two search/model rounds and asserts four successful steps, their order, call-to-step IDs, and completion timestamps. The parent reports 32 scoped tests passed and clean analysis; this reviewer inspected the test and code without rerunning tests.

### Review Summary

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0 | pass |
| HIGH | 0 | pass |
| MEDIUM | 0 | pass |
| LOW | 0 | pass |

Verdict: APPROVE — no regression found in the research timeline patch. Citation presentation remains outside this addendum pending its readiness notice.

## Citation presentation addendum — 2026-09-22

Scoped review of the new citation formatter, shared source-list presentation, reader call sites, and regression in `test/detail_updates_test.dart`. The final correction removing the generated-ID heuristic is present: only declared `sourceIds` are remapped, and `[API]` / `[documentation]` remain ordinary text. Reader navigation still uses original IDs, and research confirmation submits the original question rather than its displayed citation text.

### [MEDIUM] Shared source-list numbering breaks the topic overview's citation mapping

File: `lib/ui/common.dart:139`–`:151`; direct caller `lib/ui/research_detail.dart:78`.

`SourceList` now hides IDs and numbers entries for all callers, but `TopicDetailPage` still displays its overview with original `[source-id]` markers. An overview `结论 [source-1]` with `sourceIds: ['source-1']` therefore has a bibliography showing `来源文章 / 引用 [1]` without any matching `source-1` marker. With several sources, the user cannot reliably match citations to rows.

Make numeric source presentation opt-in for the article reader, preserving the topic's existing matching markers, or apply the same declared-source mapping to its overview. This is a direct regression in another existing caller of the changed shared widget, not a broader topic UI audit.

The parent reports 13 scoped tests passed and clean analysis before the declared-only correction. This reviewer inspected current source and test changes; no tests were rerun.

### Review Summary

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0 | pass |
| HIGH | 0 | pass |
| MEDIUM | 1 | info |
| LOW | 0 | pass |

Verdict: APPROVE under the severity policy, with the shared source-list mismatch requiring correction before the citation polish is complete. Prior lifecycle and research-timeline approvals remain unchanged.

## Citation resolution — 2026-09-22

The shared source-list mismatch is resolved. `_OverviewCard` now passes `topic.overview`, the same `topic.sourceIds` ordering, and `controller.sourceLabel` through `readerCitationText`, matching the bibliography's numeric markers. The formatter now recognizes short declared IDs such as `r1`, while retaining the declared-source membership check that preserves ordinary bracketed text. The topic regression now verifies its original `[r1]` appears as `[1]`; article coverage continues to check unresolved declared citations and unchanged `[API]` / `[documentation]` text. No additional finding in this exact patch scope.

The parent reports the targeted article/topic tests passed and the analyzer is clean. This reviewer inspected the final code and regression assertions without rerunning tests.

### Review Summary

| Severity | Open count | Status |
|----------|------------|--------|
| CRITICAL | 0 | pass |
| HIGH | 0 | pass |
| MEDIUM | 0 | pass |
| LOW | 0 | pass |

Verdict: APPROVE — citation presentation finding closed. All prior scoped approvals remain valid.
