import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/models.dart';

void main() {
  test('restored dialogue budgets cannot bypass settings limits', () {
    final valid = ConversationTurn(
      id: 'turn-1',
      conversationId: 'conversation-1',
      question: '继续',
    ).toJson();
    for (final invalid in [
      {'callLimit': 0},
      {'callLimit': 21},
      {'textBudgetChars': 7999},
      {'textBudgetChars': 64001},
      {'calls': -1},
      {'calls': 6},
    ]) {
      expect(
        () => ConversationTurn.fromJson({...valid, ...invalid}),
        throwsFormatException,
        reason: invalid.toString(),
      );
    }
    expect(ConversationTurn.fromJson({...valid, 'calls': 5}).calls, 5);
  });

  test('v4 snapshot round trips dialogue and knowledge records', () {
    final createdAt = DateTime.utc(2026, 10, 2, 8);
    final completedAt = DateTime.utc(2026, 10, 2, 8, 3);
    final evidence = EvidenceAnchor(
      sourceId: 'item-1',
      sourceVersion: 2,
      blockId: 'body-1',
      windowId: 'window-1',
      assetFingerprint: 'asset-sha',
      quote: '原文证据',
    );
    final presentation = ReadingPresentation(
      brief: '确认后的认识',
      sections: [ReadingSection(title: '结论', body: '来自证据')],
    );
    final data = AppData(
      settings: AppSettings(
        conversationCallLimit: 7,
        modelTextContextChars: 32000,
      ),
      topics: [
        Topic(
          id: 'topic-1',
          title: '知识主题',
          question: '如何持续学习？',
          overview: '旧综合不应自动成为确认知识',
          currentKnowledgeRevisionId: 'rev-1',
        ),
      ],
      conversations: [
        Conversation(
          id: 'conversation-1',
          title: '问这篇资料',
          scope: ConversationScope.item,
          scopeId: 'item-1',
          sourceIds: ['item-1'],
          createdAt: createdAt,
          updatedAt: completedAt,
        ),
      ],
      conversationTurns: [
        ConversationTurn(
          id: 'turn-1',
          conversationId: 'conversation-1',
          question: '这里的适用边界是什么？',
          status: 'complete',
          stage: 'answered',
          answer: '适用于长期复盘。',
          evidence: [evidence],
          windows: [
            SourceWindow(
              id: 'window-1',
              sourceId: 'item-1',
              sourceVersion: 2,
              blockId: 'body-1',
              start: 10,
              end: 24,
              text: '原文证据',
              fingerprint: 'window-sha',
              readActionId: 'read-1',
            ),
          ],
          visualEvidence: [
            VisualEvidence(
              sourceId: 'item-1',
              sourceVersion: 2,
              assetFingerprint: 'asset-sha',
              page: 3,
              observation: '图中趋势上升',
            ),
          ],
          inputItemIds: ['item-1'],
          sourceVersions: {'item-1': 2},
          sourceFingerprints: {'item-1': 'source-sha'},
          calls: 2,
          callLimit: 7,
          textBudgetChars: 32000,
          createdAt: createdAt,
          completedAt: completedAt,
        ),
      ],
      segmentSummaries: [
        SourceSegmentSummary(
          id: 'summary-1',
          sourceId: 'item-1',
          sourceVersion: 2,
          rangeStart: 0,
          rangeEnd: 1200,
          fingerprint: 'segment-sha',
          summary: '分段摘要',
          evidence: [evidence],
          createdAt: createdAt,
        ),
      ],
      knowledgeProposals: [
        KnowledgeProposal(
          id: 'proposal-1',
          topicId: 'topic-1',
          baseRevisionId: 'rev-0',
          title: '持续学习',
          question: '如何持续学习？',
          presentation: presentation,
          inputItemIds: ['item-1'],
          sourceVersions: {'item-1': 2},
          sourceFingerprints: {'item-1': 'source-sha'},
          evidence: [evidence],
          relatedTopicIds: ['topic-2'],
          reason: '用户追问形成新认识',
          originTurnId: 'turn-1',
          status: 'accepted',
          acceptedRevisionId: 'rev-1',
          createdAt: createdAt,
        ),
      ],
      knowledgeRevisions: [
        KnowledgeRevision(
          id: 'rev-1',
          topicId: 'topic-1',
          parentId: 'rev-0',
          presentation: presentation,
          inputItemIds: ['item-1'],
          sourceVersions: {'item-1': 2},
          sourceFingerprints: {'item-1': 'source-sha'},
          evidence: [evidence],
          relatedTopicIds: ['topic-2'],
          reason: '用户接受提案',
          originTurnId: 'turn-1',
          humanEdited: true,
          createdAt: completedAt,
        ),
      ],
    );

    final copy = AppData.fromJson(data.toJson());

    expect(copy.toJson()['version'], 4);
    expect(copy.settings.conversationCallLimit, 7);
    expect(copy.settings.modelTextContextChars, 32000);
    expect(copy.topics.single.currentKnowledgeRevisionId, 'rev-1');
    expect(copy.conversations.single.scope, ConversationScope.item);
    expect(copy.conversations.single.sourceIds, ['item-1']);
    expect(copy.conversationTurns.single.windows.single.text, '原文证据');
    expect(copy.conversationTurns.single.evidence.single.windowId, 'window-1');
    expect(
      copy.conversationTurns.single.visualEvidence.single.unverified,
      isTrue,
    );
    expect(copy.segmentSummaries.single.promptVersion, 'source-v1');
    expect(copy.knowledgeProposals.single.presentation.brief, '确认后的认识');
    expect(copy.knowledgeRevisions.single.humanEdited, isTrue);
  });

  test('older snapshots read as v4 without turning topic overview into knowledge revision', () {
    final migrated = AppData.fromJson({
      'version': 3,
      'topics': [
        {'id': 'topic-1', 'title': '旧主题', 'question': '旧问题', 'overview': '旧综合'},
      ],
    });

    expect(migrated.toJson()['version'], 4);
    expect(migrated.topics.single.overview, '旧综合');
    expect(migrated.topics.single.currentKnowledgeRevisionId, isNull);
    expect(migrated.knowledgeRevisions, isEmpty);
  });

  test('dialogue settings and runtime schema validate supported ranges and versions', () {
    expect(() => AppSettings(conversationCallLimit: 0), throwsArgumentError);
    expect(() => AppSettings(conversationCallLimit: 21), throwsArgumentError);
    expect(() => AppSettings(modelTextContextChars: 7999), throwsArgumentError);
    expect(
      () => AppSettings(modelTextContextChars: 64001),
      throwsArgumentError,
    );

    final runtime = RuntimeState(
      jobs: [BackgroundJob(id: 'job-1', type: 'analysis', entityId: 'item-1')],
    );
    final copy = RuntimeState.fromJson(runtime.toJson());

    expect(runtime.toJson()['version'], 2);
    expect(copy.jobs.single.version, 2);
    expect(copy.jobs.single.lane, 'background');
    expect(RuntimeState.fromJson({'version': 1}).toJson()['version'], 2);
    expect(() => RuntimeState.fromJson({'version': 3}), throwsFormatException);
  });
}
