import 'package:readlater/core/models.dart';

/// Synthetic, offline content shared by visual and device acceptance tests.
AppData readingFixture({ReadingPreset preset = ReadingPreset.editorial}) {
  const source =
      '收藏并不等于理解。只有把一条资料放回具体问题，写下适用条件，'
      '并在之后的行动中重新检验，信息才有机会成为可以使用的认识。';
  const explanation =
      '收藏降低了再次找到资料的成本，却没有替代判断过程。'
      '当问题尚未明确时，继续增加输入可能让重要线索被更多材料淹没。'
      '一次有效的阅读，应当留下可以复查的判断：作者声称什么，证据覆盖哪些情境，'
      '这条结论会改变自己的哪项决定。把这些问题写下来，才能在下一次遇到相关资料时比较差异。';
  const titles = [
    '先带着问题阅读，再决定收藏',
    '把适用条件写进自己的判断',
    '用原始证据核对摘要中的结论',
    '区分知识变化与重复的信息',
    '让复查对应一个具体的行动',
    '给相互冲突的证据留下位置',
    '不要把阅读次数当成立场认同',
    '用少量问题引导后续研究',
    '保留结论产生时的资料版本',
    '将不确定性留在结论附近',
    '在新证据出现时重新判断',
    '用真实任务检验整理的价值',
  ];
  final insights = [
    for (var i = 0; i < titles.length; i++)
      Insight(
        id: 'insight-$i',
        title: titles[i],
        finding: '$explanation\n\n$explanation',
        change:
            '相比把资料按主题归档，这个观点增加了“可检验的问题”这一层。'
            '分类可以保留，但不能作为已经理解内容的依据。',
        impact:
            '下一次读完文章时，先记录一个可能改变的决定，再选择是否继续研究。'
            '如果暂时找不到相关任务，可以保留原文并延后判断。',
        unknowns: ['这组方法尚未在长期使用中验证，不能据此推断一定会提升效率。'],
        evidence: [
          EvidenceAnchor(
            sourceId: 'reading-source',
            sourceVersion: 1,
            blockId: 'body-1',
            quote: source,
          ),
        ],
      ),
  ];
  final presentation = ReadingPresentation(
    brief:
        '资料的价值取决于它是否帮助回答具体问题。先保留可追溯的证据，'
        '再比较新旧认识，并把不确定性留在判断旁边。这是一套值得尝试的方法，'
        '尚不能据此承诺长期效率提升。',
    sections: [
      for (var i = 0; i < 5; i++)
        ReadingSection(
          title: titles[i],
          body: '$explanation\n\n$explanation [reading-source]',
        ),
    ],
  );
  final now = DateTime.now();
  final day =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  return AppData(
    settings: AppSettings(readingPreset: preset),
    items: [
      LibraryItem(
        id: 'reading-source',
        title: '从收藏到理解：建立自己的阅读反馈',
        kind: ItemKind.text,
        body: '$source\n\n$explanation',
        status: 'ready',
        contentBlocks: [
          ContentBlock(
            id: 'body-1',
            kind: ContentBlockKind.paragraph,
            text: source,
          ),
          ContentBlock(
            id: 'body-2',
            kind: ContentBlockKind.paragraph,
            text: explanation,
          ),
        ],
        analysis: Analysis(
          brief: presentation.brief,
          summary: '$explanation\n\n$explanation',
          structuredInsights: insights,
          insights: ['兼容保留的旧版观点内容'],
          sourceIds: ['reading-source'],
          inputItemIds: ['reading-source'],
          connections: ['与已有笔记一致：先形成问题，再比较不同资料的解释。'],
          questions: ['怎样判断一条观点值得在一个月后复查？'],
        ),
      ),
      LibraryItem(
        id: 'reading-second',
        title: '让笔记成为下一次思考的起点',
        kind: ItemKind.web,
        url: 'https://example.com/notes',
        body: source,
      ),
    ],
    topics: [
      Topic(
        id: 'reading-topic',
        title: '阅读如何转化为可用的认识',
        question: '什么样的阅读过程能支持真实决策？',
        overview: explanation,
        presentation: presentation,
        status: 'ready',
        sourceIds: ['reading-source'],
        inputItemIds: ['reading-source'],
      ),
    ],
    todaySnapshots: [
      TodaySnapshot(
        day: day,
        entries: [
          TodayEntry(
            id: 'item:reading-source',
            entityType: 'item',
            entityId: 'reading-source',
            reason: '有新的分析结果，适合继续阅读并核对证据。',
            relatedIds: ['reading-source'],
          ),
          TodayEntry(
            id: 'topic:reading-topic',
            entityType: 'topic',
            entityId: 'reading-topic',
            reason: '回顾已有认识，找出下一步需要验证的问题。',
          ),
        ],
      ),
    ],
  );
}
