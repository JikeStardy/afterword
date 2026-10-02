import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:readlater/core/app_controller.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/retrieval.dart';
import 'package:readlater/core/store.dart';
import 'package:readlater/services/intelligence_service.dart';

class DialogueSecrets implements SecretStore {
  @override
  Future<String?> read(String key) async => 'fixture';
  @override
  Future<void> write(String key, String value) async {}
}

class FailingDialogueStore extends LocalStore {
  FailingDialogueStore(super.root);
  bool fail = false;
  @override
  void saveWithRuntime(AppData data, RuntimeState runtime) {
    if (fail) throw StateError('fixture save failure');
    super.saveWithRuntime(data, runtime);
  }
}

http.Response reply(Json answer) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'content': jsonEncode(answer)},
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late AppController controller;
  late FailingDialogueStore store;
  late int calls;
  setUp(() async {
    calls = 0;
    temp = Directory.systemTemp.createTempSync('knowledge-dialogue-');
    store = FailingDialogueStore(temp.path);
    controller = AppController(
      store: store,
      secrets: DialogueSecrets(),
      intelligence: IntelligenceService(
        client: MockClient((request) async {
          calls++;
          return reply({'answer': '答案', 'evidence': [], 'remainingGaps': []});
        }),
      ),
    );
    await controller.initialize();
    await controller.saveSettings(AppSettings(textModel: 'fixture'));
    controller.data.items.add(
      LibraryItem(
        id: 'a',
        title: '全文',
        kind: ItemKind.text,
        body: '前文 ${'资料' * 10000} 尾部事实：稀有尾部结论',
      ),
    );
    store.saveWithRuntime(controller.data, controller.runtime);
  });
  tearDown(() async {
    store.fail = false;
    await controller.waitForIdle();
    controller.dispose();
    temp.deleteSync(recursive: true);
  });
  test(
    'question records tail windows, persists answer and source dependencies',
    () async {
      final id = await controller.startConversation(
        ConversationScope.item,
        scopeId: 'a',
      );
      final turnId = await controller.submitQuestion(id, '稀有尾部结论是什么？');
      await controller.waitForIdle();
      final turn = controller.data.conversationTurns.single;
      expect(turn.id, turnId);
      expect(turn.status, 'completed', reason: turn.error);
      expect(turn.answer, '答案');
      expect(turn.windows.map((w) => w.text).join(), contains('稀有尾部结论'));
      expect(turn.inputItemIds, contains('a'));
      expect(turn.calls, 1);
      expect(calls, 1);
      expect(store.load().conversationTurns.single.answer, '答案');
    },
  );
  test(
    'accept is idempotent; failed store leaves proposal and topic unchanged',
    () async {
      final source = controller.data.items.single;
      controller.data.topics.add(
        Topic(id: 'topic', title: '主题', question: '问题'),
      );
      controller.data.knowledgeProposals.add(
        KnowledgeProposal(
          id: 'proposal',
          topicId: 'topic',
          title: '主题',
          question: '问题',
          presentation: ReadingPresentation(brief: '新认识'),
          inputItemIds: ['a'],
          sourceVersions: {'a': source.contentVersion},
          sourceFingerprints: {'a': sourceFingerprint(source)},
        ),
      );
      store.saveWithRuntime(controller.data, controller.runtime);
      store.fail = true;
      await expectLater(
        controller.acceptKnowledgeProposal('proposal'),
        throwsStateError,
      );
      expect(controller.data.knowledgeProposals.single.status, 'pending');
      expect(controller.data.knowledgeRevisions, isEmpty);
      expect(controller.data.topics.single.currentKnowledgeRevisionId, isNull);
      store.fail = false;
      final revision = await controller.acceptKnowledgeProposal('proposal');
      expect(await controller.acceptKnowledgeProposal('proposal'), revision);
      expect(controller.data.knowledgeRevisions, hasLength(1));
    },
  );
  test(
    'revision mutation and stale proposals reject late acceptance',
    () async {
      final source = controller.data.items.single;
      controller.data.knowledgeProposals.add(
        KnowledgeProposal(
          id: 'p',
          title: '认识',
          question: '问题',
          inputItemIds: ['a'],
          sourceVersions: {'a': 1},
          sourceFingerprints: {'a': sourceFingerprint(source)},
        ),
      );
      source.body = 'changed';
      await expectLater(
        controller.acceptKnowledgeProposal('p'),
        throwsStateError,
      );
      expect(controller.data.knowledgeRevisions, isEmpty);
    },
  );
  test(
    'failed submission does not expose a half saved turn or queue job',
    () async {
      final id = await controller.startConversation(ConversationScope.library);
      store.fail = true;
      await expectLater(controller.submitQuestion(id, '问题'), throwsStateError);
      expect(controller.data.conversationTurns, isEmpty);
      expect(
        controller.runtime.jobs.where((j) => j.type == 'conversation'),
        isEmpty,
      );
    },
  );
  test(
    'oversized confirmed base pauses incremental update without replacement',
    () async {
      final source = controller.data.items.single;
      final b = LibraryItem(
        id: 'b',
        title: '新资料',
        kind: ItemKind.text,
        body: '新证据',
        analysis: Analysis(summary: '新认识', inputItemIds: ['b']),
      );
      controller.data.items.add(b);
      controller.data.topics.add(
        Topic(
          id: 't',
          title: '主题',
          question: '增量更新',
          currentKnowledgeRevisionId: 'r1',
        ),
      );
      controller.data.knowledgeRevisions.add(
        KnowledgeRevision(
          id: 'r1',
          topicId: 't',
          presentation: ReadingPresentation(brief: '旧知识' * 20000),
          inputItemIds: ['a'],
          sourceVersions: {'a': source.contentVersion},
          sourceFingerprints: {'a': sourceFingerprint(source)},
        ),
      );
      controller.runtime.jobs.add(
        BackgroundJob(
          id: 'incremental',
          type: 'knowledgeProposal',
          entityId: 't',
          checkpoint: {
            'configuration': jsonEncode([
              controller.data.settings.endpoint,
              controller.data.settings.textModel,
              controller.data.settings.visionModel,
              controller.data.settings.searchEndpoint,
            ]),
            'newSourceIds': ['b'],
            'inputIds': ['b'],
          },
        ),
      );
      await controller.resumeTasks();
      await controller.waitForIdle();
      expect(controller.data.knowledgeProposals, isEmpty);
      expect(controller.data.topics.single.currentKnowledgeRevisionId, 'r1');
      expect(controller.runtime.jobs.single.status, 'paused');
      expect(controller.runtime.jobs.single.error, contains('无法安全'));
      expect(calls, 0);
    },
  );
}
