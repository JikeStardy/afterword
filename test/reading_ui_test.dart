import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/app_controller.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/store.dart';
import 'package:readlater/ui/common.dart';
import 'package:readlater/ui/item_detail.dart';
import 'package:readlater/ui/research_detail.dart';

class _ReadingController extends AppController {
  _ReadingController({required super.store});

  @override
  Future<void> resume() async {}
}

_ReadingController _controller(AppData data) {
  final directory = Directory.systemTemp.createTempSync(
    'readlater_reading_ui_',
  );
  final controller = _ReadingController(
    store: LocalStore('${directory.path}/library'),
  );
  controller.data = data;
  controller.store.save(data);
  addTearDown(() {
    controller.dispose();
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });
  return controller;
}

Widget _wrap(Widget child, {double scale = 1}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: readlaterTheme(),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: child,
    ),
  );
}

class _PresetHost extends StatefulWidget {
  const _PresetHost({super.key, required this.controller, required this.item});

  final AppController controller;
  final LibraryItem item;

  @override
  State<_PresetHost> createState() => _PresetHostState();
}

class _PresetHostState extends State<_PresetHost> {
  ReadingPreset preset = ReadingPreset.editorial;

  void setPreset(ReadingPreset next) {
    setState(() => preset = next);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: readlaterTheme(preset),
      home: ArticleDetailPage(controller: widget.controller, item: widget.item),
    );
  }
}

