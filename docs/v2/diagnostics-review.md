# Diagnostics implementation review

Scope: `lib/core/diagnostics.dart` and changes to `lib/services/intelligence_service.dart`, against Task 2 in `docs/superpowers/plans/2026-09-22-v2.md` and `../readlater-v1-baseline`. Controller integration is outside this review. No implementation files changed.

[CRITICAL] Plain-text header redaction leaves authentication credentials behind

File: `lib/core/diagnostics.dart:625–630`

Issue: The non-JSON assignment sanitizer stops an unquoted value at whitespace or a semicolon. Consequently, raw HTTP header text retains subsequent cookies and the credential after an authentication scheme. These strings can appear in captured provider responses, model content, or exception text; `_payload()` / `_write()` persist the partially redacted result. Opting into debug payloads does not permit persisting cookies or authentication headers under Task 2.

Reproduction: Run the actual sanitizer methods extracted from this file with the following inputs. The standalone Dart probe at `/private/tmp/readlater-diagnostics-review-probe.dart` produced:

```text
Input:  Cookie: theme=light; session=private-session
Output: Cookie: "[REDACTED]"; session=private-session

Input:  Authorization: Basic dXNlcjpwYXNz
Output: Authorization: "[REDACTED]" dXNlcjpwYXNz
```

Calling `DiagnosticScope.finishCall(call, response: <either input>)` inside a debug-enabled task therefore records those surviving credentials. Repeated sanitization does not remove them because their sensitive header prefix has already been replaced.

Fix: Before generic assignment filtering, redact the entire value of recognized raw authorization/cookie header lines, including auth schemes and all semicolon-separated cookies. Add regression coverage for both plain-text and JSON-embedded header strings and inspect exported logs/raw SQLite bytes for their absence.

[MEDIUM] Optional response ID metadata can reject a successful business response

File: `lib/services/intelligence_service.dart:112`

Issue: `requestId ??= result['id'] as String?` throws for a non-string response ID when no recognized request-ID header exists. `_post()` handles both configurable model and search endpoints. Its previous implementation ignored `id`, so a successful search response such as `{"id":123,"results":[]}` or a completion containing valid `choices` and an integer `id` now fails solely because diagnostics metadata has an unexpected type. In research this marks the run failed; in completion it throws before parsing the valid choices.

Reproduction: Have a MockClient return HTTP 200 with `{"id":123,"choices":[{"message":{"content":"{\"answer\":\"ok\"}"}}]}` and no request-ID header, then call `complete()`. The cast throws before the transform at line 114. This also happens without a diagnostics Zone.

Fix: Read optional metadata defensively (accept a string, explicitly stringify supported scalar IDs, or leave it absent), without letting diagnostic metadata validation fail the response. Add a regression fixture proving valid completion/search results survive unexpected optional metadata types.

## Verified paths and limits

- Active task payload purge is enforced again on every write using `_purgedIds`; late responses cannot persist the deleted item's request/response. `clear()` invalidates existing context generations.
- Parent/child authorization guards compose, and the service checks them before sending, after headers/body reception, before parsing, and before continuing research.
- Scoped excluded URLs filter existing evidence and incoming search results; canonicalization removes fragments and trailing slashes.
- Default capture is off, capture permission is recorded per call, disabling capture before completion removes that call's request, and expiry/capacity pruning rewrites or deletes persisted rows with space reclamation.
- Ordinary SQLite failures are caught by `_safe`; the existing report records 29 passing tests and a clean targeted analyzer run. This review did not rerun that suite. The redaction finding was independently reproduced with a small source-extracted Dart probe; the metadata finding follows directly from the introduced cast and its call path.
- The checkout has no Git repository, so staged/working-tree diff commands could not be used; the service was compared directly with the supplied baseline.

## Review Summary

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 1 | block |
| HIGH | 0 | pass |
| MEDIUM | 1 | info |
| LOW | 0 | pass |

Verdict: BLOCK — raw header credential redaction must be fixed before merge; optional metadata should not break otherwise valid requests.

## Scoped follow-up review — both findings addressed

Re-reviewed only the two fixes and their added regression tests. This section supersedes the initial blocking verdict above.

- **Credential-header finding: addressed.** `lib/core/diagnostics.dart:623–632` now removes the entire raw Cookie, Set-Cookie, Authorization, or Proxy-Authorization value, including semicolon-separated cookies, spaces in Basic/Digest authentication, and folded continuation lines, before applying generic assignment filtering. Structured JSON is still decoded and recursively sanitized first. The regression in `test/diagnostics_test.dart:396` sends those fixtures through both response payload and error persistence, checks exported logs and raw SQLite bytes for the credential values, and confirms the following ordinary diagnostic line survives. No new actionable regression found in this change.
- **Optional response-ID finding: addressed.** `lib/services/intelligence_service.dart:112–115` accepts string/numeric IDs only, converts supported values to strings, preserves header-ID precedence, and ignores structured IDs. There is no longer a failing cast on optional metadata. `test/intelligence_test.dart:537` verifies valid completion output and successful task status for integer, map, and list IDs, together with the expected recorded ID. The common `_post()` fix also applies to search responses. No new actionable regression found in this change.

Evidence: inspected the current functions and complete added tests; inspected `/private/tmp/v2-diagnostics-review-red.log`, which contains the original credential-leak assertion and integer-to-String cast failure. The implementation report documents both new regressions passing, all **31 scoped tests passing**, and a clean targeted analyzer run. As requested, this follow-up did not rerun the suite or edit application code. This approval covers these two fixes, not a new whole-application review.

## Review Summary

| Severity | Open Count | Status |
|----------|------------|--------|
| CRITICAL | 0 | pass |
| HIGH | 0 | pass |
| MEDIUM | 0 | pass |
| LOW | 0 | pass |

Verdict: APPROVE — both original findings are addressed; no new actionable regression found in the scoped fixes.
