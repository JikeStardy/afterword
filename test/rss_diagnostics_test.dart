import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:readlater/core/app_controller.dart';
import 'package:readlater/core/diagnostics.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/store.dart';
import 'package:readlater/platform/native_bridge.dart';
import 'package:readlater/services/content_service.dart';
import 'package:xml/xml.dart' as xml;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'RSS request diagnostics record redirects without URL query secrets',
    () async {
      final logs = DiagnosticStore(':memory:')..setLevel(DiagnosticLevel.debug);
      addTearDown(logs.close);
      final service = ContentService(
        client: MockClient((request) async {
          if (request.url.path == '/feed.xml') {
            return http.Response('', 302, headers: {'location': '/full.xml'});
          }
          return http.Response(
            '<rss><channel><title>Feed</title><item>'
            '<title>Article</title><guid>a</guid><link>https://example.test/a</link>'
            '</item></channel></rss>',
            200,
          );
        }),
      );
      addTearDown(service.close);

      await logs.runTask(
        type: 'rss',
        title: 'refresh',
        body: () => service.fetchFeed(
          'https://example.test/feed.xml?aihot_actor=secret-token#fragment',
        ),
      );

      final events = logs.events;
      expect(
        events.map((event) => event.name),
        containsAll([
          'request.start',
          'response.headers',
          'redirect.follow',
          'body.success',
          'parse.success',
        ]),
      );
      final requestEvents = events
          .where(
            (event) => {
              'request.start',
              'response.headers',
              'redirect.follow',
              'body.success',
            }.contains(event.name),
          )
          .toList();
      expect(
        requestEvents.map((event) => event.data['requestId']).toSet(),
        hasLength(1),
      );
      final exported = String.fromCharCodes(logs.exportLogs());
      expect(exported, isNot(contains('secret-token')));
      expect(exported, isNot(contains('aihot_actor=secret-token')));
      expect(exported, isNot(contains('fragment')));
    },
  );

  test(
    'TLS handshake failure keeps status code empty and phase accurate',
    () async {
      final logs = DiagnosticStore(':memory:')..setLevel(DiagnosticLevel.debug);
      addTearDown(logs.close);
      final service = ContentService(
        client: MockClient((request) async {
          throw const HandshakeException(
            'Connection terminated during handshake',
          );
        }),
      );
      addTearDown(service.close);

      await expectLater(
        logs.runTask(
          type: 'rss',
          title: 'handshake',
          body: () => service.fetchFeed('https://aihot.news/feed/full.xml'),
        ),
        throwsA(isA<HandshakeException>()),
      );

      final failure = logs.events.singleWhere(
        (event) => event.name == 'request.failure',
      );
      expect(failure.data['phase'], 'tls');
      expect(failure.data['statusCode'], isNull);
      expect(failure.data['errorType'], contains('Handshake'));
    },
  );

  test(
    'RSS parse failures are logged at parse phase after body success',
    () async {
      final logs = DiagnosticStore(':memory:')..setLevel(DiagnosticLevel.debug);
      addTearDown(logs.close);
      final service = ContentService(
        client: MockClient((request) async => http.Response('<html>', 200)),
      );
      addTearDown(service.close);

      await expectLater(
        logs.runTask(
          type: 'rss',
          title: 'parse',
          body: () => service.fetchFeed('https://example.test/feed.xml'),
        ),
        throwsA(isA<xml.XmlException>()),
      );

      expect(logs.events.map((event) => event.name), contains('body.success'));
      final failure = logs.events.singleWhere(
        (event) => event.name == 'parse.failure',
      );
      expect(failure.data['phase'], 'parse');
      expect(failure.data['kind'], 'rss');
    },
  );

  test(
    'feed refresh reports partial failures without losing successful feeds',
    () async {
      final root = Directory.systemTemp.createTempSync('rss-diagnostics');
      final logs = DiagnosticStore(':memory:');
      final controller = AppController(
        store: LocalStore(root.path),
        diagnostics: logs,
        content: _PartialFeedContent(),
        native: _NoopNativeBridge(),
        secrets: _MemorySecrets(),
      );
      addTearDown(() {
        controller.dispose();
        logs.close();
        root.deleteSync(recursive: true);
      });
      controller.data.feeds.addAll([
        Feed(id: 'ok', url: 'https://example.test/ok.xml'),
        Feed(id: 'bad', url: 'https://example.test/bad.xml'),
      ]);

      final result = await controller.refreshFeeds();

      expect(result.succeeded, 1);
      expect(result.failed, 1);
      expect(controller.data.entries.single.feedId, 'ok');
      expect(
        controller.data.feeds.firstWhere((feed) => feed.id == 'ok').error,
        '',
      );
      expect(
        controller.data.feeds.firstWhere((feed) => feed.id == 'bad').error,
        contains('HandshakeException'),
      );
      expect(
        logs.events.where((event) => event.name == 'feed.refresh.failure'),
        hasLength(1),
      );
      final tasks = logs.tasks;
      expect(
        tasks
            .singleWhere(
              (task) => task.type == 'rssFeed' && task.entityId == 'bad',
            )
            .status,
        'failed',
      );
      expect(tasks.singleWhere((task) => task.type == 'rss').status, 'failed');
    },
  );
}

class _PartialFeedContent extends ContentService {
  @override
  Future<ParsedFeed> fetchFeed(String url) async {
    if (url.contains('/bad')) {
      throw const HandshakeException('Connection terminated during handshake');
    }
    return ParsedFeed(
      title: 'OK',
      entries: [
        FeedEntry(
          id: 'entry-ok',
          feedId: '',
          title: 'Article',
          url: 'https://example.test/article',
        ),
      ],
    );
  }
}

class _NoopNativeBridge extends NativeBridge {
  @override
  Future<void> stopBackgroundWork() async {}
}

class _MemorySecrets implements SecretStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
