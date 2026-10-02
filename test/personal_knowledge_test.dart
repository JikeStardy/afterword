import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/app_controller.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/store.dart';
import 'package:readlater/platform/native_bridge.dart';
import 'package:readlater/services/intelligence_service.dart';

class KnowledgeSecrets implements SecretStore {
  @override
  Future<String?> read(String key) async => 'fixture';
  @override
  Future<void> write(String key, String value) async {}
}

class ScopedIntelligence extends IntelligenceService {
  Json researchContext = {};
  int synthesisCalls = 0;
  @override
  Future<Json> synthesize(
    AppSettings settings,
    String key,
    Topic topic,
    List<LibraryItem> items,
  ) async {
    synthesisCalls++;
    return {
      'overview': '旧批注的综述',
      'sourceIds': items.map((item) => item.id).toList(),
    };
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
    Json localContext = const {},
  }) async {
    researchContext = localContext;
    run.report = '有范围的研究';
    run.status = 'complete';
    await onProgress();
  }
}

class SummaryEvidenceIntelligence extends IntelligenceService {
  @override
  Future<Json> complete(
    AppSettings settings,
    String key,
    String prompt, {
    List<String> imageDataUrls = const [],
    Future<void>? abortTrigger,
  }) async => {'summary': 'SYNTHETIC_SUMMARY'};
  @override
  Future<Analysis> analyze(
    AppSettings settings,
    String key,
    LibraryItem item,
    List<LibraryItem> related, {
    List<String> imageDataUrls = const [],
    List<EvidenceAnchor>? availableEvidence,
  }) async {
    return Analysis(
      summary: 'SYNTHETIC_SUMMARY',
      sourceIds: [item.id],
      structuredInsights: item.body.contains('SYNTHETIC_SUMMARY')
          ? [
              Insight(
                id: 'insight',
                finding: '综合发现',
                evidence: [
                  EvidenceAnchor(
                    sourceId: item.id,
                    blockId: 'body-1',
                    sourceVersion: 1,
                    quote: 'SYNTHETIC_SUMMARY',
                  ),
                ],
              ),
            ]
          : [],
    );
  }
}

