import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/diagnostics.dart';

void main() {
  late Directory root;
  late DiagnosticStore store;
  setUp(() {
    root = Directory.systemTemp.createTempSync('diagnostics');
    store = DiagnosticStore('${root.path}/logs.sqlite');
  });
  tearDown(() {
    store.close();
    root.deleteSync(recursive: true);
  });
  test(
    'concurrent and nested tasks retain separate steps and failed status',
    () async {
      final barrier = Completer<void>();
      final first = store.runTask(
        type: 'analysis',
        title: 'first',
        body: () async {
          await store.step('first-step', () async {
            await barrier.future;
          });
          await store.runTask(
            type: 'child',
            title: 'nested',
            body: () async {
              store.failCurrent('caught failure');
            },
          );
        },
      );
      await store.runTask(
        type: 'save',
        title: 'second',
        body: () async {
          await store.step('second-step', () async {});
        },
      );
      barrier.complete();
      await first;
      final tasks = store.tasks;
      expect(
        tasks.singleWhere((t) => t.title == 'first').steps.single.label,
        'first-step',
      );
      expect(
        tasks.singleWhere((t) => t.title == 'second').steps.single.label,
        'second-step',
      );
      expect(tasks.singleWhere((t) => t.title == 'nested').status, 'failed');
      expect(
        tasks.singleWhere((t) => t.title == 'nested').parentId,
        tasks.singleWhere((t) => t.title == 'first').id,
      );
    },
  );
  test('redacts nested secrets, known credentials and image bytes in persisted logs', () async {
    store.debugEnabled = true;
    await store.runTask(
      type: 'analysis',
      title: 'redaction',
      inputItemIds: ['a'],
      body: () async {
        final call = DiagnosticScope.beginCall(
          endpoint: 'https://example.test',
          model: 'm',
          credential: 'private-value',
          request: {
            'nested': [
              {'api_key': 'unknown-secret'},
            ],
            'image': 'data:image/png;base64,YWJj',
            'text': 'private-value',
          },
        );
        DiagnosticScope.finishCall(
          call,
          response: '{"nested":{"authorization":"Bearer unknown"},"echo":"private-value"}',
          statusCode: 200,
          usage: {'total_tokens': 3},
        );
      },
    );
    final output = utf8.decode(store.exportLogs());
    expect(output, isNot(contains('private-value')));
    expect(output, isNot(contains('unknown-secret')));
    expect(output, isNot(contains('YWJj')));
    expect(output, contains('total_tokens'));
    store.purgeItemPayloads({'a'});
    expect(store.tasks.single.calls.single.request, isNull);
    expect(store.tasks.single.calls.single.response, isNull);
  });
  test('retains ordinary metadata but expires payload after seven days and task after thirty', () async {
    store.close();
    var now = DateTime.utc(2026, 1, 1);
    store = DiagnosticStore('${root.path}/time.sqlite', clock: () => now)
      ..debugEnabled = true;
    await store.runTask(
      type: 'model',
      title: 'retention',
      body: () async {
        final call = DiagnosticScope.beginCall(
          endpoint: 'https://example.test',
          request: {'prompt': 'body'},
          credential: 'key',
        );
        DiagnosticScope.finishCall(call, response: 'result', statusCode: 200);
      },
    );
    now = now.add(const Duration(days: 8));
    store.prune();
    expect(store.tasks.single.calls.single.request, isNull);
    expect(store.tasks.single.calls.single.statusCode, 200);
    now = now.add(const Duration(days: 23));
    store.prune();
    expect(store.tasks, isEmpty);
  });
  test(
    'capacity and per payload byte limit stay bounded with explicit truncation',
    () async {
      store.close();
      store = DiagnosticStore(
        '${root.path}/small.sqlite',
        maxBytes: 5000,
        payloadLimitBytes: 128,
      )..debugEnabled = true;
      for (var i = 0; i < 10; i++) {
        await store.runTask(
          type: 'model',
          title: 'task$i',
          body: () async {
            final call = DiagnosticScope.beginCall(
              endpoint: 'https://example.test',
              request: {'text': '文' * 1000},
              credential: 'key',
            );
            DiagnosticScope.finishCall(
              call,
              response: 'response' * 500,
              statusCode: 200,
            );
          },
        );
      }
      expect(store.logicalBytes, lessThanOrEqualTo(5000));
      expect(store.tasks, isNotEmpty);
      expect(store.tasks.first.calls.single.requestTruncated, isTrue);
      expect(
        utf8.encode(store.tasks.first.calls.single.request!).length,
        lessThanOrEqualTo(128),
      );
    },
  );
  test('guard cancels task and logging failure does not fail business', () async {
    await expectLater(
      store.runTask(
        type: 'analysis',
        title: 'cancel',
        allowed: () => false,
        body: () async {},
      ),
      throwsA(isA<DiagnosticCancelled>()),
    );
    expect(store.tasks.single.status, 'cancelled');
    store.close();
    store = DiagnosticStore('${root.path}/missing/blocked/logs.sqlite');
    // Closing diagnostics must never prevent an otherwise valid business task.
    store.close();
    expect(
      await store.runTask(type: 'save', title: 'saved', body: () async => 42),
      42,
    );
    expect(store.lastError, isNotNull);
  });
  test(
    'interrupted tasks recover and clear prevents active task resurrection',
    () async {
      final ready = Completer<void>(), release = Completer<void>();
      final running = store.runTask(
        type: 'save',
        title: 'interrupted',
        body: () async {
          await store.step('write', () async {
            ready.complete();
            await release.future;
          });
        },
      );
      await ready.future;
      store.close();
      store = DiagnosticStore('${root.path}/logs.sqlite');
      expect(store.tasks.single.status, 'interrupted');
      expect(store.tasks.single.steps.single.status, 'interrupted');
      release.complete();
      await running;
      final gate = Completer<void>();
      final cleared = store.runTask(
        type: 'save',
        title: 'clear active',
        body: () => gate.future,
      );
      store.clear();
      gate.complete();
      await cleared;
      expect(store.tasks, isEmpty);
    },
  );
  test(
    'malformed text and nested encoded content cannot leak sensitive keys',
    () async {
      store.debugEnabled = true;
      await store.runTask(
        type: 'model',
        title: 'malformed',
        body: () async {
          final call = DiagnosticScope.beginCall(
            endpoint: 'https://example.test?api_key=secret-url',
            request: {'prompt': 'normal'},
            credential: 'live-key',
          );
          DiagnosticScope.finishCall(
            call,
            response: '{"api_key":"unknown-truncated-secret", "data":',
            statusCode: 500,
          );
        },
      );
      final logs = utf8.decode(store.exportLogs());
      expect(logs, isNot(contains('unknown-truncated-secret')));
      expect(logs, isNot(contains('secret-url')));
    },
  );
  test('caught network failure still marks task failed', () async {
    await store.runTask(
      type: 'model',
      title: 'caught',
      body: () async {
        final call = DiagnosticScope.beginCall(
          endpoint: 'https://example.test',
          request: {},
          credential: 'key',
        );
        DiagnosticScope.finishCall(
          call,
          error: StateError('HTTP 500'),
          statusCode: 500,
        );
      },
    );
    expect(store.tasks.single.status, 'failed');
  });
  test(
    'in flight purge and capture toggles cannot resurrect detailed content',
    () async {
      store.debugEnabled = true;
      await store.runTask(
        type: 'model',
        title: 'purge',
        inputItemIds: ['a'],
        body: () async {
          final call = DiagnosticScope.beginCall(
            endpoint: 'https://example.test',
            request: {'text': 'private'},
            credential: 'key',
          );
          store.purgeItemPayloads({'a'});
          DiagnosticScope.finishCall(
            call,
            response: 'late private response',
            statusCode: 200,
          );
        },
      );
      expect(store.tasks.single.calls.single.response, isNull);
      store.clear();
      store.debugEnabled = false;
      await store.runTask(
        type: 'model',
        title: 'toggle',
        body: () async {
          final call = DiagnosticScope.beginCall(
            endpoint: 'https://example.test',
            request: {'text': 'private'},
            credential: 'key',
          );
          store.debugEnabled = true;
          DiagnosticScope.finishCall(
            call,
            response: 'should remain absent',
            statusCode: 200,
          );
        },
      );
      expect(store.tasks.single.calls.single.response, isNull);
      store.clear();
      await store.runTask(
        type: 'model',
        title: 'disable',
        body: () async {
          final call = DiagnosticScope.beginCall(
            endpoint: 'https://example.test',
            request: {'text': 'private'},
            credential: 'key',
          );
          store.debugEnabled = false;
          DiagnosticScope.finishCall(
            call,
            response: 'should remain absent',
            statusCode: 200,
          );
        },
      );
      expect(store.tasks.single.calls.single.request, isNull);
    },
  );
  test('nested scope composes parent guard and URL exclusions', () async {
    var allowed = true;
    await expectLater(
      store.runTask(
        type: 'parent',
        title: 'parent',
        allowed: () => allowed,
        excludedUrls: {'https://example.test/a'},
        body: () async {
          await store.runTask(
            type: 'child',
            title: 'child',
            allowed: () => true,
            excludedUrls: {'https://example.test/b'},
            body: () async {
              expect(DiagnosticScope.excludedUrls, {
                'https://example.test/a',
                'https://example.test/b',
              });
              allowed = false;
              DiagnosticScope.ensureAllowed();
            },
          );
        },
      ),
      throwsA(isA<DiagnosticCancelled>()),
    );
    expect(store.tasks.every((task) => task.status == 'cancelled'), isTrue);
  });
  test('file storage redacts headers and encoded credentials and resets debug on reopen', () async {
    store.debugEnabled = true;
    await store.runTask(
      type: 'model',
      title: 'storage',
      body: () async {
        final call = DiagnosticScope.beginCall(
          endpoint: 'https://user:password@example.test',
          request: {
            'nested': {
              'x-api-key': 'unknown-header',
              'client_secret': 'unknown-client',
              'Cookie': 'session=unknown-cookie',
            },
            'prompt': 'value',
          },
          credential: 'actual/key',
        );
        DiagnosticScope.finishCall(
          call,
          response: 'echo actual%2Fkey',
          statusCode: 200,
        );
      },
    );
    store.close();
    store = DiagnosticStore('${root.path}/logs.sqlite');
    final bytes = File('${root.path}/logs.sqlite').readAsBytesSync();
    final raw = latin1.decode(bytes);
    expect(store.debugEnabled, isFalse);
    for (final secret in [
      'unknown-header',
      'unknown-client',
      'unknown-cookie',
      'actual%2Fkey',
      'user:password',
    ]) {
      expect(
        raw.contains(secret),
        isFalse,
        reason: 'Persisted fixture: $secret',
      );
    }
  });
  test(
    'raw cookie and authorization headers redact their entire values',
    () async {
      store.debugEnabled = true;
      const headers =
          'Cookie: theme=light; session=private-session; login=private-login\n'
          'Set-Cookie: sid=private-sid; Path=/; HttpOnly\n'
          'Authorization: Basic dXNlcjpwYXNz\n'
          'Proxy-Authorization: Digest username="private-user", response="private-digest"\n'
          'Cookie: first=public;\n continuation=private-folded\n'
          'ordinary diagnostic line';
      await store.runTask(
        type: 'model',
        title: 'raw headers',
        body: () async {
          final call = DiagnosticScope.beginCall(
            endpoint: 'https://example.test',
            request: {},
            credential: 'actual-key',
          );
          DiagnosticScope.finishCall(
            call,
            response: headers,
            statusCode: 401,
            error: StateError(headers),
          );
        },
      );
      final exported = utf8.decode(store.exportLogs());
      final raw = latin1.decode(
        File('${root.path}/logs.sqlite').readAsBytesSync(),
      );
      for (final secret in [
        'private-session',
        'private-login',
        'private-sid',
        'dXNlcjpwYXNz',
        'private-user',
        'private-digest',
        'private-folded',
      ]) {
        expect(
          exported.contains(secret),
          isFalse,
          reason: 'Export fixture: $secret',
        );
        expect(
          raw.contains(secret),
          isFalse,
          reason: 'Persisted fixture: $secret',
        );
      }
      expect(exported, contains('ordinary diagnostic line'));
    },
  );
}
