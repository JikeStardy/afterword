# Task 2 — diagnostic storage and request instrumentation

Implemented in `lib/core/diagnostics.dart`, `lib/services/intelligence_service.dart`, `test/diagnostics_test.dart`, and the existing `test/intelligence_test.dart`. No dependencies added; existing public service method signatures and override fakes remain compatible.

## Behavior

- Independent SQLite task log with Zone-scoped task/step/call association, parent task IDs, entity/input IDs, timestamps, statuses, errors, model, HTTP status, request ID, and actual provider usage. Missing usage stays null; no inferred token counts or hidden model reasoning are represented.
- Ordinary records expire after 30 days and detailed request/response payloads after 7 days. Logical persisted JSON is capped at 50 MiB by deleting oldest tasks. SQLite secure deletion and VACUUM reclaim expired/cleared space. Physical SQLite file overhead is additional to the logical limit.
- Debug payload capture defaults off on each store construction. A call must start with capture enabled; disabling it before completion removes that call's captured request as well. Each request/response is capped at 256 KiB of UTF-8 with a truncation flag and marker.
- Recursive sensitive-key filtering handles headers, cookies, prefixed API keys, passwords, tokens and credentials. Known model/search keys, including JSON-escaped and URL-encoded echoes, and URI user information are redacted. Image data URLs retain MIME metadata with bytes omitted. Malformed response JSON cannot leak raw payload through ordinary exception metadata. Malformed/truncated sensitive assignments also receive text redaction.
- Logging write/read/capture failures set `lastError` while business operations continue. Interrupted tasks/steps/calls are repaired on reopen. Clearing invalidates active tasks' future writes; purging an item's payloads also suppresses late response reinsertion.
- Guards compose parent and child authorization and run before sending, after receiving, during streaming, before parsing, and before applying or continuing research. Cancellation reports that already-sent requests cannot be withdrawn. Scoped excluded URLs filter both existing research evidence and new search results after fragment/trailing-slash normalization.

## Stable integration API

`DiagnosticStore(path, {clock, maxBytes, payloadLimitBytes})` extends ChangeNotifier. Public fields/getters: `debugEnabled`, `lastError`, `tasks`, `logicalBytes`; methods: `task(id)`, `runTask(...)`, `step(...)`, `failCurrent(message)`, `addInputIds(ids)`, `prune()`, `clear()`, `purgeItemPayloads(ids)`, `exportLogs({taskId})`, `close()`.

`runTask` includes optional `excludedUrls`, composing it with the parent's set. Cancellation type is `DiagnosticCancelled`. `DiagnosticScope` supplies `ensureAllowed`, `excludedUrls`, `registerCredentials`, and `sanitizeError`. Task statuses are `running`, `succeeded`, `failed`, `cancelled`, or `interrupted`. Model response parse errors and caught network errors cannot turn their task into success.

## Verification evidence

Initial diagnostics tests were written before the implementation. The first compile run failed because `DiagnosticStore`, `DiagnosticScope`, and `DiagnosticCancelled` did not exist (`/private/tmp/v2-diagnostics-red.log`). Additional regression tests first exposed four failures—caught request marked success, malformed JSON body leaking through errors, malformed secret assignments not redacted—and passed after fixes (`/private/tmp/v2-diagnostics-security-red.log`). A disk-byte fixture additionally exposed a prefixed `x-api-key` leak before that filter was repaired (`/private/tmp/v2-diagnostics-edge-red.log`).

Exact passing commands, run from the project directory:

```sh
XDG_CONFIG_HOME=/private/tmp/readlater-flutter-config CI=true /Users/tomato/Documents/Codex/2026-09-21/wo-xi/work/toolchains/flutter/bin/flutter test test/diagnostics_test.dart test/intelligence_test.dart
XDG_CONFIG_HOME=/private/tmp/readlater-flutter-config /Users/tomato/Documents/Codex/2026-09-21/wo-xi/work/toolchains/flutter/bin/dart analyze lib/core/diagnostics.dart lib/services/intelligence_service.dart test/diagnostics_test.dart test/intelligence_test.dart
```

Results after independent review fixes: **31 tests passed**, analyzer **No issues found**. Flutter tests required the approved sandbox escalation for the local 127.0.0.1 test harness socket. Fixtures exercised HTTP success/failure, missing/actual usage, bad provider/model JSON, timeout, oversize, guards, URL exclusion, concurrent/nested tasks, retention/capacity, interrupted recovery, opt-in toggles, in-flight purge, clearing, storage failure, and raw SQLite-byte redaction.

Independent review follow-up reproduced two failing cases with the same test command plus `--name 'raw cookie|optional numeric'` (`/private/tmp/v2-diagnostics-review-red.log`): raw cookie headers retained later semicolon-separated values, and numeric optional provider response IDs threw a type error. The header regression also covers Basic/Digest authorization, proxy authorization, Set-Cookie, and folded continuation lines. Those complete values are now redacted in both payloads and errors. Numeric IDs are represented as strings; structured optional IDs are omitted without failing otherwise valid completions. Both added tests and the full scoped suite passed after the changes.

Research timeline follow-up added a regression for the developer log case where a completed research task had four remote calls but no step timeline. The first run failed with `task.steps` length `0`; after adding Zone-scoped research steps, the scoped diagnostics/intelligence suite reports **32 tests passed**, and analyzer reports **No issues found**. Each research search/model-comparison call now stores the `stepId` of its corresponding timeline step.

## Integration limits

- No external provider credentials were used. These are deterministic HTTP/SQLite fixtures, not live-provider acceptance.
- Whole-app controller/UI tests, Android build, emulator inspection, and independent review belong to the parent integration lane.
- SQLite synchronous pruning/VACUUM is bounded by the 50 MiB logical cap but may briefly occupy the UI isolate during a large cleanup. The physical SQLite minimum and index overhead are not included in that cap.
- Redaction deliberately suppresses sensitive data and deeply nested content (beyond 64 levels); it is not an encrypted-at-rest database.
