# V2 data and backup implementation

Changed `lib/core/models.dart`, `lib/core/store.dart`, and added `test/lifecycle_store_test.dart`.

- Added archive/trash timestamps and derived lifecycle getters. Both timestamps survive round trips so restoring a trashed archive keeps its archived state.
- Analysis, topic, and research ancestry is nullable and separate from citations. Missing legacy ancestry remains unknown; empty ancestry remains explicitly empty.
- Schema output is version 2; versions 1 and 2 load, unknown versions fail. New settings support 3/7-day retention, debug logging, and confirmed interests.
- Backup excludes expired trash without mutating the committed snapshot. Restore expires trash before writing new attachments or committing, clears expired RSS saved pointers, and retains historical source/input IDs. Remaining timestamps are unchanged.
- Restore keeps device model/search configuration (explicit settings or the current committed settings), disables debug logging, and continues disabling imported tracking grants.
- `cleanUnusedAssets(AppData)` synchronously removes unreferenced regular files with managed names directly under assets. It skips links, directories, arbitrary filenames and referenced assets; filesystem failures can be retried. The controller must invoke it only when attachment imports and snapshot saves are idle.
- Added optional `LocalStore(now: ...)` clock injection for deterministic expiry boundary tests.

Verification: new lifecycle tests first failed because the requested APIs did not exist (`/tmp/readlater-data-red.log`). The first model/store/lifecycle run passed 15 tests. A separate regression then exposed restore resetting the current device endpoint to the default when no settings argument was provided; its expected/actual mismatch was observed before fixing the fallback to the committed settings. Targeted `dart analyze lib/core/models.dart lib/core/store.dart test/lifecycle_store_test.dart` returned “No issues found!” after the fix. Final test verification is reported below and by the parent integration pass.

Final targeted run: `flutter test test/models_test.dart test/store_test.dart test/lifecycle_store_test.dart` passed all **16 tests** (exit 0), including the device-settings regression.

Scope boundaries: controller owns lifecycle actions, periodic expiry, and coordinating cleanup with in-flight attachment writes. This lane does not rewrite historical provenance or infer old ancestry. No dependencies were added.
