import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/services/intelligence_service.dart';
import 'package:readlater/services/source_understanding_service.dart';

class RecordingIntelligence extends IntelligenceService {
  final List<String> prompts = [];
  final List<List<String>> images = [];
  final List<Json> replies;

  RecordingIntelligence(this.replies);

  @override
  Future<Json> complete(
    AppSettings settings,
    String key,
    String prompt, {
    List<String> imageDataUrls = const [],
    Future<void>? abortTrigger,
  }) async {
    prompts.add(prompt);
    images.add(imageDataUrls);
    return replies.removeAt(0);
  }
}

class BudgetCheckingIntelligence extends IntelligenceService {
  final prompts = <String>[];

  @override
  Future<Json> complete(
    AppSettings settings,
    String key,
    String prompt, {
    List<String> imageDataUrls = const [],
    Future<void>? abortTrigger,
  }) async {
    prompts.add(prompt);
    expect(
      IntelligenceService.textualRequestChars(
        prompt,
        model: imageDataUrls.isEmpty
            ? settings.textModel
            : settings.visionModel,
      ),
      lessThanOrEqualTo(settings.modelTextContextChars),
    );
    return {'summary': '合并后摘要 ${prompts.length}'};
  }
}

void main() {
  test(
    'summarizes text windows as neutral source segments with real anchors',
    () async {
      final intelligence = RecordingIntelligence([
        {'summary': '这段资料说明长上下文应先被分段压缩，再用于后续问答。'},
      ]);
      final service = SourceUnderstandingService(intelligence);
      final item = LibraryItem(
        id: 'item-1',
        title: '长文处理',
        kind: ItemKind.text,
        body: 'full body should not be sent',
        contentVersion: 7,
      );
      final windows = [
        SourceWindow(
          id: 'w1',
          sourceId: 'item-1',
          sourceVersion: 7,
          blockId: 'b1',
          start: 10,
          end: 28,
          text: '先分段总结，避免每次塞全文。',
          fingerprint: 'fingerprint-a',
        ),
        SourceWindow(
          id: 'w2',
          sourceId: 'item-1',
          sourceVersion: 7,
          blockId: 'b2',
          start: 29,
          end: 42,
          text: '问答时按需取回证据窗口。',
          fingerprint: 'fingerprint-b',
        ),
      ];

      final summary = await service.summarizeText(
        AppSettings(textModel: 'fixture', modelTextContextChars: 8000),
        'key',
        item,
        windows,
      );

      expect(summary.sourceId, 'item-1');
      expect(summary.sourceVersion, 7);
      expect(summary.rangeStart, 10);
      expect(summary.rangeEnd, 42);
      expect(summary.pdf, isFalse);
      expect(summary.promptVersion, SourceUnderstandingService.promptVersion);
      expect(summary.summary, contains('分段压缩'));
      expect(summary.evidence.map((e) => e.windowId), ['w1', 'w2']);
      expect(summary.evidence.first.blockId, 'b1');
      expect(summary.evidence.first.quote, '先分段总结，避免每次塞全文。');
      expect(summary.fingerprint, hasLength(64));
      expect(summary.fingerprint, service.textFingerprint(item, windows));
      expect(
        summary.id,
        service.summaryId('item-1', 7, 10, 42, summary.fingerprint),
      );
      expect(intelligence.prompts.single, isNot(contains(item.body)));
      expect(
        jsonDecode(intelligence.prompts.single),
        isA<Map<String, dynamic>>(),
      );
    },
  );

  test('merges many summaries in bounded hierarchical calls', () async {
    final intelligence = RecordingIntelligence([
      {'summary': '第一组合并摘要'},
      {'summary': '第二组合并摘要'},
      {'summary': '最终摘要'},
    ]);
    final service = SourceUnderstandingService(intelligence, mergeBatchSize: 2);
    final summaries = List.generate(
      4,
      (index) => SourceSegmentSummary(
        id: 's$index',
        sourceId: 'item-1',
        sourceVersion: 1,
        rangeStart: index * 10,
        rangeEnd: index * 10 + 9,
        fingerprint: 'fp$index',
        summary: '片段$index',
      ),
    );

    final merged = await service.mergeSummaries(
      AppSettings(textModel: 'fixture', modelTextContextChars: 8000),
      'key',
      summaries,
    );

    expect(merged, '最终摘要');
    expect(intelligence.prompts, hasLength(3));
    expect(intelligence.prompts.first, contains('片段0'));
    expect(intelligence.prompts.first, contains('片段1'));
    expect(intelligence.prompts.first, isNot(contains('片段2')));
    expect(intelligence.prompts.last, contains('第一组合并摘要'));
    expect(intelligence.prompts.last, contains('第二组合并摘要'));
  });

  test('splits oversized windows without breaking UTF-16 surrogate pairs', () {
    final service = SourceUnderstandingService(RecordingIntelligence([]));
    final segments = service.segmentWindows([
      SourceWindow(
        id: 'w',
        sourceId: 'item-1',
        sourceVersion: 1,
        blockId: 'b',
        start: 100,
        end: 110,
        text: 'abcd😀efgh',
        fingerprint: 'parent',
      ),
    ], maxChars: 5);

    expect(segments.map((segment) => segment.single.text), [
      'abcd',
      '😀efg',
      'h',
    ]);
    expect(segments[1].single.start, 104);
    expect(segments[1].single.end, 109);
    expect(segments[1].single.text.runes.first, 0x1F600);
  });

  test('merges large summaries with adaptive batches inside budget', () async {
    final intelligence = BudgetCheckingIntelligence();
    final service = SourceUnderstandingService(intelligence, mergeBatchSize: 8);
    final summaries = List.generate(
      7,
      (index) => SourceSegmentSummary(
        id: 's$index',
        sourceId: 'item-1',
        sourceVersion: 1,
        rangeStart: index * 10,
        rangeEnd: index * 10 + 9,
        fingerprint: 'fp$index',
        summary: '片段$index ${'内容' * 700}',
      ),
    );

    final merged = await service.mergeSummaries(
      AppSettings(textModel: 'fixture', modelTextContextChars: 8000),
      'key',
      summaries,
    );

    expect(merged, startsWith('合并后摘要'));
    expect(intelligence.prompts.length, greaterThan(1));
  });

  test('rejects model summaries over the derived output limit', () async {
    final intelligence = RecordingIntelligence([
      {'summary': '过长' * 1001},
    ]);
    final service = SourceUnderstandingService(intelligence);
    final item = LibraryItem(id: 'item-1', title: '长文处理', kind: ItemKind.text);
    final windows = [
      SourceWindow(
        id: 'w1',
        sourceId: 'item-1',
        sourceVersion: 1,
        blockId: 'b1',
        start: 0,
        end: 2,
        text: '正文',
        fingerprint: 'fingerprint',
      ),
    ];

    await expectLater(
      service.summarizeText(
        AppSettings(textModel: 'fixture', modelTextContextChars: 8000),
        'key',
        item,
        windows,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'summarizes normalized pdf images without exposing original paths',
    () async {
      final intelligence = RecordingIntelligence([
        {'summary': '这一页图像显示了模型预算和页面证据。'},
      ]);
      final service = SourceUnderstandingService(intelligence);
      final item = LibraryItem(
        id: 'pdf-1',
        title: 'PDF材料',
        kind: ItemKind.pdf,
        contentVersion: 3,
      );

      final summary = await service.summarizePdf(
        AppSettings(visionModel: 'vision', modelTextContextChars: 8000),
        'key',
        item,
        5,
        ['jpeg-page-base64'],
        'asset-sha',
      );

      expect(summary.pdf, isTrue);
      expect(summary.rangeStart, 5);
      expect(summary.rangeEnd, 5);
      expect(summary.evidence.single.pdfPage, 5);
      expect(summary.evidence.single.assetFingerprint, 'asset-sha');
      expect(summary.evidence.single.unresolved, isTrue);
      expect(
        summary.fingerprint,
        service.pdfFingerprint(item, 5, ['jpeg-page-base64'], 'asset-sha'),
      );
      expect(intelligence.images.single, [
        'data:image/jpeg;base64,jpeg-page-base64',
      ]);
      expect(intelligence.prompts.single, isNot(contains('/')));
    },
  );
}
