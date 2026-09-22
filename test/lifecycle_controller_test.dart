import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:readlater/core/app_controller.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/diagnostics.dart';
import 'package:readlater/services/content_service.dart';
import 'package:readlater/core/store.dart';
import 'package:readlater/services/intelligence_service.dart';

class MemorySecrets implements SecretStore {
  @override
  Future<String?> read(String key) async => 'fixture-key';
  @override
  Future<void> write(String key, String value) async {}
}

LibraryItem source(String id, {String body = '知识管理 research evidence'}) =>
    LibraryItem(id: id, title: '知识管理 $id', kind: ItemKind.text, body: body);

Analysis resultFor(String id, List<String>? inputs, {String summary = '认识'}) =>
    Analysis.fromJson({
      'summary': summary,
      'sourceIds': [id],
      'inputItemIds': inputs,
      'suggestedTopics': ['知识管理'],
      'questions': ['如何验证知识管理？'],
    });

class RecordingIntelligence extends IntelligenceService {
  int calls = 0;
  List<LibraryItem> related = [];
  List<LibraryItem> synthesisInputs = [];
  AppSettings? receivedSettings;
  String previous = '';
  List<ResearchSource> researchSources = [];
  Completer<Analysis>? pending;
  Completer<void>? researchWait;
  @override
  Future<Analysis> analyze(
    AppSettings settings,
    String key,
    LibraryItem item,
    List<LibraryItem> related, {
    List<String> imageDataUrls = const [],
  }) async {
    calls++;
    this.related = related;
    receivedSettings = settings;
    return pending == null
        ? Analysis(summary: '新认识', sourceIds: [item.id])
        : pending!.future;
  }

  @override
  Future<Json> synthesize(
    AppSettings settings,
    String key,
    Topic topic,
    List<LibraryItem> items,
  ) async {
    synthesisInputs = items;
    return {'overview': '新的主题综述', 'sourceIds': items.map((i) => i.id).toList()};
  }

  @override
  Future<void> research(
    AppSettings settings,
    String key,
    String searchKey,
    ResearchRun run, {
    required bool Function() authorized,
    required Future<void> Function() onProgress,
    String previousReport = '',
  }) async {
    if (!authorized()) throw StateError('paused');
    previous = previousReport;
    if (researchWait != null) await researchWait!.future;
    run.sources = researchSources;
    run.report = '知识管理 新研究成果';
    run.status = 'complete';
    await onProgress();
  }
}

class DelayedAssetStore extends LocalStore {
  DelayedAssetStore(super.root);
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<Asset> writeAsset(Uint8List bytes, String name, String mime) async {
    final asset = await super.writeAsset(bytes, name, mime);
    entered.complete();
    await release.future;
    return asset;
  }
}

