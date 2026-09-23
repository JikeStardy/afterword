import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/retrieval.dart';

void main() {
  test('Chinese search includes personal knowledge with useful snippet', () {
    final data = AppData(
      items: [
        LibraryItem(
          id: 'a',
          title: '方法',
          kind: ItemKind.text,
          notes: '我关心知识如何再次使用',
          contentBlocks: [
            ContentBlock(
              id: 'b1',
              kind: ContentBlockKind.paragraph,
              text: '结构化正文保留证据链',
            ),
          ],
          annotations: [
            Annotation(
              id: 'n1',
              highlightedText: '稍后复查的高亮',
              note: '这会影响决策证据',
              anchor: EvidenceAnchor(sourceId: 'a', quote: '稍后复查'),
            ),
          ],
          analysis: Analysis(
            summary: '建立决策证据',
            structuredInsights: [
              Insight(
                id: 's1',
                finding: '复用证据链',
                change: '比原来的零散笔记更可追溯',
                impact: '影响下一次决策',
                evidence: [EvidenceAnchor(quote: '可定位证据')],
                unknowns: ['证据更新频率'],
              ),
            ],
          ),
        ),
        LibraryItem(id: 'b', title: '决策证据', kind: ItemKind.text),
      ],
      topics: [
        Topic(
          id: 't',
          title: '主题',
          question: '如何积累知识？',
          contextEntries: [
            ContextEntry(
              id: 'c',
              kind: 'judgement',
              text: '个人判断需要确认后再参与结论',
              confirmed: true,
            ),
          ],
        ),
      ],
      runs: [ResearchRun(id: 'r', goal: '研究', report: '决策证据的研究成果')],
    );
    final hits = searchLibrary(data, '决策证据');
    expect(hits.map((hit) => hit.id), containsAll(['a', 'b', 'r']));
    expect(hits.first.id, 'b');
    expect(hits.first.snippet, contains('决策证据'));
    expect(searchLibrary(data, '知识').map((hit) => hit.id), contains('a'));
    expect(searchLibrary(data, '复用证据链').map((hit) => hit.id), contains('a'));
    expect(searchLibrary(data, '结构化正文').map((hit) => hit.id), contains('a'));
    expect(searchLibrary(data, '可定位证据').map((hit) => hit.id), contains('a'));
    expect(searchLibrary(data, '个人判断').map((hit) => hit.id), contains('t'));
    expect(searchLibrary(data, '稍后复查').map((hit) => hit.id), contains('a'));
  });

  test('URL dedup strips marketing but keeps identity queries', () {
    expect(
      normalizedCaptureUrl('https://EXAMPLE.com/a?id=7&utm_source=x#top'),
      normalizedCaptureUrl('https://example.com/a?id=7'),
    );
    expect(
      normalizedCaptureUrl('https://example.com/a?id=8'),
      isNot(normalizedCaptureUrl('https://example.com/a?id=7')),
    );
  });
}
