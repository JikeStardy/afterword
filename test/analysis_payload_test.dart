import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/services/intelligence_service.dart';

void main() {
  late Map<String, dynamic> input;
  late IntelligenceService service;

  setUp(() {
    service = IntelligenceService(
      client: MockClient((request) async {
        final prompt =
            jsonDecode(request.body)['messages'][1]['content'] as String;
        input = jsonDecode(
          prompt
              .substring(prompt.lastIndexOf('\n') + 1)
              .replaceFirst('输入数据：', ''),
        ) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'summary': '保留来源的分析',
                    'overview': '主题认识 [a]',
                    'sourceIds': ['a'],
                  }),
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
  });

  LibraryItem article(String id, {int paragraphs = 20}) => LibraryItem(
    id: id,
    title: '资料',
    kind: ItemKind.text,
    body: List.generate(
      paragraphs,
      (i) => '第$i段${List.filled(1000, '文').join()}',
    ).join('\n\n'),
  );

  int blockChars(Map<String, dynamic> payload) =>
      (payload['contentBlocks'] as List).fold<int>(
        0,
        (sum, block) => sum + (block['text'] as String).length,
      );

  test(
    'primary article is sent once without dropping later evidence blocks',
    () async {
      final item = article('a');
      await service.analyze(
        AppSettings(textModel: 'fixture'),
        'fixture-key',
        item,
        [],
      );
      final payload = input['item'] as Map<String, dynamic>;
      expect(payload.containsKey('content'), isFalse);
      expect(blockChars(payload), greaterThan(19000));
      expect(payload['contentBlocks'].last['id'], 'body-20');
      expect(payload['contentBlocks'].last['text'], contains('第19段'));
      expect(item.body, contains('第19段'));
    },
  );

  test(
    'related material has a per-source total budget and bounded summaries',
    () async {
      final original = article('a', paragraphs: 1);
      final related = article('b', paragraphs: 100);
      final analyzed = article('c', paragraphs: 100)
        ..analysis = Analysis(summary: List.filled(30000, '摘').join());
      await service.analyze(
        AppSettings(textModel: 'fixture'),
        'fixture-key',
        original,
        [related, analyzed],
      );
      for (final payload
          in (input['related'] as List).cast<Map<String, dynamic>>()) {
        final textChars =
            blockChars(payload) +
            ((payload['content'] as String?)?.length ?? 0);
        expect(textChars, lessThanOrEqualTo(4000));
        expect(payload['contentTruncated'], isTrue);
        expect(payload['contentBlocks'].first['id'], 'body-1');
      }
      expect(input['related'][0].containsKey('content'), isFalse);
      expect(
        (input['related'][1]['content'] as String).length,
        lessThanOrEqualTo(2000),
      );
      expect(related.body.length, greaterThan(100000));
      expect(analyzed.analysis!.summary.length, 30000);
    },
  );

  test(
    'merge sends intermediate text once and retains collected evidence',
    () async {
      final item = LibraryItem(
        id: 'a',
        title: '合并',
        kind: ItemKind.text,
        body: '分段摘要',
      );
      final evidence = EvidenceAnchor(
        sourceId: 'a',
        blockId: 'body-1',
        quote: '原文证据',
        unresolved: true,
      );
      await service.analyze(
        AppSettings(textModel: 'fixture'),
        'fixture-key',
        item,
        [],
        availableEvidence: [evidence],
      );
      expect(input['item']['content'], '分段摘要');
      expect(input['item']['contentBlocks'], isEmpty);
      expect(input['availableEvidence'], [evidence.toJson()]);
    },
  );

  test('topic source clipping applies across all paragraphs', () async {
    final item = article('a', paragraphs: 100);
    await service.synthesize(
      AppSettings(textModel: 'fixture'),
      'fixture-key',
      Topic(id: 't', title: '主题', question: '问题'),
      [item],
    );
    final payload = (input['sources'] as List).single as Map<String, dynamic>;
    expect(blockChars(payload), lessThanOrEqualTo(6000));
    expect(payload['contentTruncated'], isTrue);
  });
}
