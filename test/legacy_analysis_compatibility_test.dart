import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/models.dart';

void main() {
  test(
    'legacy readable-analysis highlights migrate to structured insights',
    () {
      final analysis = Analysis.fromJson({
        'summary': '旧分析正文',
        'insights': ['旧观点'],
        'sourceIds': ['article-1'],
        'highlights': [
          {
            'title': '观点标题',
            'explanation': '这段解释说明为什么这个观点重要。',
            'evidence': [
              {
                'sourceId': 'article-1',
                'quote': '来源摘录原文',
                'page': 7,
                'verified': true,
              },
            ],
          },
        ],
        'createdAt': '2026-09-20T00:00:00.000Z',
      });

      expect(analysis.structuredInsights, hasLength(1));
      final migrated = analysis.structuredInsights.single;
      expect(migrated.id, 'legacy-highlight-0');
      expect(migrated.title, '观点标题');
      expect(migrated.finding, '这段解释说明为什么这个观点重要。');
      expect(migrated.evidence, hasLength(1));
      expect(migrated.evidence.single.sourceId, 'article-1');
      expect(migrated.evidence.single.quote, '来源摘录原文');
      expect(migrated.evidence.single.pdfPage, 7);
      expect(migrated.evidence.single.sourceVersion, isNull);
      expect(migrated.evidence.single.blockId, isEmpty);
      expect(migrated.evidence.single.unresolved, isTrue);
      expect(migrated.evidence.single.note, contains('需核对'));
    },
  );

  test('existing structured insights take priority over legacy highlights', () {
    final analysis = Analysis.fromJson({
      'summary': '已有结构化分析',
      'structuredInsights': [
        {
          'id': 'current-1',
          'title': '当前结构化观点',
          'finding': '当前发现',
          'evidence': [
            {
              'sourceId': 'article-1',
              'sourceVersion': 3,
              'blockId': 'b1',
              'quote': '已核验证据',
            },
          ],
        },
      ],
      'highlights': [
        {
          'title': '旧观点不应覆盖',
          'explanation': '旧说明',
          'evidence': [
            {'sourceId': 'article-1', 'quote': '旧摘录'},
          ],
        },
      ],
    });

    expect(analysis.structuredInsights, hasLength(1));
    expect(analysis.structuredInsights.single.id, 'current-1');
    expect(analysis.structuredInsights.single.title, '当前结构化观点');
    expect(analysis.structuredInsights.single.evidence.single.blockId, 'b1');
    expect(
      analysis.structuredInsights.single.evidence.single.unresolved,
      isFalse,
    );
  });
}