class EvidencePdfNative extends NativeBridge {
  @override
  Future<PdfPages> renderPdf(
    String path, {
    int startPage = 0,
    int maxPages = 4,
  }) async => const PdfPages(pageCount: 1, images: ['YWJj']);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final kind in [ItemKind.text, ItemKind.pdf]) {
    test(
      '${kind.name} final synthesis never certifies a synthetic excerpt as original evidence',
      () async {
        final directory = Directory.systemTemp.createTempSync(
          'readlater-final-anchor-',
        );
        final controller = AppController(
          store: LocalStore(directory.path),
          intelligence: SummaryEvidenceIntelligence(),
          native: EvidencePdfNative(),
          secrets: KnowledgeSecrets(),
        );
        try {
          await controller.initialize();
          await controller.saveSettings(
            AppSettings(textModel: 'fixture', visionModel: 'fixture'),
          );
          final LibraryItem item;
          if (kind == ItemKind.text) {
            item = await controller.captureText(List.filled(25000, '原').join());
          } else {
            final file = File('${directory.path}/input.pdf')
              ..writeAsBytesSync([1]);
            item = await controller.importFile(file.path);
          }
          await controller.waitForIdle();
          expect(item.status, 'ready');
          final anchor =
              item.analysis!.structuredInsights.single.evidence.single;
          expect(anchor.unresolved, isTrue);
          expect(anchor.blockId, isEmpty);
          expect(anchor.quote, 'SYNTHETIC_SUMMARY');
        } finally {
          controller.dispose();
          directory.deleteSync(recursive: true);
        }
      },
    );
  }

  test(
    'external research includes only selected sources and confirmed context',
    () async {
      final directory = Directory.systemTemp.createTempSync('readlater-scope-');
      final ai = ScopedIntelligence();
      final controller = AppController(
        store: LocalStore(directory.path),
        intelligence: ai,
        secrets: KnowledgeSecrets(),
      );
      try {
        await controller.initialize();
        await controller.saveSettings(AppSettings(textModel: 'fixture'));
        controller.data.items.addAll([
          LibraryItem(
            id: 'a',
            title: '关注问题',
            kind: ItemKind.text,
            body: '已选正文',
            notes: '我的笔记',
          ),
          LibraryItem(
            id: 'b',
            title: '关注问题',
            kind: ItemKind.text,
            body: '未选正文',
          ),
        ]);
        final topic = await controller.addTopic('关注问题', '关注问题');
        topic.selectedSourceIds = ['a'];
        topic.contextEntries.addAll([
          ContextEntry(
            id: 'confirmed',
            kind: 'goal',
            text: '明确目标',
            confirmed: true,
          ),
          ContextEntry(
            id: 'unconfirmed',
            kind: 'judgement',
            text: '待确认判断',
            confirmed: false,
          ),
        ]);
        await controller.research(
          goal: topic.question,
          topicId: topic.id,
          confirmed: true,
        );
        await controller.waitForIdle();
        final sources = ai.researchContext['sources'] as List;
        expect(sources.map((source) => source['id']), ['a']);
        expect(sources.single['notes'], '我的笔记');
        final contexts = ai.researchContext['contexts'] as List;
        expect(contexts.map((entry) => entry['id']), ['confirmed']);
        expect(controller.data.runs.single.inputItemIds, contains('a'));
        expect(controller.data.runs.single.inputItemIds, isNot(contains('b')));
        topic.selectedSourceIds = [];
        topic.selectedContextIds = [];
        topic.overviewStale = true;
        await controller.research(
          goal: topic.question,
          topicId: topic.id,
          confirmed: true,
        );
        await controller.waitForIdle();
        expect(ai.researchContext['sources'], isEmpty);
        expect(ai.researchContext['contexts'], isEmpty);
      } finally {
        controller.dispose();
        directory.deleteSync(recursive: true);
      }
    },
  );

  test(
    'cached synthesis cannot be restored as fresh after annotation edits',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'readlater-synthesis-cache-',
      );
      final ai = ScopedIntelligence();
      final controller = AppController(
        store: LocalStore(directory.path),
        intelligence: ai,
        secrets: KnowledgeSecrets(),
      );
      try {
        await controller.initialize();
        await controller.saveSettings(AppSettings(textModel: 'fixture'));
        controller.data.items.add(
          LibraryItem(
            id: 'a',
            title: '问题',
            kind: ItemKind.pdf,
            pdfPageCount: 2,
          ),
        );
        final topic = await controller.addTopic('问题', '问题');
        topic.selectedSourceIds = ['a'];
        await controller.queueSynthesis(topic.id);
        await controller.waitForIdle();
        expect(ai.synthesisCalls, 1);
        final job = controller.runtime.jobs.single;
        job.status = 'paused';
        await controller.updatePageNote('a', 1, '新的个人判断');
        await controller.resumeTasks();
        await controller.waitForIdle();
        expect(ai.synthesisCalls, 1);
        expect(job.status, 'paused');
        expect(job.error, contains('输入已变化'));
        expect(topic.overviewStale, isTrue);
      } finally {
        controller.dispose();
        directory.deleteSync(recursive: true);
      }
    },
  );

  test(
    'page-note edits update one annotation and invalidate dependent knowledge',
    () async {
      final directory = Directory.systemTemp.createTempSync('readlater-notes-');
      final controller = AppController(
        store: LocalStore(directory.path),
        secrets: KnowledgeSecrets(),
      );
      try {
        await controller.initialize();
        controller.data.items.addAll([
          LibraryItem(
            id: 'pdf',
            title: 'PDF',
            kind: ItemKind.pdf,
            pdfPageCount: 2,
          ),
          LibraryItem(
            id: 'dependent',
            title: '关联',
            kind: ItemKind.text,
            analysis: Analysis(summary: '旧认识', inputItemIds: ['pdf']),
          ),
        ]);
        controller.data.runs.add(
          ResearchRun(
            id: 'r',
            goal: '旧研究',
            report: '旧结论',
            inputItemIds: ['pdf'],
          ),
        );
        await controller.updatePageNote('pdf', 2, '初稿');
        await controller.updatePageNote('pdf', 2, '修订');
        expect(controller.data.items.first.annotations, hasLength(1));
        expect(controller.data.items.first.annotations.single.note, '修订');
        expect(controller.data.items.last.analysis!.stale, isTrue);
        expect(controller.data.runs.single.stale, isTrue);
      } finally {
        controller.dispose();
        directory.deleteSync(recursive: true);
      }
    },
  );
}
