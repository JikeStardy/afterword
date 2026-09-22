import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/app_controller.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/store.dart';
import 'package:readlater/platform/native_bridge.dart';
import 'package:readlater/services/content_service.dart';
import 'package:readlater/services/intelligence_service.dart';

class TestSecrets implements SecretStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class TestContent extends ContentService {
  @override
  Future<ParsedFeed> fetchFeed(String url) async => ParsedFeed(
    title: 'Test feed',
    entries: [
      FeedEntry(
        id: 'e1',
        feedId: '',
        title: '文章',
        url: 'https://example.com/a',
      ),
    ],
  );
  @override
  Future<ExtractedArticle> fetchArticle(String url) async =>
      ExtractedArticle(title: '文章', body: '文章正文', url: url, imageUrls: []);
}

class BrokenImageContent extends TestContent {
  @override
  Future<ExtractedArticle> fetchArticle(String url) async => ExtractedArticle(
    title: '正文仍然可读',
    body: '这是一段需要保留的正文。',
    url: url,
    imageUrls: ['https://example.com/broken.png'],
  );
  @override
  Future<Uint8List> downloadImage(String url) async =>
      Uint8List.fromList(utf8.encode('not an image'));
}

class CountingIntelligence extends IntelligenceService {
  int analyses = 0, researches = 0;
  List<String> suggestions = [];
  @override
  Future<Analysis> analyze(
    AppSettings s,
    String key,
    LibraryItem item,
    List<LibraryItem> related, {
    List<String> imageDataUrls = const [],
  }) async {
    analyses++;
    return Analysis(
      summary: '认识',
      insights: ['方法有条件适用'],
      sourceIds: [item.id],
      suggestedTopics: suggestions,
    );
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
    if (!authorized()) throw StateError('unauthorized');
    researches++;
    run.status = 'complete';
    run.report = '结果';
    run.completedAt = DateTime.now();
    await onProgress();
  }
}

class QueueNative extends NativeBridge {
  void Function()? listener;
  final queue = <SharedInput>[];
  bool signalDuringRead = false;
  @override
  void setShareListener(void Function()? value) {
    listener = value;
  }

  @override
  Future<List<SharedInput>> pendingShares() async {
    final snapshot = queue.toList();
    if (signalDuringRead) {
      signalDuringRead = false;
      queue.add(const SharedInput(id: 'late', text: '晚到的分享', paths: []));
      listener?.call();
    }
    return snapshot;
  }

  @override
  Future<void> acknowledgeShare(String id) async {
    queue.removeWhere((s) => s.id == id);
  }
}

