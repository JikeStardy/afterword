import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:readlater/core/app_controller.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/retrieval.dart';
import 'package:readlater/core/store.dart';
import 'package:readlater/platform/native_bridge.dart';
import 'package:readlater/services/intelligence_service.dart';

class RuntimeSecrets implements SecretStore {
  @override
  Future<String?> read(String key) async => 'fixture-key';

  @override
  Future<void> write(String key, String value) async {}
}

class RuntimeNative extends NativeBridge {
  int started = 0, pdfReads = 0, imageReads = 0;
  String? lastPdfPath, lastImagePath;
  int? lastPdfStartPage, lastPdfMaxPages;
  final notifications = <PublishedNotification>[];

  @override
  Future<void> startBackgroundWork() async {
    started++;
  }

  @override
  Future<PdfPages> renderPdf(
    String path, {
    int startPage = 0,
    int maxPages = 4,
  }) async {
    pdfReads++;
    lastPdfPath = path;
    lastPdfStartPage = startPage;
    lastPdfMaxPages = maxPages;
    return const PdfPages(pageCount: 3, images: ['cGRmLXBhZ2U=']);
  }

  @override
  Future<String> normalizeImage(String path) async {
    imageReads++;
    lastImagePath = path;
    return 'bm9ybWFsaXplZC1pbWFnZQ==';
  }

  @override
  Future<bool> publishNotification({
    required String id,
    required String channel,
    required String title,
    required String body,
    String? entityType,
    String? entityId,
  }) async {
    notifications.add(
      PublishedNotification(
        id: id,
        channel: channel,
        entityType: entityType ?? '',
        entityId: entityId ?? '',
      ),
    );
    return true;
  }
}

class PublishedNotification {
  const PublishedNotification({
    required this.id,
    required this.channel,
    required this.entityType,
    required this.entityId,
  });
  final String id, channel, entityType, entityId;
}

class BlockingAnalysisService extends IntelligenceService {
  BlockingAnalysisService({super.client});

  final entered = Completer<void>();
  final release = Completer<void>();
  int calls = 0;

  @override
  Future<Analysis> analyze(
    AppSettings settings,
    String key,
    LibraryItem item,
    List<LibraryItem> related, {
    List<String> imageDataUrls = const [],
    List<EvidenceAnchor>? availableEvidence,
  }) async {
    calls++;
    if (!entered.isCompleted) entered.complete();
    await release.future;
    return Analysis(summary: '后台分析完成', sourceIds: [item.id]);
  }
}

typedef RequestHandler = Future<Json> Function(
  Map<String, dynamic> payload,
  http.Request request,
);

class RuntimeHarness {
  RuntimeHarness({this.handler, this.intelligence, RuntimeNative? native})
    : native = native ?? RuntimeNative();

  late final Directory temp;
  late final LocalStore store;
  late final AppController controller;
  final RuntimeNative native;
  final RequestHandler? handler;
  final prompts = <Map<String, dynamic>>[];

  Future<void> setUp() async {
    temp = Directory.systemTemp.createTempSync('readlater-conversation-rt-');
    store = LocalStore(temp.path);
    final service =
        intelligence ??
        IntelligenceService(
          client: MockClient((request) async {
            final prompt = _requestPrompt(request);
            final payload = _promptPayload(prompt);
            prompts.add(payload);
            final answer =
                await (handler?.call(payload, request) ??
                    Future<Json>.value({
                      'answer': '默认回答',
                      'evidence': const [],
                      'remainingGaps': const [],
                    }));
            return _reply(answer);
          }),
        );
    controller = AppController(
      store: store,
      intelligence: service,
      native: native,
      secrets: RuntimeSecrets(),
    );
    await controller.initialize();
    await controller.saveSettings(
      AppSettings(textModel: 'fixture', visionModel: 'fixture'),
    );
  }

  IntelligenceService? intelligence;

  Future<void> dispose() async {
    await controller.waitForIdle();
    controller.dispose();
    temp.deleteSync(recursive: true);
  }

  LibraryItem addText(
    String id,
    String title,
    String body, {
    int contentVersion = 1,
  }) {
    final item = LibraryItem(
      id: id,
      title: title,
      kind: ItemKind.text,
      body: body,
      contentVersion: contentVersion,
      contentBlocks: [
        ContentBlock(
          id: 'body-1',
          kind: ContentBlockKind.paragraph,
          text: body,
        ),
      ],
    );
    controller.data.items.add(item);
    store.saveWithRuntime(controller.data, controller.runtime);
    return item;
  }