class ImageContent extends ContentService {
  @override
  Future<ExtractedArticle> fetchArticle(String url) async => ExtractedArticle(
    title: '知识管理',
    body: '知识管理正文',
    url: url,
    imageUrls: ['https://example.com/a.png'],
  );
  @override
  Future<Uint8List> downloadImage(String url) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xff476b4f), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(1, 1);
    try {
      return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
          .asUint8List();
    } finally {
      image.dispose();
      picture.dispose();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppController controller;
  late RecordingIntelligence ai;
  setUp(() async {
    directory = Directory.systemTemp.createTempSync('readlater-v2-controller-');
    ai = RecordingIntelligence();
    controller = AppController(
      store: LocalStore(directory.path),
      intelligence: ai,
      secrets: MemorySecrets(),
    );
    await controller.initialize();
    await controller.saveSettings(AppSettings(textModel: 'fixture'));
  });
  tearDown(() {
    controller.dispose();
    directory.deleteSync(recursive: true);
  });

  test(
    'archive prevents direct analysis but preserves original and old result',
    () async {
      final item = source('a')..analysis = resultFor('a', ['a']);
      controller.data.items.add(item);
      await (controller as dynamic).archiveItems(['a']);
      expect(item.toJson()['archivedAt'], isNotNull);
      await expectLater(controller.analyze('a'), throwsStateError);
      expect(ai.calls, 0);
      expect(item.analysis!.summary, '认识');
      expect(item.body, contains('知识管理'));
    },
  );

  test('restoring trashed archived item retains archived state', () async {
    final item = source('a');
    controller.data.items.add(item);
    await (controller as dynamic).archiveItems(['a']);
    await (controller as dynamic).trashItems(['a']);
    await (controller as dynamic).restoreItems(['a']);
    expect(item.toJson()['archivedAt'], isNotNull);
    expect(item.toJson()['trashedAt'], isNull);
    await (controller as dynamic).unarchiveItems(['a']);
    await controller.analyze('a');
    expect(ai.calls, 1);
  });

  test(
    'archived source taints cached outputs, not remaining raw originals',
    () async {
      final a = source('a')
        ..analysis = resultFor('a', ['a'], summary: 'excluded-secret');
      final b = source('b')
        ..analysis = resultFor('b', ['a', 'b'], summary: 'excluded-secret');
      final c = source('c');
      controller.data.items.addAll([a, b, c]);
      controller.data.runs.add(
        ResearchRun.fromJson({
          'id': 'r',
          'goal': '知识管理',
          'report': 'excluded-secret',
          'inputItemIds': ['a', 'b'],
        }),
      );
      await (controller as dynamic).archiveItems(['a']);
      await controller.analyze('c');
      expect(ai.related.map((i) => i.id), contains('b'));
      expect(ai.related.map((i) => i.id), isNot(contains('a')));
      expect(ai.related.map((i) => i.id), isNot(contains('r')));
      expect(ai.related.firstWhere((i) => i.id == 'b').analysis, isNull);
      expect(
        b.analysis!.summary,
        'excluded-secret',
        reason: 'historical result stays readable',
      );
      expect(c.analysis!.toJson()['inputItemIds'], containsAll(['b', 'c']));
      expect(c.analysis!.toJson()['inputItemIds'], isNot(contains('a')));
    },
  );

  test('legacy outputs with unknown lineage are not reused', () async {
    final b = source('b')..analysis = Analysis(summary: 'unproven-old-summary');
    controller.data.items.addAll([b, source('c')]);
    await controller.analyze('c');
    expect(ai.related.single.analysis, isNull);
    expect(b.analysis!.summary, 'unproven-old-summary');
  });

  test('derived inferred interest stops when its source is archived', () async {
    controller.data.items.add(source('a')..analysis = resultFor('a', ['a']));
    controller.data.settings.inferredInterests = ['知识管理'];
    controller.data.settings.explicitInterests = ['长期阅读'];
    await (controller as dynamic).archiveItems(['a']);
    expect(controller.data.settings.inferredInterests, isNot(contains('知识管理')));
    expect(controller.data.settings.explicitInterests, contains('长期阅读'));
  });

  test(
    'topic previous report with excluded ancestry is not sent again',
    () async {
      controller.data.items.add(source('a'));
      controller.data.topics.add(
        Topic.fromJson({
          'id': 't',
          'title': '知识管理',
          'question': '知识管理如何实践？',
          'overview': 'excluded-secret',
          'inputItemIds': ['a'],
        }),
      );
      await (controller as dynamic).archiveItems(['a']);
      await controller.research(
        goal: '知识管理如何实践？',
        topicId: 't',
        confirmed: true,
      );
      expect(ai.previous, isEmpty);
    },
  );

  test('archive during model await discards late output', () async {
    final item = source('a')..analysis = resultFor('a', ['a'], summary: '历史结果');
    controller.data.items.add(item);
    ai.pending = Completer<Analysis>();
    final analyzing = controller.analyze('a');
    await Future<void>.delayed(Duration.zero);
    expect(ai.calls, 1);
    await (controller as dynamic).archiveItems(['a']);
    ai.pending!.complete(Analysis(summary: '不应保存的迟到结果'));
    await expectLater(analyzing, throwsA(isA<DiagnosticCancelled>()));
    expect(item.analysis!.summary, '历史结果');
    expect(item.status, isNot('analyzing'));
  });

  test(
    'startup expiry retains deleted id lineage and clears RSS pointer',
    () async {
      controller.data.items.add(
        LibraryItem.fromJson({
          ...source('a').toJson(),
          'trashedAt': DateTime.now()
              .subtract(const Duration(days: 8))
              .toIso8601String(),
        }),
      );
      controller.data.items.add(
        source('b')..analysis = resultFor('b', ['a', 'b']),
      );
      controller.data.entries.add(
        FeedEntry(
          id: 'e',
          feedId: 'f',
          title: 'article',
          url: 'https://example.com/a',
          savedItemId: 'a',
        ),
      );
      controller.store.save(controller.data);
      await controller.initialize();
      expect(controller.data.items.map((i) => i.id), isNot(contains('a')));
      expect(controller.data.entries.single.savedItemId, isNull);
      expect(
        controller.data.items.single.analysis!.toJson()['inputItemIds'],
        contains('a'),
      );
    },
  );

  test(
    'multichunk real HTTP analysis makes no second call after archive',
    () async {
      controller.dispose();
      final pending = Completer<http.Response>();
      var calls = 0;
      controller = AppController(
        store: LocalStore(directory.path),
        secrets: MemorySecrets(),
        intelligence: IntelligenceService(
          client: MockClient((request) async {
            calls++;
            if (calls == 1) return pending.future;
            return http.Response(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': '{"summary":"late"}'},
                  },
                ],
              }),
              200,
            );
          }),
        ),
      );
      await controller.initialize();
      await controller.saveSettings(AppSettings(textModel: 'fixture'));
      controller.data.items.add(
        source('a', body: List.filled(5000, '知识管理 ').join()),
      );
      final analyzing = controller.analyze('a');
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      await (controller as dynamic).trashItems(['a']);
      pending.complete(
        http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '{"summary":"late"}'},
              },
            ],
          }),
          200,
        ),
      );
      await expectLater(analyzing, throwsA(isA<DiagnosticCancelled>()));
      expect(calls, 1);
      expect(controller.data.items.single.analysis, isNull);
    },
  );
  test(
    'shortening retention to three days purges already expired trash',
    () async {
      final a = source('a');
      a.trashedAt = DateTime.now().subtract(const Duration(days: 4));
      controller.data.items.add(a);
      await controller.setTrashRetentionDays(3);
      expect(controller.data.items, isEmpty);
    },
  );

  test('searched source matching active library URL carries lineage into later results', () async {
    final a = source('a')..url = 'https://example.com/a';
    controller.data.items.add(a);
    ai.researchSources = [
      ResearchSource(id: 'S1', title: '知识管理', url: a.url, snippet: '排除的证据'),
    ];
    final run = await controller.research(goal: '知识管理', confirmed: true);
    expect(run.inputItemIds, contains('a'));
    final b = source('b');
    controller.data.items.add(b);
    await controller.analyze('b');
    expect(b.analysis!.inputItemIds, contains('a'));
    await controller.archiveItems(['a']);
    controller.data.items.add(source('c'));
    await controller.analyze('c');
    expect(ai.related.map((i) => i.id), isNot(contains(run.id)));
    expect(ai.related.firstWhere((i) => i.id == 'b').analysis, isNull);
  });

  test('late image asset write never reattaches after archive', () async {
    controller.dispose();
    final store = DelayedAssetStore(directory.path);
    controller = AppController(
      store: store,
      content: ImageContent(),
      intelligence: ai,
      secrets: MemorySecrets(),
    );
    await controller.initialize();
    final capture = controller.captureUrl('https://example.com/a');
    await store.entered.future;
    final id = controller.data.items.single.id;
    await controller.archiveItems([id]);
    store.release.complete();
    await expectLater(capture, throwsA(isA<DiagnosticCancelled>()));
    expect(controller.data.items.single.assets, isEmpty);
    expect(Directory('${directory.path}/assets').listSync(), isEmpty);
  });

  test(
    'cancelled old analysis does not overwrite newer successful retry state',
    () async {
      controller.data.items.addAll([source('a'), source('b')]);
      final old = Completer<Analysis>();
      ai.pending = old;
      final first = controller.analyze('b');
      await Future<void>.delayed(Duration.zero);
      await controller.archiveItems(['a']);
      ai.pending = null;
      await controller.analyze('b');
      expect(controller.data.items.last.status, 'ready');
      old.complete(Analysis(summary: '迟到旧结果'));
      await expectLater(first, throwsA(isA<DiagnosticCancelled>()));
      expect(controller.data.items.last.status, 'ready');
      expect(controller.data.items.last.analysis!.summary, '新认识');
    },
  );
  test('late failure from old analysis does not overwrite newer successful retry state', () async {
    controller.data.items.addAll([source('a'), source('b')]);
    final old = Completer<Analysis>();
    ai.pending = old;
    final first = controller.analyze('b');
    await Future<void>.delayed(Duration.zero);
    await controller.archiveItems(['a']);
    ai.pending = null;
    await controller.analyze('b');
    expect(controller.data.items.last.status, 'ready');
    old.completeError(TimeoutException('late failure'));
    await expectLater(first, throwsA(isA<DiagnosticCancelled>()));
    expect(controller.data.items.last.status, 'ready');
    expect(controller.data.items.last.analysis!.summary, '新认识');
  });
  test('diagnostic source labels resolve existing research topics', () async {
    final topic = await controller.addTopic('知识管理', '如何积累认识？');
    expect(controller.sourceLabel(topic.id), '知识管理');
  });

  test(
    'changing topic scope during research prevents attaching late report',
    () async {
      final topic = await controller.addTopic('知识管理', '原研究问题');
      ai.researchWait = Completer<void>();
      final researching = controller.research(
        goal: topic.question,
        topicId: topic.id,
        confirmed: true,
      );
      await Future<void>.delayed(Duration.zero);
      await controller.updateTopic(topic.id, topic.title, '新的研究问题');
      ai.researchWait!.complete();
      await expectLater(researching, throwsA(isA<DiagnosticCancelled>()));
      expect(topic.overview, isEmpty);
      expect(controller.data.runs.single.report, isEmpty);
    },
  );
}
