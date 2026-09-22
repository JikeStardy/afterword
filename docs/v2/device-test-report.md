# V2 Android integration test extension

Only `integration_test/device_flow_test.dart` was modified. No dependency, controller, service or UI edits were made in this lane.

The existing real Android SQLite, local HTTP, native PDF rendering, image import, RSS and four-call research pipeline now checks:

- Default diagnostic calls contain status/model metadata without request/response bodies. Enabling debug records the subsequent actual fixture request and response; earlier calls remain metadata only. Export contains the request and excludes `fixture-key`; missing fixture usage remains null.
- The research task has the persisted run ID as its `entityId`. The test opens the production entity-filtered developer route, taps its real task row and verifies the detail route task ID and displayed run association.
- Archive blocks analysis before another HTTP model request, preserves the entire existing analysis, and survives trash/restore with the original archive timestamp.
- Purge deletes a managed image file, removes the item, scrubs related detailed logs, and preserves the old research report and exact input ancestry.
- Backup, restore and SQLite reopen preserve archived and unexpired-trash timestamps, original attachment bytes and research ancestry. Restore disables debug logging.

Screenshots use the installed `IntegrationTestWidgetsFlutterBinding` implementation. It requires `convertFlutterSurfaceToImage()` once on Android, followed by a pumped frame before `takeScreenshot()`. The installed callback registers image-surface reversion automatically during teardown. Returned bytes are checked for a PNG signature and written under `getApplicationSupportDirectory()/v2-screens`:

- `library.png`
- `reader-analysis.png`
- `developer-task.png`
- `restored-archives.png`
- `debug-task-redacted.json` (actual redacted diagnostic export)
- `evidence.json` (task/entity IDs, lifecycle timestamps, preserved input IDs and restored count)

All domain data lives in a unique `integration-<timestamp>` directory and a separate restored directory. The test never opens the normal app database. At completion it disposes the test controller and leaves the saved genuine archive screenshot visible, avoiding the production app's periodic resume timer.

Validation status: source inspected against the current controller/UI and installed screenshot API, and Dart formatting completed. Per the parent's instruction, no test, Android build or device command was run by this lane; the parent owns device execution and screenshot inspection. The HTTP server is the repository's deterministic local fixture, not an external model provider.