class NotificationNative extends NativeBridge {
  final notifications = <String>[];
  @override
  Future<void> requestNotificationPermission() async {}
  @override
  Future<void> notify(String title, String body) async =>
      notifications.add(body);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppController controller;
  late CountingIntelligence intelligence;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('readlater-controller-');
    intelligence = CountingIntelligence();
    controller = AppController(
      store: LocalStore(dir.path),
      content: TestContent(),
      intelligence: intelligence,
      secrets: TestSecrets(),
    );
    await controller.initialize();
  });
  tearDown(() {
    controller.dispose();
    dir.deleteSync(recursive: true);
  });
  for (final scenario in [
    (name: 'no important change', report: '没有重要变化 [S1]', meaningful: false),
    (name: 'new evidence', report: '新证据改变适用条件 [S1]', meaningful: true),
    (name: 'changed conclusion', report: '已有结论需要修正 [S1]', meaningful: true),
    (
      name: 'user decision needed',
      report: '请用户选择后续研究方向 [S1]',
      meaningful: true,
    ),
  ]) {
    test('tracking notification gate: ${scenario.name}', () async {
      controller.dispose();
      final native = NotificationNative();
      controller = AppController(
        store: LocalStore(dir.path),
        secrets: TestSecrets(),
        native: native,
        intelligence: IntelligenceService(
          client: MockClient((request) async {
            final result = request.url.path.endsWith('/search')
                ? {
                    'results': [
                      {
                        'title': '原始依据',
                        'url': 'https://example.com/source',
                        'content': '研究证据',
                      },
                    ],
                  }
                : {
                    'choices': [
                      {
                        'message': {
                          'content': jsonEncode({
                            'report': scenario.report,
                            'nextQuery': '',
                            'meaningful': scenario.meaningful,
                          }),
                        },
                      },
                    ],
                  };
            return http.Response(
              jsonEncode(result),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      );
      await controller.initialize();
      await controller.saveSettings(
        AppSettings(textModel: 'm'),
        apiKey: 'key',
        searchKey: 'search',
      );
      final topic = await controller.addTopic('知识管理', '比较笔记方法');
      await controller.setTracking(
        topic.id,
        enabled: true,
        confirmed: true,
        callLimit: 2,
      );
      await controller.runDueTracking();
      expect(controller.data.runs.single.status, 'complete');
      expect(controller.data.runs.single.calls, 2);
      expect(controller.data.notices.length, scenario.meaningful ? 1 : 0);
      expect(native.notifications.length, scenario.meaningful ? 1 : 0);
      expect(topic.lastRun, isNotNull);
      expect(topic.sourceIds, [controller.data.runs.single.id]);
      await controller.runDueTracking();
      expect(controller.data.runs.length, 1);
    });
  }
  test('unconfigured model never prevents saving original notes', () async {
    final item = await controller.captureText('我想保留的原文', notes: '关注适用条件');
    expect(item.body, '我想保留的原文');
    expect(item.status, 'waiting');
    expect(intelligence.analyses, 0);
    final reopened = LocalStore(dir.path);
    expect(reopened.load().items.single.notes, '关注适用条件');
    reopened.close();
  });
  test(
    'invalid downloaded images are reported without losing saved article',
    () async {
      controller.dispose();
      controller = AppController(
        store: LocalStore(dir.path),
        content: BrokenImageContent(),
        secrets: TestSecrets(),
      );
      await controller.initialize();
      final item = await controller.captureUrl('https://example.com/article');
      expect(item.body, '这是一段需要保留的正文。');
      expect(item.warning, contains('1 张图片'));
      expect(item.assets, isEmpty);
    },
  );
  test(
    'long text segments retain explicit feedback and attention signals',
    () async {
      controller.dispose();
      final inputs = <Map<String, dynamic>>[];
      controller = AppController(
        store: LocalStore(dir.path),
        secrets: TestSecrets(),
        intelligence: IntelligenceService(
          client: MockClient((request) async {
            final prompt =
                jsonDecode(request.body)['messages'][1]['content'] as String;
            final input =
                jsonDecode(prompt.split('输入数据：').last) as Map<String, dynamic>;
            inputs.add(input['item'] as Map<String, dynamic>);
            return http.Response(
              jsonEncode({
                'choices': [
                  {
                    'message': {
                      'content': jsonEncode({
                        'summary': '分段认识',
                        'insights': ['保留适用条件'],
                        'sourceIds': [input['item']['id']],
                      }),
                    },
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      );
      await controller.initialize();
      final item = await controller.captureText(List.filled(25001, '文').join());
      await controller.markRead(item.id);
      await controller.markRead(item.id);
      await controller.setFeedback(item.id, -1);
      item.researchAdoptions = 1;
      await controller.saveSettings(AppSettings(textModel: 'm'), apiKey: 'key');
      await controller.analyze(item.id);
      expect(item.status, 'ready');
      expect(inputs.length, 3);
      for (final input in inputs) {
        expect(input['feedback'], -1);
        expect(input['attentionNotAgreement'], {
          'reads': 2,
          'researchAdoptions': 1,
        });
      }
    },
  );
  test('saved research evidence participates in later analysis and topic synthesis', () async {
    controller.dispose();
    final prompts = <String>[];
    controller = AppController(
      store: LocalStore(dir.path),
      secrets: TestSecrets(),
      intelligence: IntelligenceService(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final prompt = body['messages'][1]['content'] as String;
          prompts.add(prompt);
          final result = prompt.contains('生成观点卡片')
              ? {
                  'summary': '研究与新资料相互补充 [r1]',
                  'insights': ['方法有条件适用 [r1]'],
                  'sourceIds': ['r1'],
                }
              : {
                  'overview': '旧研究的适用条件仍是重要依据 [r1]',
                  'sourceIds': ['r1'],
                };
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': jsonEncode(result)},
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
    await controller.initialize();
    await controller.saveSettings(AppSettings(textModel: 'm'), apiKey: 'key');
    final topic = await controller.addTopic('知识管理', '怎样形成认识');
    controller.data.runs.add(
      ResearchRun(
        id: 'r1',
        inputItemIds: const [],
        goal: '知识管理的适用条件',
        topicId: topic.id,
        status: 'complete',
        report: '${List.filled(3000, '知识管理需要适用条件').join()} [S1]',
        sources: [
          ResearchSource(
            id: 'S1',
            title: '原始依据',
            url: 'https://example.com/evidence',
            snippet: '方法的约束条件',
          ),
        ],
      ),
    );
    final item = await controller.captureText('知识管理的新资料讨论适用条件');
    expect(item.status, 'ready');
    expect(item.analysis!.sourceIds, contains('r1'));
    await controller.synthesizeTopic(topic.id);
    expect(topic.status, 'ready');
    expect(topic.sourceIds, contains('r1'));
    expect(
      prompts.every((p) => p.contains('https://example.com/evidence')),
      isTrue,
    );
    expect(prompts.every((p) => p.contains('方法的约束条件')), isTrue);
  });
  test(
    'dismissing an error removes it without discarding research notices',
    () async {
      controller.lastError = '网络失败';
      controller.data.notices.add('主题有新发现');
      await controller.dismissError();
      expect(controller.lastError, isNull);
      expect(controller.data.notices, ['主题有新发现']);
    },
  );
  test(
    'restore makes interrupted analysis and synthesis retryable immediately',
    () async {
      final item = await controller.captureText('保留下来的原文');
      final topic = await controller.addTopic('知识管理', '怎样形成认识');
      item.status = 'analyzing';
      topic.status = 'synthesizing';
      controller.store.save(controller.data);
      final bytes = controller.store.backup();
      await controller.restore(bytes);
      expect(controller.data.items.single.status, 'interrupted');
      expect(controller.data.items.single.body, '保留下来的原文');
      expect(controller.data.topics.single.status, 'pending');
      expect(controller.store.load().topics.single.status, 'pending');
    },
  );
  test(
    'RSS remains unanalysed until selected, then joins regular analysis',
    () async {
      await controller.saveSettings(
        AppSettings(textModel: 'm'),
        apiKey: 'test',
      );
      await controller.addFeed('https://example.com/feed');
      expect(controller.data.entries.length, 1);
      expect(controller.data.items, isEmpty);
      expect(intelligence.analyses, 0);
      await controller.selectEntry('e1');
      expect(controller.data.items.single.analysis!.summary, '认识');
      expect(intelligence.analyses, 1);
      await controller.selectEntry('e1');
      expect(controller.data.items.length, 1);
    },
  );
  test('unconfirmed external research is blocked before network', () async {
    await expectLater(
      controller.research(goal: '研究', confirmed: false),
      throwsStateError,
    );
    expect(intelligence.researches, 0);
    expect(controller.data.runs, isEmpty);
  });
  test(
    'only confirmed research adoption is retained as an attention signal',
    () async {
      await controller.saveSettings(
        AppSettings(textModel: 'm'),
        apiKey: 'key',
        searchKey: 'search',
      );
      final item = await controller.captureText('研究知识管理');
      item.analysis!.questions = ['比较不同笔记方法'];
      await expectLater(
        controller.research(goal: '比较不同笔记方法', confirmed: false),
        throwsStateError,
      );
      expect(item.researchAdoptions, 0);
      await controller.research(goal: '比较不同笔记方法', confirmed: true);
      expect(item.researchAdoptions, 1);
      expect(controller.store.load().items.single.researchAdoptions, 1);
      expect(item.feedback, 0);
    },
  );
  test(
    'changing question invalidates existing tracking authorization',
    () async {
      final topic = await controller.addTopic('知识管理', '如何做笔记');
      await controller.setTracking(topic.id, enabled: true, confirmed: true);
      await controller.updateTopic(topic.id, '知识管理', '如何做商业投资');
      expect(topic.tracking, isFalse);
      expect(topic.authorizedScope, isEmpty);
    },
  );
  test(
    'due tracking coalesces missed runs and paused topics do not execute',
    () async {
      await controller.saveSettings(
        AppSettings(textModel: 'm'),
        apiKey: 'test',
        searchKey: 'search',
      );
      final topic = await controller.addTopic('笔记', '研究笔记');
      await controller.setTracking(topic.id, enabled: true, confirmed: true);
      topic.nextRun = DateTime.now().subtract(const Duration(days: 20));
      await controller.runDueTracking();
      await controller.runDueTracking();
      expect(intelligence.researches, 1);
      await controller.setTracking(topic.id, enabled: false, confirmed: false);
      topic.nextRun = DateTime.now().subtract(const Duration(days: 1));
      await controller.runDueTracking();
      expect(intelligence.researches, 1);
    },
  );
  test(
    'explicit preference correction is retained separately from behavior',
    () async {
      await controller.saveSettings(
        AppSettings(explicitInterests: ['反例'], inferredInterests: ['工具']),
      );
      expect(controller.data.settings.explicitInterests, ['反例']);
      final item = await controller.captureText('与工具相关');
      await controller.markRead(item.id);
      expect(controller.data.settings.explicitInterests, ['反例']);
    },
  );
  test(
    'invalid research budget is rejected before creating a running record',
    () async {
      await controller.saveSettings(
        AppSettings(textModel: 'm'),
        apiKey: 'test',
        searchKey: 'search',
      );
      await expectLater(
        controller.research(goal: '问题', confirmed: true, callLimit: 1),
        throwsFormatException,
      );
      expect(controller.data.runs, isEmpty);
    },
  );
  test('interrupted topic synthesis can be retried after restart', () async {
    final topic = await controller.addTopic('笔记', '如何整理笔记');
    topic.status = 'synthesizing';
    controller.store.save(controller.data);
    await controller.initialize();
    expect(controller.data.topics.single.status, isNot('synthesizing'));
  });
  test(
    'restoring an untrusted backup cannot redirect existing API credentials',
    () async {
      await controller.saveSettings(
        AppSettings(
          endpoint: 'https://trusted.example/v1',
          textModel: 'm',
          searchEndpoint: 'https://trusted.example/search',
        ),
        apiKey: 'private-model',
        searchKey: 'private-search',
      );
      final imported = Directory.systemTemp.createTempSync('readlater-import-');
      final other = LocalStore(imported.path);
      try {
        other.save(
          AppData(
            settings: AppSettings(
              endpoint: 'https://untrusted.example/v1',
              textModel: 'm',
              searchEndpoint: 'https://untrusted.example/search',
            ),
          ),
        );
        await controller.restore(other.backup());
        expect(controller.data.settings.endpoint, 'https://trusted.example/v1');
        expect(
          controller.data.settings.searchEndpoint,
          'https://trusted.example/search',
        );
      } finally {
        other.close();
        imported.deleteSync(recursive: true);
      }
    },
  );
  test('removed inferred interest does not reappear on the next automatic analysis', () async {
    await controller.saveSettings(AppSettings(textModel: 'm'), apiKey: 'key');
    intelligence.suggestions = ['工具'];
    await controller.captureText('工具的用途');
    expect(controller.data.settings.inferredInterests, contains('工具'));
    final edited = AppSettings.fromJson(controller.data.settings.toJson());
    edited.inferredInterests.clear();
    await controller.saveSettings(edited);
    await controller.captureText('更多工具资料');
    expect(controller.data.settings.inferredInterests, isNot(contains('工具')));
  });

  test('native share completed during a drain is processed without waiting for next resume', () async {
    controller.dispose();
    final native = QueueNative()..signalDuringRead = true;
    controller = AppController(
      store: LocalStore(dir.path),
      native: native,
      secrets: TestSecrets(),
    );
    await controller.initialize();
    await controller.resume();
    expect(controller.data.items.single.body, '晚到的分享');
    expect(native.queue, isEmpty);
  });
  test(
    'terminal native share failure is visible and cannot block later shares',
    () async {
      controller.dispose();
      final native = QueueNative();
      native.queue.addAll([
        const SharedInput(id: 'bad', text: '', paths: [], error: '附件超过50MB'),
        const SharedInput(id: 'good', text: '后续内容', paths: []),
      ]);
      controller = AppController(
        store: LocalStore(dir.path),
        native: native,
        secrets: TestSecrets(),
      );
      await controller.initialize();
      await controller.resume();
      expect(controller.data.items.single.body, '后续内容');
      expect(controller.data.notices.join(), contains('50MB'));
      expect(native.queue, isEmpty);
    },
  );
}
