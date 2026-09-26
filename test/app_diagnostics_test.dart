import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/diagnostics.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory root;
  late String databasePath;
  late DiagnosticStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('app-diagnostics');
    databasePath = '${root.path}/diagnostics.sqlite';
    store = DiagnosticStore(databasePath);
  });

  tearDown(() {
    store.close();
    root.deleteSync(recursive: true);
  });

  test('starts each process session at INFO while retaining stored events', () {
    expect(store.level, DiagnosticLevel.info);
    expect(store.debugEnabled, isFalse);

    store.setLevel(DiagnosticLevel.debug);
    final session = store.sessionId;

    store.close();
    store = DiagnosticStore(databasePath);

    expect(store.level, DiagnosticLevel.info);
    expect(store.debugEnabled, isFalse);
    expect(store.sessionId, isNot(session));
    expect(
      store.events.map((event) => event.name),
      contains('session.enabled'),
    );
    expect(store.latestDebugSessionId, session);
    expect(store.tasks, isEmpty);
  });

  test(
    'filters DEBUG at INFO and logs task and step lifecycle with task links',
    () async {
      store.log(DiagnosticLevel.debug, 'rss', 'ignored');
      await store.runTask(
        type: 'rss',
        title: 'refresh',
        entityId: 'feed-1',
        body: () async {
          await store.step('parse', () async {});
        },
      );

      var names = store.events.map((event) => event.name).toSet();
      expect(names, containsAll(['task.start', 'task.end']));
      expect(names, isNot(contains('ignored')));
      expect(names, isNot(contains('step.start')));

      store.clear();
      store.setLevel(DiagnosticLevel.debug);
      await store.runTask(
        type: 'rss',
        title: 'refresh',
        body: () async {
          await store.step('parse', () async {});
        },
      );

      names = store.events.map((event) => event.name).toSet();
      expect(
        names,
        containsAll(['task.start', 'step.start', 'step.end', 'task.end']),
      );
      final taskId = store.tasks.single.id;
      expect(store.tasks.single.sessionId, store.sessionId);
      expect(
        store.events
            .where((event) => event.module == 'diagnostics.task')
            .every((event) => event.taskId == taskId),
        isTrue,
      );
    },
  );

  test(
    'event sanitization strips URL query values, bodies and credentials',
    () {
      store.registerCredentials(['actor-secret']);
      final safe = DiagnosticStore.safeUrl(
        Uri.parse(
          'https://aihot.news:443/feed/full.xml?aihot_actor=actor-secret#part',
        ),
      );
      expect(safe, startsWith('https://aihot.news:443/[path:'));
      expect(safe, isNot(contains('actor-secret')));
      expect(safe, isNot(contains('aihot_actor')));
      expect(safe, isNot(contains('full.xml')));

      store.log(
        DiagnosticLevel.warn,
        'content',
        'request.failed',
        data: {
          'url':
              'https://aihot.news/feed/full.xml?aihot_actor=actor-secret#part',
          'body': '<rss>private article</rss>',
          'headers': {'authorization': 'Bearer actor-secret'},
          'parseError': 'FormatException near <html private article body>',
          'message':
              '{"body":"private article","response":"private model output"}',
          'bytes': 17,
        },
        error: StateError('HandshakeException actor-secret'),
        stackTrace: StackTrace.current,
      );

      final encoded = jsonEncode(store.events.single.toJson());
      expect(encoded, contains('aihot.news'));
      expect(encoded, contains('[path:'));
      expect(encoded, contains('"bytes":17'));
      expect(encoded, isNot(contains('actor-secret')));
      expect(encoded, isNot(contains('aihot_actor')));
      expect(encoded, isNot(contains('private article')));
      expect(encoded, isNot(contains('private article body')));
      expect(encoded, isNot(contains('private model output')));
      expect(encoded, isNot(contains('Bearer ')));
    },
  );

  test('event DEBUG level does not enable model payload capture', () async {
    store.setLevel(DiagnosticLevel.debug);
    await store.runTask(
      type: 'model',
      title: 'without payload capture',
      body: () async {
        final call = DiagnosticScope.beginCall(
          endpoint: 'https://example.test',
          request: {'prompt': 'private prompt'},
          credential: 'key',
        );
        DiagnosticScope.finishCall(
          call,
          response: 'private response',
          statusCode: 200,
        );
      },
    );
    expect(store.tasks.single.calls.single.request, isNull);
    expect(store.tasks.single.calls.single.response, isNull);

    store.clear();
    store.debugEnabled = true;
    await store.runTask(
      type: 'model',
      title: 'with payload capture',
      body: () async {
        final call = DiagnosticScope.beginCall(
          endpoint: 'https://example.test',
          request: {'prompt': 'private prompt'},
          credential: 'key',
        );
        DiagnosticScope.finishCall(
          call,
          response: 'private response',
          statusCode: 200,
        );
      },
    );
    expect(store.tasks.single.calls.single.request, contains('private prompt'));
    expect(
      store.tasks.single.calls.single.response,
      contains('private response'),
    );
  });

  test(
    'retention removes DEBUG after seven days and other events after thirty',
    () {
      store.close();
      var now = DateTime.utc(2026, 1, 1);
      store = DiagnosticStore('${root.path}/retention.sqlite', clock: () => now)
        ..setLevel(DiagnosticLevel.debug);
      store.log(DiagnosticLevel.debug, 'rss', 'debug');
      store.log(DiagnosticLevel.info, 'rss', 'info');

      now = now.add(const Duration(days: 8));
      store.prune();
      expect(store.events.map((event) => event.name), ['info']);

      now = now.add(const Duration(days: 23));
      store.prune();
      expect(store.events, isEmpty);
    },
  );

  test(
    'clear prevents in-flight task and event writes from resurrecting',
    () async {
      store.setLevel(DiagnosticLevel.debug);
      final ready = Completer<void>();
      final release = Completer<void>();
      final running = store.runTask(
        type: 'rss',
        title: 'active',
        body: () async {
          await store.step('waiting', () async {
            ready.complete();
            await release.future;
          });
        },
      );

      await ready.future;
      store.clear();
      release.complete();
      await running;

      expect(store.tasks, isEmpty);
      expect(store.events, isEmpty);
    },
  );

  test('bounded queue keeps ERROR events ahead of lower priority entries', () {
    store.close();
    store = DiagnosticStore('${root.path}/queue.sqlite', maxQueuedEvents: 2)
      ..setLevel(DiagnosticLevel.debug);
    store.clear();

    store.log(DiagnosticLevel.info, 'queue', 'first');
    store.log(DiagnosticLevel.info, 'queue', 'second');
    store.log(DiagnosticLevel.error, 'queue', 'failure');
    store.log(DiagnosticLevel.warn, 'queue', 'after-drop');

    final names = store.events.map((event) => event.name).toSet();
    expect(names, containsAll(['second', 'failure', 'after-drop']));
    expect(names, isNot(contains('first')));
    expect(
      store.events.singleWhere((event) => event.name == 'after-drop').data,
      containsPair('droppedBefore', 1),
    );
  });

  test('timer flush persists small batches without using getters', () async {
    store.setLevel(DiagnosticLevel.debug);
    store.log(DiagnosticLevel.debug, 'timer', 'batch');

    await Future<void>.delayed(const Duration(milliseconds: 350));

    final database = sqlite3.open(databasePath);
    addTearDown(database.close);
    final names = database
        .select('SELECT data FROM events ORDER BY time ASC')
        .map(
          (row) =>
              (jsonDecode(row['data'] as String)
                  as Map<String, dynamic>)['name'],
        )
        .toList();

    expect(names, containsAll(['session.enabled', 'batch']));
  });

  test('log is best effort for cyclic and unsupported event data', () {
    final cyclic = <String, Object?>{};
    cyclic['self'] = cyclic;

    expect(
      () => store.log(
        DiagnosticLevel.info,
        'privacy',
        'cyclic',
        data: {
          'cyclic': cyclic,
          'object': Object(),
          'when': DateTime.utc(2026, 1, 1),
        },
      ),
      returnsNormally,
    );
    store.flush();

    expect(store.events.single.name, 'cyclic');
    expect(store.lastError, isNull);
  });
}