void main() {
  testWidgets(
    'long structured analysis uses readable sections and disclosures',
    (tester) async {
      tester.view.physicalSize = const Size(360, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final item = LibraryItem(
        id: 'article',
        title: '很长很长的标题用于验证阅读排版',
        kind: ItemKind.web,
        body: '第一段原文\n\n第二段原文',
        analysis: Analysis(
          summary: List.filled(30, '旧版完整总结用于保留兼容内容。').join(),
          sourceIds: ['article'],
          inputItemIds: ['article'],
          questions: ['这个问题很长，用来确认研究建议在窄屏和大字号下仍然独立换行。'],
          structuredInsights: [
            for (var index = 0; index < 12; index++)
              Insight(
                id: 'insight-$index',
                finding: '第 $index 条观点有很长的发现正文，解释模型读完资料后到底改变了什么理解。',
                change: '它改变了原先把所有结论塞进一个段落的读法。',
                impact: '读者可以先扫标题，再展开证据，不需要在一整堵文字里找重点。',
                unknowns: ['仍需验证边界条件', '需要保留来源跳转'],
                evidence: [
                  EvidenceAnchor(
                    sourceId: 'article',
                    blockId: 'body-1',
                    quote: '第一段原文',
                  ),
                ],
              ),
          ],
        ),
      );
      final controller = _controller(AppData(items: [item]));

      await tester.pumpWidget(
        _wrap(
          ArticleDetailPage(controller: controller, item: item),
          scale: 1.8,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('观点 01'), findsOneWidget);
      expect(find.byKey(const ValueKey('insight-insight-0-0')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('evidence-insight-0-0')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ExpansionTile>(find.widgetWithText(ExpansionTile, '完整总结'))
            .initiallyExpanded,
        isFalse,
      );

      await Scrollable.ensureVisible(
        tester.element(find.text('证据 · 1').first),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('证据 · 1').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('第一段原文'), findsWidgets);
      expect(find.text('研究建议'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('research run report uses reading presentation when available', (
    tester,
  ) async {
    final run = ResearchRun(
      presentation: ReadingPresentation(
        brief: '这是一段短导语 [S1]',
        sections: [ReadingSection(title: '核心发现', body: '研究报告正文会按章节展开 [S1]')],
      ),
      id: 'run-1',
      goal: '调研长阅读设计',
      status: 'done',
      report: '完整研究报告 [S1]',
      sources: [
        ResearchSource(
          id: 'S1',
          title: '来源标题',
          url: 'https://example.com',
          snippet: 'snippet',
        ),
      ],
    );
    final controller = _controller(AppData(runs: [run]));

    await tester.pumpWidget(
      _wrap(ResearchRunPage(controller: controller, runId: 'run-1')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('这是一段短导语 [1]'), findsOneWidget);
    expect(find.text('核心发现'), findsOneWidget);
    expect(find.textContaining('研究报告正文会按章节展开 [1]'), findsOneWidget);
    expect(
      tester
          .widget<ExpansionTile>(find.widgetWithText(ExpansionTile, '完整报告'))
          .initiallyExpanded,
      isFalse,
    );
  });

  testWidgets('topic overview resolves attached run source citations', (
    tester,
  ) async {
    const channel = MethodChannel('readlater/native');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final run = ResearchRun(
      id: 'run-1',
      goal: '调研外部来源',
      topicId: 'topic-1',
      status: 'done',
      report: '研究报告 [S1]',
      sources: [
        ResearchSource(
          id: 'S1',
          title: '外部来源标题',
          url: 'https://example.com/source',
          snippet: 'snippet',
        ),
      ],
      presentation: ReadingPresentation(
        brief: '研究导语 [S1]',
        sections: [ReadingSection(title: '结论', body: '主题综述正文来自外部来源 [S1]')],
      ),
    );
    final topic = Topic(
      id: 'topic-1',
      title: '主题',
      question: '如何处理研究来源？',
      status: 'ready',
      sourceIds: [run.id],
      overview: '主题综述正文来自外部来源 [S1]\n\n研究记录：[run-1]',
      presentation: ReadingPresentation(
        brief: run.presentation!.brief,
        sections: [
          ...run.presentation!.sections,
          ReadingSection(title: '研究记录', body: '完整来源链：[run-1]'),
        ],
      ),
    );
    final controller = _controller(AppData(topics: [topic], runs: [run]));

    await tester.pumpWidget(
      _wrap(TopicDetailPage(controller: controller, topicId: topic.id)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('研究导语 [1]'), findsOneWidget);
    expect(find.textContaining('主题综述正文来自外部来源 [1]'), findsOneWidget);
    expect(find.text('完整来源链：[2]'), findsOneWidget);
    expect(find.text('本次研究来源'), findsOneWidget);
    expect(find.text('外部来源标题'), findsOneWidget);
    expect(find.text('研究记录：调研外部来源'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('调研外部来源'), findsNothing);
    expect(find.byType(SourceList), findsNothing);

    await Scrollable.ensureVisible(
      tester.element(find.text('外部来源标题')),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('外部来源标题'));
    await tester.pumpAndSettle();

    expect(calls.single.method, 'openUrl');
    expect(calls.single.arguments, {'url': 'https://example.com/source'});
  });

  testWidgets(
    'topic overview numbers record as source one when run has no external sources',
    (tester) async {
      final run = ResearchRun(
        id: 'run-empty',
        goal: '无外部来源研究',
        topicId: 'topic-empty',
        status: 'done',
        report: '只有研究记录 [run-empty]',
        presentation: ReadingPresentation(brief: '研究导语来自记录 [run-empty]'),
      );
      final topic = Topic(
        id: 'topic-empty',
        title: '主题',
        question: '没有外部来源怎么办？',
        status: 'ready',
        sourceIds: [run.id],
        overview: run.report,
        presentation: run.presentation,
      );
      final controller = _controller(AppData(topics: [topic], runs: [run]));

      await tester.pumpWidget(
        _wrap(TopicDetailPage(controller: controller, topicId: topic.id)),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('研究导语来自记录 [1]'), findsOneWidget);
      expect(find.text('本次研究来源'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('研究记录：无外部来源研究'), findsOneWidget);
      expect(find.text('无外部来源研究'), findsNothing);
      expect(find.byType(SourceList), findsNothing);
    },
  );

  testWidgets('analysis brief keeps the full summary accessible', (
    tester,
  ) async {
    const fullSummary = '完整总结第一段说明长期阅读结论。完整总结第二段保留限制条件。完整总结第三段保留来源语境。';
    final item = LibraryItem(
      id: 'article',
      title: '导语资料',
      kind: ItemKind.web,
      body: '正文',
      analysis: Analysis(brief: '短导语先说明重点。', summary: fullSummary),
    );
    final controller = _controller(AppData(items: [item]));

    await tester.pumpWidget(
      _wrap(ArticleDetailPage(controller: controller, item: item)),
    );
    await tester.pumpAndSettle();

    expect(find.text('短导语先说明重点。'), findsOneWidget);
    expect(find.text('完整总结'), findsOneWidget);
    expect(
      tester
          .widget<ExpansionTile>(find.widgetWithText(ExpansionTile, '完整总结'))
          .initiallyExpanded,
      isFalse,
    );

    await tester.tap(find.text('完整总结'));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) => widget is SelectableText && widget.data == fullSummary,
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'analysis keeps the visible insight anchored across preset changes',
    (tester) async {
      final longBody = List.filled(30, '这一条观点正文很长，用来填满超过一屏的阅读区域。').join();
      final item = LibraryItem(
        id: 'article',
        title: '分析锚点资料',
        kind: ItemKind.web,
        body: '正文',
        analysis: Analysis(
          sourceIds: ['article'],
          structuredInsights: [
            Insight(
              id: 'long',
              title: '超长观点',
              finding: longBody,
              change: longBody,
              impact: longBody,
            ),
            for (var index = 0; index < 14; index++)
              Insight(
                id: 'insight-$index',
                finding: '用于测试预设切换的第 $index 条观点正文。',
                change: '变化说明 $index',
                impact: '影响说明 $index',
                evidence: [
                  EvidenceAnchor(sourceId: 'article', blockId: 'body-1'),
                ],
              ),
          ],
        ),
      );
      final controller = _controller(AppData(items: [item]));
      final host = GlobalKey<_PresetHostState>();

      await tester.pumpWidget(
        _PresetHost(key: host, controller: controller, item: item),
      );
      await tester.pumpAndSettle();
      const anchor = ValueKey('insight-long-0');
      await tester.ensureVisible(find.byKey(anchor));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -360));
      await tester.pumpAndSettle();
      final before = tester.getTopLeft(find.byKey(anchor)).dy;
      expect(before, lessThan(0));
      expect(tester.getBottomLeft(find.byKey(anchor)).dy, greaterThan(120));

      host.currentState!.setPreset(ReadingPreset.magazine);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byKey(anchor), findsOneWidget);
      expect(tester.getTopLeft(find.byKey(anchor)).dy, lessThan(120));
      expect(tester.getBottomLeft(find.byKey(anchor)).dy, greaterThan(120));
    },
  );

  testWidgets('duplicate insight ids keep stable unique UI keys', (
    tester,
  ) async {
    final item = LibraryItem(
      id: 'article',
      title: '重复 ID 资料',
      kind: ItemKind.web,
      body: '正文',
      analysis: Analysis(
        structuredInsights: [
          Insight(id: 'same', finding: '第一条'),
          Insight(id: 'same', finding: '第二条'),
          Insight(id: '', finding: '第三条'),
        ],
      ),
    );
    final controller = _controller(AppData(items: [item]));

    await tester.pumpWidget(
      _wrap(ArticleDetailPage(controller: controller, item: item)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('insight-same-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('insight-same-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('insight-row-2')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('insight feedback target keeps a 48dp touch size', (
    tester,
  ) async {
    final item = LibraryItem(
      id: 'article',
      title: '反馈尺寸资料',
      kind: ItemKind.web,
      body: '正文',
      analysis: Analysis(
        structuredInsights: [Insight(id: 'one', finding: '观点正文')],
      ),
    );
    final controller = _controller(AppData(items: [item]));

    await tester.pumpWidget(
      _wrap(ArticleDetailPage(controller: controller, item: item)),
    );
    await tester.pumpAndSettle();

    final size = tester.getSize(
      find.byKey(const ValueKey('insight-feedback-one-0')),
    );
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });
}
