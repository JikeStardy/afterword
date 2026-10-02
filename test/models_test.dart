import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/services/knowledge_service.dart';

void main() {
  test('restoring a snapshot retains original content, citations and tracking scope', () {
    final data = AppData();
    data.items.add(
      LibraryItem(
        id: 'i1',
        title: '读书',
        kind: ItemKind.text,
        body: '原文',
        notes: '适用条件',
        analysis: Analysis(
          summary: '认识',
          insights: ['有条件适用'],
          sourceIds: ['i1'],
        ),
      ),
    );
    data.topics.add(
      Topic(
        id: 't1',
        title: '知识管理',
        question: '如何积累认识？',
        tracking: true,
        authorizedScope: '如何积累认识？',
        callLimit: 4,
      ),
    );
    final restored = AppData.fromJson(data.toJson());
    expect(restored.items.single.body, '原文');
    expect(restored.items.single.analysis!.sourceIds, ['i1']);
    expect(restored.topics.single.authorizedScope, '如何积累认识？');
    expect(restored.topics.single.tracking, isTrue);
    expect(restored.topics.single.callLimit, 4);
  });

  test(
    'preferences keep explicit interests separate from inferred attention',
    () {
      final settings = AppSettings(
        explicitInterests: ['适用条件'],
        inferredInterests: ['笔记工具'],
        readingPreset: ReadingPreset.magazine,
        readerFontScale: 1.35,
      );
      final copy = AppSettings.fromJson(settings.toJson());
      expect(copy.explicitInterests, ['适用条件']);
      expect(copy.inferredInterests, ['笔记工具']);
      expect(copy.readingPreset, ReadingPreset.magazine);
      expect(copy.readerFontScale, 1.35);
      expect(
        AppSettings.fromJson({'readingPreset': 'unknown'}).readingPreset,
        ReadingPreset.editorial,
      );
      expect(AppSettings.fromJson({'readerFontScale': 9}).readerFontScale, 1.6);
      expect(
        AppSettings.fromJson({'readerFontScale': .1}).readerFontScale,
        .85,
      );
      expect(
        copy.toJson().keys.any((key) => key.toLowerCase().contains('key')),
        isFalse,
      );
    },
  );

  test('unknown backup schema is rejected instead of silently losing data', () {
    expect(() => AppData.fromJson({'version': 999}), throwsFormatException);
  });

  test('markdown export does not duplicate summary when brief is absent', () {
    final markdown = KnowledgeService.exportItemMarkdown(
      LibraryItem(
        id: 'i1',
        title: '文章',
        kind: ItemKind.text,
        analysis: Analysis(summary: '完整分析正文'),
      ),
    );

    expect(RegExp('完整分析正文').allMatches(markdown), hasLength(1));
  });

  test(
    'topic scope preserves automatic null separately from explicit empty',
    () {
      final automatic = Topic(id: 'auto', title: '自动', question: '问题');
      final explicitEmpty = Topic(
        id: 'empty',
        title: '空范围',
        question: '问题',
        selectedSourceIds: [],
        selectedContextIds: [],
      );

      final copy = AppData.fromJson(
        AppData(topics: [automatic, explicitEmpty]).toJson(),
      );

      expect(copy.topics[0].selectedSourceIds, isNull);
      expect(copy.topics[0].selectedContextIds, isNull);
      expect(copy.topics[1].selectedSourceIds, isEmpty);
      expect(copy.topics[1].selectedContextIds, isEmpty);
    },
  );

  test('v3 snapshot round trips work state, structured content and insight anchors', () {
    final data = AppData(
      items: [
        LibraryItem(
          id: 'i1',
          title: '结构化文章',
          kind: ItemKind.text,
          readCount: 9,
          workState: WorkState.snoozed,
          snoozedUntil: DateTime.utc(2026, 9, 23),
          contentVersion: 2,
          contentBlocks: [
            ContentBlock(
              id: 'b1',
              kind: ContentBlockKind.heading,
              text: '标题',
              level: 2,
            ),
            ContentBlock(
              id: 'b2',
              kind: ContentBlockKind.paragraph,
              text: '正文',
            ),
          ],
          readingPosition: ReadingPosition(blockId: 'b2', offset: 3),
          readerFontScale: 1.3,
          annotations: [
            Annotation(
              id: 'a1',
              anchor: EvidenceAnchor(
                sourceId: 'i1',
                sourceVersion: 2,
                blockId: 'b2',
                start: 0,
                end: 2,
                quote: '正文',
              ),
              note: '批注',
            ),
          ],
          analysis: Analysis(
            summary: '总结',
            brief: '短导读',
            insights: ['旧 insight'],
            sourceIds: ['i1'],
            structuredInsights: [
              Insight(
                id: 's1',
                title: '适用条件改变',
                finding: '新发现',
                change: '改变了旧认识',
                impact: '影响个人决策',
                evidence: [
                  EvidenceAnchor(
                    sourceId: 'i1',
                    sourceVersion: 2,
                    blockId: 'b2',
                    quote: '正文',
                  ),
                ],
                unknowns: ['仍未知'],
                verdict: 'doubt',
                stale: true,
              ),
            ],
          ),
        ),
      ],
      topics: [
        Topic(
          id: 't1',
          title: '主题',
          question: '问题',
          selectedSourceIds: [],
          selectedContextIds: ['c1'],
          contextEntries: [
            ContextEntry(
              id: 'c1',
              kind: 'judgement',
              text: '个人判断',
              confirmed: true,
              sourceId: 'i1',
              sourceVersion: 2,
              updatedAt: DateTime.utc(2026, 9, 22),
            ),
          ],
          overviewStale: true,
          reviewAt: DateTime.utc(2026, 10),
          presentation: ReadingPresentation(
            brief: '主题导读',
            sections: [ReadingSection(title: '共识', body: '正文 [i1]')],
          ),
        ),
      ],
      runs: [
        ResearchRun(
          id: 'r1',
          goal: '研究',
          report: '报告 [S1]',
          presentation: ReadingPresentation(
            brief: '研究导读',
            sections: [ReadingSection(title: '结论', body: '证据 [S1]')],
          ),
        ),
      ],
      todaySnapshots: [
        TodaySnapshot(
          day: '2026-09-22',
          entries: [
            TodayEntry(
              id: 'te1',
              entityType: 'item',
              entityId: 'i1',
              reason: '到期复查',
              relatedIds: ['t1'],
            ),
          ],
          skippedIds: ['old'],
          deferredUntil: {'later': DateTime.utc(2026, 9, 24)},
        ),
      ],
    );

    final copy = AppData.fromJson(data.toJson());
    expect(copy.toJson()['version'], 4);
    expect(copy.items.single.workState, WorkState.snoozed);
    expect(copy.items.single.readCount, 9);
    expect(
      copy.items.single.contentBlocks.first.kind,
      ContentBlockKind.heading,
    );
    expect(copy.items.single.annotations.single.anchor.blockId, 'b2');
    expect(copy.items.single.analysis!.brief, '短导读');
    expect(
      copy.items.single.analysis!.structuredInsights.single.title,
      '适用条件改变',
    );
    expect(copy.items.single.analysis!.structuredInsights.single.stale, isTrue);
    expect(copy.topics.single.selectedSourceIds, isEmpty);
    expect(copy.topics.single.presentation!.sections.single.title, '共识');
    expect(copy.runs.single.presentation!.brief, '研究导读');
    expect(copy.topics.single.contextEntries.single.confirmed, isTrue);
    expect(
      copy.todaySnapshots.single.deferredUntil['later'],
      DateTime.utc(2026, 9, 24),
    );
  });

  test(
    'v1 and v2 snapshots migrate without inferring completion from read count',
    () {
      final migrated = AppData.fromJson({
        'version': 1,
        'items': [
          {
            'id': 'i1',
            'title': '旧文章',
            'kind': 'text',
            'readCount': 12,
            'status': 'ready',
          },
        ],
      });

      expect(migrated.items.single.readCount, 12);
      expect(migrated.items.single.workState, WorkState.pending);
      expect(migrated.toJson()['version'], 4);
    },
  );

  test('runtime state round trips durable jobs and notification outbox', () {
    final runtime = RuntimeState(
      epoch: 3,
      jobs: [
        BackgroundJob(
          id: 'job1',
          type: 'analyzeItem',
          entityId: 'i1',
          status: 'running',
          stage: 'chunking',
          checkpoint: {'block': 2},
          epoch: 3,
          attempts: 1,
          createdAt: DateTime.utc(2026, 9, 22),
          error: 'possible duplicate billing',
        ),
      ],
      outbox: [
        PendingNotification(
          id: 'n1',
          channel: 'results',
          title: '完成',
          body: '分析完成',
          entityType: 'item',
          entityId: 'i1',
          createdAt: DateTime.utc(2026, 9, 22),
        ),
      ],
    );

    final copy = RuntimeState.fromJson(runtime.toJson());
    expect(copy.epoch, 3);
    expect(copy.jobs.single.checkpoint['block'], 2);
    expect(copy.outbox.single.channel, 'results');
  });

  test('research run round trips durable stage checkpoint', () {
    final run = ResearchRun(
      id: 'r',
      goal: '问题',
      calls: 3,
      callLimit: 4,
      pendingStage: 'compare',
      pendingQuery: '问题\n补充查证：证据',
      requestPending: true,
    );

    final copy = ResearchRun.fromJson(run.toJson());
    expect(copy.pendingStage, 'compare');
    expect(copy.pendingQuery, contains('补充查证'));
    expect(copy.requestPending, isTrue);
    expect(copy.calls, 3);
    expect(copy.callLimit, 4);
  });
}