  Future<LibraryItem> addAssetItem({
    required String id,
    required ItemKind kind,
    required String name,
    required List<int> bytes,
    int? pdfPageCount,
  }) async {
    final file = File('${temp.path}/$name')..writeAsBytesSync(bytes);
    final asset = await store.importAsset(
      file.path,
      name,
      kind == ItemKind.pdf ? 'application/pdf' : 'image/png',
    );
    final item = LibraryItem(
      id: id,
      title: name,
      kind: kind,
      assets: [asset],
      pdfPageCount: pdfPageCount,
      status: 'ready',
    );
    controller.data.items.add(item);
    store.saveWithRuntime(controller.data, controller.runtime);
    return item;
  }
}

http.Response _reply(Json answer, {int statusCode = 200}) =>
    http.Response.bytes(
      utf8.encode(
        jsonEncode({
          'choices': [
            {
              'message': {'content': jsonEncode(answer)},
            },
          ],
        }),
      ),
      statusCode,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

String _requestPrompt(http.Request request) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  final messages = body['messages'] as List;
  final user = messages.last as Map<String, dynamic>;
  final content = user['content'];
  if (content is String) return content;
  return ((content as List).first as Map<String, dynamic>)['text'] as String;
}

Map<String, dynamic> _promptPayload(String prompt) =>
    jsonDecode(prompt.split('输入数据：').last) as Map<String, dynamic>;

Json _answer(String answer) => {
  'answer': answer,
  'evidence': const [],
  'remainingGaps': const [],
};

KnowledgeRevision _revision({
  required String id,
  required String topicId,
  required String sourceId,
  required LibraryItem source,
  required String brief,
}) => KnowledgeRevision(
  id: id,
  topicId: topicId,
  presentation: ReadingPresentation(brief: brief),
  inputItemIds: [sourceId],
  sourceVersions: {sourceId: source.contentVersion},
  sourceFingerprints: {sourceId: sourceFingerprint(source)},
);

String _revisionFingerprint(KnowledgeRevision revision) =>
    sha256.convert(utf8.encode(jsonEncode(revision.toJson()))).toString();

