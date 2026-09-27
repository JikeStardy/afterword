# 有下文 · Afterword V3 Android Device Checks

These checks cover the native foreground-service path that cannot be proven by
unit tests alone: submit, background/home, lock screen, resume, and notification
click routing.

## Prerequisites

- A physical Android device, or an emulator that can actually boot on the host.
- The fixture server used by `integration_test/device_flow_test.dart` running on
  the host at `http://127.0.0.1:18765`.
- Run `adb -s <device-id> reverse tcp:18765 tcp:18765` for both emulator and physical device; retain the localhost fixture URL.
- Notification permission should be tested twice: allowed and denied.

Current local host note: the installed Android 36 arm64 image can create an AVD,
but the emulator binary exits before boot with:

```text
Incompatible processor. This Qt build requires the following features:
    neon
```

So this environment can compile/analyze the Android code, but cannot complete
the device runtime checks without another device/emulator host.

## Long Text And PDF Background Flow

Start the test:

```sh
flutter test integration_test/background_flow_test.dart \
  -d <device-id> \
  --dart-define=READLATER_FIXTURE_BASE=http://127.0.0.1:18765
```

The test delays each model stage by 15 seconds using a test-only adapter. It asserts that the app is in the background after each submission marker, and waits for foreground before submitting the PDF. The actual HTTP, storage and PDF renderer still execute.

Watch for markers:

```sh
adb -s <device-id> logcat -s flutter
```

When logcat prints `READLATER_V3_BACKGROUND_FLOW` with
`"stage":"long-submitted"`, send the app home, wait, lock the screen, wait, then
unlock and bring the app back:

```sh
adb -s <device-id> shell input keyevent HOME
sleep 10
adb -s <device-id> shell input keyevent 26
sleep 60
adb -s <device-id> shell input keyevent 26
adb -s <device-id> shell monkey -p app.readlater.readlater 1
```

Repeat the same sequence when the marker stage is `"pdf-submitted"`.

Expected result:

- The integration test completes successfully.
- The running foreground notification stays present while work is active.
- The long text item reaches `ready`.
- The PDF item reaches `ready`.
- The final markers include `"long-complete"` and `"pdf-complete"`.

## Notification Routing

With notifications allowed:

1. Submit a text item and background the app.
2. Wait for the result notification.
3. Tap the notification.

Expected result: the app cold-starts or resumes and opens the corresponding
item/result. For the daily digest notification, tapping the notification should
open the Today tab even when the notification has `entityType=today` and an
empty `entityId`.

For multiple results:

1. Complete two tasks without dismissing their result notifications.
2. Verify they appear as grouped children with one summary; a child opens its
   result and the summary opens Today.
3. Dismiss the result notifications, then complete one new task.
4. Verify no stale historical count appears. Repeat after process death, and
   include a failed task to check that the summary says results, not successes.

With notifications denied:

1. Deny Android notification permission.
2. Submit a text item.

Expected result: analysis still runs; native `publishNotification` returns
`false`, and Dart must leave the outbox entry undelivered instead of marking it
sent.

## Share Cancel Flow

1. Share a large PDF or image batch into 有下文 · Afterword.
2. While the native copy foreground notification is active, tap Cancel.
3. Reopen 有下文 · Afterword.

Expected result:

- Copied files are retained in the private share inbox.
- `pendingShares()` exposes `cancelled: true`.
- Dart imports the raw material as retryable/manual-only and does not enqueue
  automatic analysis for that cancelled share.
- The native foreground-service lease is released only after Dart acknowledges
  the share.

## Digest Scheduler

1. Enable daily digest.
2. Record the pending JobScheduler job.
3. Force-stop neither app nor device; let JobScheduler cold-start the process.

Expected result:

- `Application.onCreate` does not cancel and replan an already pending due job.
- `configureDigest` with unchanged settings preserves the existing pending job.
- `finishDigest` schedules the next digest after the current job completes.
- A headless digest run stays in `digestOnly` mode until a real user Activity or
  share path promotes the runtime to interactive.
