import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/app_controller.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/store.dart';
import 'package:readlater/main.dart';
import 'package:readlater/ui/item_detail.dart';
import 'package:readlater/ui/research_detail.dart';
import 'package:readlater/ui/research_dialogs.dart';

AppController _controller(AppData data) {
  final dir = Directory.systemTemp.createTempSync('readlater_detail_test_');
  final controller = _DetailController(
    store: LocalStore('${dir.path}/library'),
  );
  controller.data = data;
  controller.store.save(data);
  addTearDown(() {
    controller.dispose();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  return controller;
}

Widget _wrap(Widget child) {
  return MaterialApp(debugShowCheckedModeBanner: false, home: child);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('readlater/native');
  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('article detail refreshes when the controller item changes', (
    tester,
  ) async {
    final controller = _controller(
      AppData(
        items: [
          LibraryItem(
            id: 'i1',
            title: '原文',
            kind: ItemKind.web,
            body: '正文',
            analysis: Analysis(summary: '旧总结'),
          ),
        ],
      ),
    ) as _DetailController;

    await tester.pumpWidget(
      _wrap(
        ArticleDetailPage(
          controller: controller,
          item: controller.data.items.single,
        ),
      ),
    );
    expect(find.text('旧总结'), findsOneWidget);

    controller.replaceItemSummary('i1', '新总结');
    await tester.pump();

    expect(find.text('新总结'), findsOneWidget);
    expect(find.text('旧总结'), findsNothing);
  });

  testWidgets('analysis source ids open the matching local article', (
    tester,
  ) async {
    final controller = _controller(
      AppData(
        items: [
          LibraryItem(
            id: 'i1',
            title: '分析文章',
            kind: ItemKind.web,
            body: '正文',
            analysis: Analysis(summary: '总结', sourceIds: ['source-1']),
          ),
          LibraryItem(
            id: 'source-1',
            title: '来源文章',
            kind: ItemKind.web,
            body: '来源正文',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      _wrap(
        ArticleDetailPage(
          controller: controller,
          item: controller.data.items.first,
        ),
      ),
    );
    await tester.tap(find.text('来源文章'));
    await tester.pumpAndSettle();

    expect(find.text('来源正文'), findsOneWidget);
  });

  testWidgets(
    'article analysis renders citations without internal source ids',
    (tester) async {
      final controller = _controller(
        AppData(
          items: [
            LibraryItem(
              id: 'i1',
              title: '分析文章',
              kind: ItemKind.web,
              body: '正文',
              analysis: Analysis(
                summary: '核心观点来自 [source-1]，另有一个未确认引用 [ghost-id]。',
                insights: [
                  '适用条件见 [source-1]，但普通标签 [API] 和 [documentation] 保持原样。',
                ],
                sourceIds: ['source-1', 'ghost-id'],
              ),
            ),
            LibraryItem(
              id: 'source-1',
              title: '来源文章',
              kind: ItemKind.web,
              body: '来源正文',
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        _wrap(
          ArticleDetailPage(
            controller: controller,
            item: controller.data.items.first,
          ),
        ),
      );

      expect(find.textContaining('核心观点来自 [1]'), findsOneWidget);
      expect(find.textContaining('未确认引用 [未知来源]'), findsOneWidget);
      expect(
        find.text('适用条件见 [1]，但普通标签 [API] 和 [documentation] 保持原样。'),
        findsOneWidget,
      );
      expect(find.text('来源文章'), findsOneWidget);
      expect(find.textContaining('source-1'), findsNothing);
      expect(find.textContaining('ghost-id'), findsNothing);
    },
  );

  testWidgets('asset open failures are shown through the UI action wrapper', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          throw PlatformException(code: 'no_viewer', message: '没有可用查看器');
        });
    final controller = _controller(
      AppData(
        items: [
          LibraryItem(
            id: 'i1',
            title: 'PDF资料',
            kind: ItemKind.pdf,
            body: '正文',
            assets: [
              Asset(
                path: 'assets/doc.pdf',
                name: 'doc.pdf',
                mime: 'application/pdf',
              ),
            ],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      _wrap(
        ArticleDetailPage(
          controller: controller,
          item: controller.data.items.single,
        ),
      ),
    );
    await tester.tap(find.text('附件 · 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('doc.pdf'));
    await tester.pump();

    expect(calls.single.method, 'openFile');
    expect(find.textContaining('没有可用查看器'), findsOneWidget);
  });

  testWidgets('topic detail shows synthesis status and errors', (tester) async {
    final controller = _controller(
      AppData(
        topics: [
          Topic(
            id: 't1',
            title: '个人知识管理',
            question: '怎样把收藏变成认识？',
            status: 'error',
            error: '模型返回为空',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      _wrap(TopicDetailPage(controller: controller, topicId: 't1')),
    );

    expect(find.text('error'), findsOneWidget);
    expect(find.text('模型返回为空'), findsOneWidget);
  });

  testWidgets('topic synthesis action is disabled while already synthesizing', (
    tester,
  ) async {
    final controller = _controller(
      AppData(
        topics: [
          Topic(
            id: 't1',
            title: '个人知识管理',
            question: '怎样把收藏变成认识？',
            status: 'synthesizing',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      _wrap(TopicDetailPage(controller: controller, topicId: 't1')),
    );

    final button = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.auto_awesome),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets(
    'research source URLs are actionable and call the native bridge',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      final controller = _controller(
        AppData(
          runs: [
            ResearchRun(
              id: 'r1',
              goal: '比较卡片笔记',
              status: 'complete',
              report: '研究报告',
              sources: [
                ResearchSource(
                  id: 'S1',
                  title: '外部来源',
                  url: 'https://example.com/source',
                  snippet: '摘要',
                ),
              ],
            ),
          ],
        ),
      );

      await tester.pumpWidget(ReadlaterApp(controller: controller));
      await tester.tap(find.text('研究'));
      await tester.pump();
      await tester.tap(find.text('比较卡片笔记'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('外部来源'));
      await tester.pump();

      expect(calls.single.method, 'openUrl');
      expect(calls.single.arguments, {'url': 'https://example.com/source'});
    },
  );

  testWidgets(
    'research and tracking call limit sliders match controller bounds',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () => showResearchDialog(context, const <Topic>[]),
                  child: const Text('研究弹窗'),
                ),
                TextButton(
                  onPressed: () => showTrackingDialog(
                    context,
                    Topic(id: 't1', title: '主题', question: '问题'),
                  ),
                  child: const Text('追踪弹窗'),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('研究弹窗'));
      await tester.pumpAndSettle();
      var slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.min, 2);
      expect(slider.max, 30);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('追踪弹窗'));
      await tester.pumpAndSettle();
      final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
      slider = sliders.last;
      expect(slider.min, 2);
      expect(slider.max, 30);
    },
  );
}

class _DetailController extends AppController {
  _DetailController({required super.store});

  void replaceItemSummary(String id, String summary) {
    final index = data.items.indexWhere((item) => item.id == id);
    data.items[index] = LibraryItem(
      id: data.items[index].id,
      title: data.items[index].title,
      kind: data.items[index].kind,
      body: data.items[index].body,
      analysis: Analysis(summary: summary),
    );
    notifyListeners();
  }

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<void> resume() async {}
}