Future<void> _eventually(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition was not met before $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'interactive question runs while background analysis is blocked',
    () async {
      final ai = BlockingAnalysisService(
        client: MockClient((request) async => _reply(_answer('默认回答'))),
      );
      final harness = RuntimeHarness(intelligence: ai);
      harness.intelligence = ai;
      await harness.setUp();
      final controller = harness.controller;
      try {
        harness.addText('analysis-src', '后台资料', '后台资料正文');
        harness.addText('dialogue-src', '对话资料', '对话证据正文');
        final background = controller.queueAnalysis('analysis-src');
        await ai.entered.future.timeout(const Duration(seconds: 2));

        final conversationId = await controller.startConversation(
          ConversationScope.item,
          scopeId: 'dialogue-src',
        );
        final turnId = await controller.submitQuestion(
          conversationId,
          '现在能回答吗？',
        );
        await _eventually(
          () => controller.data.conversationTurns.any(
            (turn) => turn.id == turnId && turn.status == 'completed',
          ),
        );

        expect(
          controller.data.conversationTurns
              .singleWhere((t) => t.id == turnId)
              .answer,
          '默认回答',
        );
        expect(
          controller.runtime.jobs.any((job) => job.lane == 'background'),
          isTrue,
        );
        ai.release.complete();
        await background;
        await controller.waitForIdle();
        expect(ai.calls, 1);
      } finally {
        if (!ai.release.isCompleted) ai.release.complete();
        await harness.dispose();
      }
    },
  );

  test('same conversation allows only one inflight turn', () async {
    final gate = Completer<void>();
    final harness = RuntimeHarness(
      handler: (payload, request) async {
        await gate.future;
        return _answer('完成');
      },
    );
    await harness.setUp();
    try {
      harness.addText('a', '资料', '第一段资料');
      final conversationId = await harness.controller.startConversation(
        ConversationScope.item,
        scopeId: 'a',
      );
      await harness.controller.submitQuestion(conversationId, '第一个问题');
      await _eventually(
        () => harness.controller.data.conversationTurns.isNotEmpty,
      );

      await expectLater(
        harness.controller.submitQuestion(conversationId, '第二个问题'),
        throwsStateError,
      );

      gate.complete();
      await harness.controller.waitForIdle();
      expect(harness.controller.data.conversationTurns, hasLength(1));
      final turn = harness.controller.data.conversationTurns.single;
      expect(turn.status, 'completed', reason: turn.error);
    } finally {
      if (!gate.isCompleted) gate.complete();
      await harness.dispose();
    }
  });

  test(
    'latest reusable answer is privileged while older safe history is derived',
    () async {
      var count = 0;
      final harness = RuntimeHarness(
        handler: (payload, request) async {
          count++;
          return _answer('answer-$count');
        },
      );
      await harness.setUp();
      try {
        harness.addText('a', '资料', '可复用资料正文');
        final conversationId = await harness.controller.startConversation(
          ConversationScope.item,
          scopeId: 'a',
        );
        await harness.controller.submitQuestion(conversationId, '第一问');
        await harness.controller.waitForIdle();
        await harness.controller.submitQuestion(conversationId, '第二问');
        await harness.controller.waitForIdle();
        await harness.controller.submitQuestion(conversationId, '第三问');
        await harness.controller.waitForIdle();

        final thirdPayload = harness.prompts.last;
        expect(thirdPayload['lastAnswer'], isA<Map<String, dynamic>>());
        expect(thirdPayload['lastAnswer']['answer'], 'answer-2');
        final history = thirdPayload['history'] as List;
        expect(history.single['answer'], 'answer-1');
        expect(history.single['derived'], isTrue);
        expect(
          thirdPayload['historyCoverage']['derivedHistoryNotOriginalEvidence'],
          isTrue,
        );
      } finally {
        await harness.dispose();
      }
    },
  );

  test(
    'readText actions are version guarded and final call answers only',
    () async {
      final requested = <Map<String, dynamic>>[];
      final harness = RuntimeHarness(
        handler: (payload, request) async {
          requested.add(payload);
          if (requested.length < 5) {
            return {
              'actions': [
                {
                  'id': 'read-${requested.length}',
                  'type': 'readText',
                  'sourceId': 'a',
                  'sourceVersion': 7,
                  'blockId': 'body-1',
                  'start': 0,
                  'end': 8,
                },
              ],
            };
          }
          return _answer('第五次直接回答');
        },
      );
      await harness.setUp();
      try {
        harness.addText(
          'a',
          '资料',
          '0123456789abcdefghijklmnopqrstuvwxyz',
          contentVersion: 7,
        );
        final conversationId = await harness.controller.startConversation(
          ConversationScope.item,
          scopeId: 'a',
        );
        await harness.controller.submitQuestion(conversationId, '需要补读');
        await harness.controller.waitForIdle();

        final turn = harness.controller.data.conversationTurns.single;
        expect(turn.status, 'completed');
        expect(turn.calls, 5);
        expect(turn.answer, '第五次直接回答');
        expect(requested.last['protocol']['answerOnly'], isTrue);
        expect(
          turn.windows.any(
            (window) =>
                window.readActionId.startsWith('read-') &&
                window.text == '01234567',
          ),
          isTrue,
        );
        expect(turn.sourceVersions['a'], 7);
      } finally {
        await harness.dispose();
      }
    },
  );

  test('failed call persists one spent call and retry is explicit', () async {
    var first = true;
    final harness = RuntimeHarness(
      handler: (payload, request) async {
        if (first) {
          first = false;
          throw const SocketException('fixture 503');
        }
        return _answer('重试后的回答');
      },
    );
    await harness.setUp();
    try {
      harness.addText('a', '资料', '失败后可重试的资料');
      final conversationId = await harness.controller.startConversation(
        ConversationScope.item,
        scopeId: 'a',
      );
      final turnId = await harness.controller.submitQuestion(
        conversationId,
        '会失败吗？',
      );
      await harness.controller.waitForIdle();

      var turn = harness.controller.data.conversationTurns.single;
      expect(turn.id, turnId);
      expect(turn.status, 'paused');
      expect(turn.calls, 1);
      expect(turn.requestPending, isTrue);
      expect(
        harness.controller.runtime.jobs.where((j) => j.type == 'conversation'),
        hasLength(1),
      );

      await harness.controller.retryTurn(turnId);
      await harness.controller.waitForIdle();
      turn = harness.controller.data.conversationTurns.single;
      expect(turn.status, 'completed');
      expect(turn.calls, 2);
      expect(turn.requestPending, isFalse);
      expect(turn.answer, '重试后的回答');
    } finally {
      await harness.dispose();
    }
  });

  test('exhausted call budget requires a new question', () async {
    final harness = RuntimeHarness(
      handler: (payload, request) async {
        throw const SocketException('fixture failure');
      },
    );
    await harness.setUp();
    try {
      harness.controller.data.settings.conversationCallLimit = 1;
      harness.addText('a', '资料', '预算用尽资料');
      harness.store.saveWithRuntime(
        harness.controller.data,
        harness.controller.runtime,
      );
      final conversationId = await harness.controller.startConversation(
        ConversationScope.item,
        scopeId: 'a',
      );
      final turnId = await harness.controller.submitQuestion(
        conversationId,
        '预算问题',
      );
      await harness.controller.waitForIdle();

      final turn = harness.controller.data.conversationTurns.single;
      expect(turn.status, 'paused');
      expect(turn.calls, 1);
      await expectLater(harness.controller.retryTurn(turnId), throwsStateError);
    } finally {
      await harness.dispose();
    }
  });

  test(
    'archived or changed source rejects late answer and stops further reads',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      var requests = 0;
      final harness = RuntimeHarness(
        handler: (payload, request) async {
          requests++;
          if (!entered.isCompleted) entered.complete();
          await release.future;
          return {
            'actions': [
              {
                'type': 'readText',
                'sourceId': 'a',
                'sourceVersion': 1,
                'blockId': 'body-1',
                'start': 0,
                'end': 5,
              },
            ],
          };
        },
      );
      await harness.setUp();
      try {
        final item = harness.addText('a', '资料', '即将被归档或修改的资料');
        final conversationId = await harness.controller.startConversation(
          ConversationScope.item,
          scopeId: 'a',
        );
        await harness.controller.submitQuestion(conversationId, '读一下');
        await entered.future.timeout(const Duration(seconds: 2));

        item.body = '已修改';
        item.contentBlocks.single.text = '已修改';
        await harness.controller.archiveItems(['a']);
        release.complete();
        await harness.controller.waitForIdle();

        final turn = harness.controller.data.conversationTurns.single;
        expect(turn.status, anyOf('cancelled', 'paused', 'interrupted'));
        expect(turn.answer, isEmpty);
        expect(requests, 1);
        expect(
          turn.windows.where((window) => window.readActionId.isNotEmpty),
          isEmpty,
        );
      } finally {
        if (!release.isCompleted) release.complete();
        await harness.dispose();
      }
    },
  );

  test(
    'stale or unsafe old history is not reintroduced into the prompt',
    () async {
      final harness = RuntimeHarness();
      await harness.setUp();
      try {
        final source = harness.addText('a', '资料', '当前资料');
        final conversationId = await harness.controller.startConversation(
          ConversationScope.item,
          scopeId: 'a',
        );
        harness.controller.data.conversationTurns.add(
          ConversationTurn(
            id: 'old-turn',
            conversationId: conversationId,
            question: '旧问题',
            status: 'completed',
            answer: '旧答案不能再次进入提示词',
            inputItemIds: ['a'],
            sourceVersions: {'a': source.contentVersion},
            sourceFingerprints: {'a': 'stale-fingerprint'},
          ),
        );
        harness.store.saveWithRuntime(
          harness.controller.data,
          harness.controller.runtime,
        );

        await harness.controller.submitQuestion(conversationId, '新问题');
        await harness.controller.waitForIdle();
        expect(
          jsonEncode(harness.prompts.single),
          isNot(contains('旧答案不能再次进入提示词')),
        );
      } finally {
        await harness.dispose();
      }
    },
  );

  test('configuration change blocks retry of a paused turn', () async {
    final harness = RuntimeHarness(
      handler: (payload, request) async {
        throw const SocketException('transient');
      },
    );
    await harness.setUp();
    try {
      harness.addText('a', '资料', '配置变化资料');
      final conversationId = await harness.controller.startConversation(
        ConversationScope.item,
        scopeId: 'a',
      );
      final turnId = await harness.controller.submitQuestion(
        conversationId,
        '配置问题',
      );
      await harness.controller.waitForIdle();
      await harness.controller.saveSettings(
        AppSettings(textModel: 'changed-model'),
      );

      await expectLater(harness.controller.retryTurn(turnId), throwsStateError);
      expect(harness.controller.data.conversationTurns.single.status, 'paused');
    } finally {
      await harness.dispose();
    }
  });

  test('accepted and restored revisions drop only their target self knowledge proof', () async {
    final harness = RuntimeHarness();
    await harness.setUp();
    try {
      final source = harness.addText('a', '资料A', '资料A正文');
      final topic = Topic(
        id: 'topic',
        title: '主题',
        question: '问题',
        currentKnowledgeRevisionId: 'r1',
      );
      final r1 = _revision(
        id: 'r1',
        topicId: topic.id,
        sourceId: source.id,
        source: source,
        brief: 'R1',
      );
      harness.controller.data.topics.add(topic);
      harness.controller.data.knowledgeRevisions.add(r1);
      harness.controller.data.knowledgeProposals.add(
        KnowledgeProposal(
          id: 'proposal',
          topicId: topic.id,
          baseRevisionId: r1.id,
          title: topic.title,
          question: topic.question,
          presentation: ReadingPresentation(brief: 'R2'),
          inputItemIds: ['a'],
          sourceVersions: {'a': source.contentVersion},
          sourceFingerprints: {
            'a': sourceFingerprint(source),
            'knowledge:${topic.id}': _revisionFingerprint(r1),
          },
        ),
      );
      harness.store.saveWithRuntime(
        harness.controller.data,
        harness.controller.runtime,
      );

      final r2Id = await harness.controller.acceptKnowledgeProposal('proposal');
      final r2 = harness.controller.data.knowledgeRevisions.singleWhere(
        (revision) => revision.id == r2Id,
      );
      expect(r2.sourceFingerprints, isNot(contains('knowledge:${topic.id}')));
      expect(harness.controller.isKnowledgeRevisionReusable(r2), isTrue);

      final restoredId = await harness.controller.restoreKnowledgeRevision(
        r2.id,
      );
      final restored = harness.controller.data.knowledgeRevisions.singleWhere(
        (revision) => revision.id == restoredId,
      );
      expect(
        restored.sourceFingerprints,
        isNot(contains('knowledge:${topic.id}')),
      );
      expect(restored.stale, isFalse);
      expect(harness.controller.isKnowledgeRevisionReusable(restored), isTrue);
    } finally {
      await harness.dispose();
    }
  });

  test('new source proposal receives current revision knowledge and carries ancestor inputs', () async {
    final captured = <Map<String, dynamic>>[];
    final harness = RuntimeHarness(
      handler: (payload, request) async {
        captured.add(payload);
        return {
          'answer': 'B 带来增量',
          'presentation': {'brief': 'B 带来增量'},
          'evidence': const [],
          'remainingGaps': const [],
        };
      },
    );
    await harness.setUp();
    try {
      final sourceA = harness.addText('a', '资料A', '祖先资料A');
      final sourceB = harness.addText('b', '资料B', '新增资料B');
      sourceB
        ..analysis = Analysis(
          summary: '新增资料B摘要',
          sourceIds: ['b'],
          inputItemIds: ['b'],
        )
        ..status = 'ready';
      final topic = Topic(
        id: 'topic',
        title: '主题',
        question: '问题',
        sourceIds: ['a', 'b'],
        currentKnowledgeRevisionId: 'r1',
      );
      final r1 = _revision(
        id: 'r1',
        topicId: topic.id,
        sourceId: sourceA.id,
        source: sourceA,
        brief: 'A 形成的R1',
      );
      harness.controller.data.topics.add(topic);
      harness.controller.data.knowledgeRevisions.add(r1);
      harness.controller.runtime.jobs.add(
        BackgroundJob(
          id: 'knowledge-job',
          type: 'knowledgeProposal',
          entityId: topic.id,
          checkpoint: {
            'configuration': jsonEncode([
              harness.controller.data.settings.endpoint,
              harness.controller.data.settings.textModel,
              harness.controller.data.settings.visionModel,
              harness.controller.data.settings.searchEndpoint,
            ]),
            'newSourceIds': ['b'],
            'inputIds': ['b'],
          },
        ),
      );
      harness.store.saveWithRuntime(
        harness.controller.data,
        harness.controller.runtime,
      );

      await harness.controller.resumeTasks();
      await harness.controller.waitForIdle();

      expect(captured, hasLength(1));
      expect(
        (captured.single['knowledgeRevisions'] as List).map(
          (revision) => revision['id'],
        ),
        contains('r1'),
      );
      final proposal = harness.controller.data.knowledgeProposals.singleWhere(
        (entry) => entry.originSourceId == 'b',
      );
      expect(proposal.inputItemIds, containsAll(['a', 'b']));
      expect(proposal.sourceFingerprints, contains('knowledge:${topic.id}'));
    } finally {
      await harness.dispose();
    }
  });

  test('visual PDF asset proof inherited through history makes later revision stale after byte mutation', () async {
    final harness = RuntimeHarness();
    await harness.setUp();
    try {
      final source = await harness.addAssetItem(
        id: 'a',
        kind: ItemKind.pdf,
        name: 'proof.pdf',
        bytes: [1, 2, 3],
        pdfPageCount: 1,
      );
      final assetPath = harness.controller.assetPath(source.assets.single);
      final assetHash = sha256
          .convert(File(assetPath).readAsBytesSync())
          .toString();
      final topic = Topic(
        id: 'topic',
        title: '主题',
        question: '问题',
        currentKnowledgeRevisionId: 'r1',
      );
      final r1 = _revision(
        id: 'r1',
        topicId: topic.id,
        sourceId: source.id,
        source: source,
        brief: 'PDF R1',
      );
      r1.sourceFingerprints['asset:${source.id}'] = assetHash;
      harness.controller.data.topics.add(topic);
      harness.controller.data.knowledgeRevisions.add(r1);
      harness.controller.data.conversations.add(
        Conversation(
          id: 'conversation',
          title: '会话',
          scope: ConversationScope.topic,
          scopeId: topic.id,
        ),
      );
      harness.controller.data.conversationTurns.add(
        ConversationTurn(
          id: 'turn',
          conversationId: 'conversation',
          question: 'PDF 结论是什么？',
          status: 'completed',
          answer: 'PDF 历史回答',
          inputItemIds: ['a'],
          sourceVersions: {'a': source.contentVersion},
          sourceFingerprints: {
            'a': sourceFingerprint(source),
            'asset:${source.id}': assetHash,
            'knowledge:${topic.id}': _revisionFingerprint(r1),
          },
        ),
      );
      harness.store.saveWithRuntime(
        harness.controller.data,
        harness.controller.runtime,
      );

      final proposalId = await harness.controller.proposeKnowledgeFromTurn(
        'turn',
        topicId: topic.id,
      );
      final r2Id = await harness.controller.acceptKnowledgeProposal(proposalId);
      final r2 = harness.controller.data.knowledgeRevisions.singleWhere(
        (revision) => revision.id == r2Id,
      );
      expect(r2.sourceFingerprints['asset:${source.id}'], assetHash);
      expect(r2.sourceFingerprints, isNot(contains('knowledge:${topic.id}')));
      expect(harness.controller.isKnowledgeRevisionReusable(r2), isTrue);

      File(assetPath).writeAsBytesSync([9, 9, 9], flush: true);
      expect(source.contentVersion, 1);
      expect(harness.controller.isKnowledgeRevisionReusable(r2), isFalse);
    } finally {
      await harness.dispose();
    }
  });

  test('blocked knowledge proposal keeps frozen base and cannot silently target newer revision', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final harness = RuntimeHarness(
      handler: (payload, request) async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
        return {
          'answer': '迟到的增量建议',
          'presentation': {'brief': '迟到的增量建议'},
          'evidence': const [],
          'remainingGaps': const [],
        };
      },
    );
    await harness.setUp();
    try {
      final source = harness.addText('a', '资料A', '新增资料A');
      source.analysis = Analysis(
        summary: '新增资料A摘要',
        sourceIds: ['a'],
        inputItemIds: ['a'],
      );
      source.status = 'ready';
      final topic = Topic(
        id: 'topic',
        title: '主题',
        question: '如何更新？',
        sourceIds: ['a'],
        currentKnowledgeRevisionId: 'r1',
      );
      harness.controller.data.topics.add(topic);
      harness.controller.data.knowledgeRevisions.add(
        _revision(
          id: 'r1',
          topicId: topic.id,
          sourceId: source.id,
          source: source,
          brief: '旧知识R1',
        ),
      );
      harness.controller.runtime.jobs.add(
        BackgroundJob(
          id: 'knowledge-job',
          type: 'knowledgeProposal',
          entityId: topic.id,
          checkpoint: {
            'configuration': jsonEncode([
              harness.controller.data.settings.endpoint,
              harness.controller.data.settings.textModel,
              harness.controller.data.settings.visionModel,
              harness.controller.data.settings.searchEndpoint,
            ]),
            'newSourceIds': ['a'],
            'inputIds': ['a'],
          },
        ),
      );
      harness.store.saveWithRuntime(
        harness.controller.data,
        harness.controller.runtime,
      );

      await harness.controller.resumeTasks();
      await entered.future.timeout(const Duration(seconds: 2));
      harness.controller.data.knowledgeProposals.add(
        KnowledgeProposal(
          id: 'manual-r2',
          topicId: topic.id,
          baseRevisionId: 'r1',
          title: topic.title,
          question: topic.question,
          presentation: ReadingPresentation(brief: '人工确认R2'),
          inputItemIds: ['a'],
          sourceVersions: {'a': source.contentVersion},
          sourceFingerprints: {'a': sourceFingerprint(source)},
        ),
      );
      final r2 = await harness.controller.acceptKnowledgeProposal('manual-r2');
      expect(topic.currentKnowledgeRevisionId, r2);

      release.complete();
      await harness.controller.waitForIdle();

      final late = harness.controller.data.knowledgeProposals
          .where((proposal) => proposal.originSourceId == 'a')
          .toList();
      expect(
        late.any((proposal) => proposal.baseRevisionId == r2),
        isFalse,
        reason: 'late model output must not silently rebase onto R2',
      );
      for (final proposal in late) {
        expect(proposal.baseRevisionId, 'r1');
        await expectLater(
          harness.controller.acceptKnowledgeProposal(proposal.id),
          throwsStateError,
        );
      }
    } finally {
      if (!release.isCompleted) release.complete();
      await harness.dispose();
    }
  });

  test(
    'explicit selected source filters other-source knowledge and topic context',
    () async {
      final harness = RuntimeHarness();
      await harness.setUp();
      try {
        final sourceA = harness.addText('a', '资料A', '资料A正文');
        final sourceB = harness.addText('b', '资料B', '资料B正文');
        final topic = Topic(
          id: 'topic',
          title: '主题',
          question: '问题',
          currentKnowledgeRevisionId: 'rev-b',
          contextEntries: [
            ContextEntry(
              id: 'context-a',
              kind: 'note',
              text: 'A 的确认背景',
              confirmed: true,
              sourceId: 'a',
              sourceVersion: sourceA.contentVersion,
            ),
            ContextEntry(
              id: 'context-b',
              kind: 'note',
              text: 'B 的确认背景不得进入',
              confirmed: true,
              sourceId: 'b',
              sourceVersion: sourceB.contentVersion,
            ),
          ],
        );
        harness.controller.data.topics.add(topic);
        harness.controller.data.knowledgeRevisions.add(
          _revision(
            id: 'rev-b',
            topicId: topic.id,
            sourceId: 'b',
            source: sourceB,
            brief: 'B 派生确认知识不得进入',
          ),
        );
        harness.store.saveWithRuntime(
          harness.controller.data,
          harness.controller.runtime,
        );

        final conversationId = await harness.controller.startConversation(
          ConversationScope.library,
          sourceIds: ['a'],
        );
        await harness.controller.submitQuestion(conversationId, '只看 A');
        await harness.controller.waitForIdle();

        final payload = harness.prompts.single;
        expect(
          jsonEncode(payload['knowledgeRevisions'] ?? []),
          isNot(contains('rev-b')),
        );
        final context = payload['extraContext']['userContext'] as List;
        expect(context.map((entry) => entry['id']), ['context-a']);
        expect(jsonEncode(payload), isNot(contains('B 的确认背景不得进入')));
      } finally {
        await harness.dispose();
      }
    },
  );

  test(
    'conversation and knowledge result notifications keep their entity types',
    () async {
      var responses = 0;
      final harness = RuntimeHarness(
        handler: (payload, request) async {
          responses++;
          return {
            'answer': responses == 1 ? '对话完成' : '知识建议完成',
            'presentation': {'brief': responses == 1 ? '对话完成' : '知识建议完成'},
            'evidence': const [],
            'remainingGaps': const [],
          };
        },
      );
      await harness.setUp();
      try {
        final source = harness.addText('a', '资料A', '资料A正文');
        source.analysis = Analysis(
          summary: '资料A摘要',
          sourceIds: ['a'],
          inputItemIds: ['a'],
        );
        source.status = 'ready';
        final conversationId = await harness.controller.startConversation(
          ConversationScope.item,
          scopeId: 'a',
        );
        final turnId = await harness.controller.submitQuestion(
          conversationId,
          '通知我',
        );
        await harness.controller.waitForIdle();

        final topic = Topic(
          id: 'topic',
          title: '主题',
          question: '问题',
          sourceIds: ['a'],
        );
        harness.controller.data.topics.add(topic);
        harness.controller.runtime.jobs.add(
          BackgroundJob(
            id: 'knowledge-job',
            type: 'knowledgeProposal',
            entityId: topic.id,
            checkpoint: {
              'configuration': jsonEncode([
                harness.controller.data.settings.endpoint,
                harness.controller.data.settings.textModel,
                harness.controller.data.settings.visionModel,
                harness.controller.data.settings.searchEndpoint,
              ]),
              'newSourceIds': ['a'],
              'inputIds': ['a'],
            },
          ),
        );
        harness.store.saveWithRuntime(
          harness.controller.data,
          harness.controller.runtime,
        );
        await harness.controller.resumeTasks();
        await harness.controller.waitForIdle();

        expect(
          harness.native.notifications
              .where((entry) => entry.entityType == 'conversation')
              .map((entry) => entry.entityId),
          contains(turnId),
        );
        expect(
          harness.native.notifications
              .where((entry) => entry.entityType == 'knowledge')
              .map((entry) => entry.entityId),
          contains(topic.id),
        );
      } finally {
        await harness.dispose();
      }
    },
  );

  test(
    'image and PDF proof use normalized image and rendered page payloads',
    () async {
      final imageHarness = RuntimeHarness();
      await imageHarness.setUp();
      try {
        final image = await imageHarness.addAssetItem(
          id: 'img',
          kind: ItemKind.image,
          name: 'image.png',
          bytes: [1, 2, 3],
        );
        final conversationId = await imageHarness.controller.startConversation(
          ConversationScope.item,
          scopeId: image.id,
        );
        await imageHarness.controller.submitQuestion(conversationId, '图里是什么？');
        await imageHarness.controller.waitForIdle();
        expect(imageHarness.native.imageReads, 1);
        expect(
          imageHarness.native.lastImagePath,
          imageHarness.controller.assetPath(image.assets.single),
        );
        final turn = imageHarness.controller.data.conversationTurns.single;
        expect(turn.visualEvidence.single.sourceId, 'img');
        expect(turn.visualEvidence.single.unverified, isTrue);
      } finally {
        await imageHarness.dispose();
      }

      final pdfHarness = RuntimeHarness();
      await pdfHarness.setUp();
      try {
        final pdf = await pdfHarness.addAssetItem(
          id: 'pdf',
          kind: ItemKind.pdf,
          name: 'doc.pdf',
          bytes: [4, 5, 6],
          pdfPageCount: 3,
        );
        final conversationId = await pdfHarness.controller.startConversation(
          ConversationScope.item,
          scopeId: pdf.id,
        );
        await pdfHarness.controller.submitQuestion(
          conversationId,
          'PDF 第一页是什么？',
        );
        await pdfHarness.controller.waitForIdle();
        expect(pdfHarness.native.pdfReads, 1);
        expect(
          pdfHarness.native.lastPdfPath,
          pdfHarness.controller.assetPath(pdf.assets.single),
        );
        expect(pdfHarness.native.lastPdfStartPage, 0);
        expect(pdfHarness.native.lastPdfMaxPages, 1);
        final turn = pdfHarness.controller.data.conversationTurns.single;
        expect(turn.visualEvidence.single.page, 1);
        expect(turn.visualEvidence.single.unverified, isTrue);
      } finally {
        await pdfHarness.dispose();
      }
    },
  );

  test('restored request-pending conversation pauses and old v1 jobs remain loadable', () async {
    final temp = Directory.systemTemp.createTempSync(
      'readlater-conversation-restore-',
    );
    final store = LocalStore(temp.path);
    try {
      store.saveWithRuntime(
        AppData(
          conversations: [
            Conversation(
              id: 'conversation',
              title: '会话',
              scope: ConversationScope.library,
            ),
          ],
          conversationTurns: [
            ConversationTurn(
              id: 'turn',
              conversationId: 'conversation',
              question: '恢复问题',
              status: 'running',
              requestPending: true,
            ),
          ],
        ),
        RuntimeState(
          jobs: [
            BackgroundJob(
              id: 'conversation-job',
              type: 'conversation',
              entityId: 'turn',
              status: 'running',
              lane: 'interactive',
              checkpoint: {'requestPending': true},
            ),
            BackgroundJob(
              id: 'legacy-job',
              type: 'analysis',
              entityId: 'missing-historic-source',
              version: 1,
            ),
          ],
        ),
      );

      final controller = AppController(store: store, secrets: RuntimeSecrets());
      await controller.initialize();
      expect(controller.data.conversationTurns.single.status, 'interrupted');
      expect(controller.data.conversationTurns.single.requestPending, isTrue);
      final conversationJob = controller.runtime.jobs.singleWhere(
        (job) => job.id == 'conversation-job',
      );
      expect(conversationJob.status, 'paused');
      expect(conversationJob.checkpoint['requiresAttention'], isTrue);
      expect(
        controller.runtime.jobs
            .singleWhere((job) => job.id == 'legacy-job')
            .version,
        1,
      );
      controller.dispose();
    } finally {
      temp.deleteSync(recursive: true);
    }
  });
}
