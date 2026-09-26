import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/app_controller.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/store.dart';
import 'package:readlater/main.dart';
import 'package:readlater/ui/common.dart';
import 'package:readlater/ui/library_page.dart';
import 'package:readlater/ui/research_page.dart';
import 'package:readlater/ui/rss_page.dart';
import 'package:readlater/ui/today_page.dart';

void main() {
  testWidgets('today rows keep secondary actions in the more menu', (
    tester,
  ) async {
    final controller = _controller(
      AppData(
        items: [
          LibraryItem(
            id: 'i1',
            title: '长文观点',
            kind: ItemKind.text,
            body: '这是一段很长的原文摘录，用来验证今日页面显示摘录而不是继续堆一张大卡。',
            analysis: Analysis(summary: '分析摘要会优先成为今日推荐的阅读线索。'),
          ),
        ],
        todaySnapshots: [
          TodaySnapshot(
            day: _today(),
            entries: [
              TodayEntry(
                id: 'item:i1',
                entityType: 'item',
                entityId: 'i1',
                reason: '尚待判断，决定精读、保留或跳过',
                relatedIds: ['i1'],
              ),
            ],
          ),
        ],
      ),
    );

    await tester.pumpWidget(ReadlaterApp(controller: controller));
    await tester.pump();

    expect(find.text('推荐原因'), findsOneWidget);
    expect(find.text('尚待判断，决定精读、保留或跳过'), findsOneWidget);
    expect(find.text('少推荐类似'), findsNothing);

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('少推荐类似'));
    await tester.pump();

    expect(controller.data.items.single.feedback, -1);
  });

  testWidgets('today title keeps readable width on narrow large text screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _controller(
      AppData(
        items: [
          LibraryItem(
            id: 'i1',
            title: '一篇需要完整宽度阅读的长标题',
            kind: ItemKind.text,
            body: '正文摘录。',
            analysis: Analysis(brief: '这是真正的短导读。'),
          ),
        ],
        todaySnapshots: [
          TodaySnapshot(
            day: _today(),
            entries: [
              TodayEntry(id: 'item:i1', entityType: 'item', entityId: 'i1'),
            ],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: readlaterTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.8)),
          child: child!,
        ),
        home: TodayPage(controller: controller, data: controller.data),
      ),
    );
    await tester.pump();

    final titleBox = tester.renderObject<RenderBox>(
      find.byKey(const Key('today-title-item:i1')),
    );
    expect(titleBox.size.width, greaterThan(200));
    expect(find.text('这是真正的短导读。'), findsOneWidget);
  });

  testWidgets(
    'library separates scope filters from state filters and result meta',
    (tester) async {
      final controller = _controller(
        AppData(
          items: [
            LibraryItem(
              id: 'i1',
              title: '已分析资料',
              kind: ItemKind.text,
              body: '资料正文',
              analysis: Analysis(summary: '分析摘要'),
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        _wrap(LibraryPage(controller: controller, data: controller.data)),
      );

      expect(find.text('范围'), findsOneWidget);
      expect(find.text('状态'), findsOneWidget);
      expect(find.text('当前 1 条资料 · 按加入时间排序'), findsOneWidget);
      expect(find.text('已分析资料'), findsOneWidget);
      expect(find.text('已分析'), findsOneWidget);
    },
  );

  testWidgets(
    'rss keeps feed management compact and prioritizes pending entries',
    (tester) async {
      final now = DateTime.now();
      final controller = _controller(
        AppData(
          feeds: [
            Feed(id: 'f1', url: 'https://example.com/rss', title: '主订阅'),
            Feed(
              id: 'f2',
              url: 'https://bad.example/rss',
              title: '异常订阅',
              error: 'HTTP 500',
            ),
          ],
          entries: [
            FeedEntry(
              id: 'done',
              feedId: 'f1',
              title: '已处理条目',
              url: 'https://example.com/done',
              processed: true,
              publishedAt: now,
            ),
            FeedEntry(
              id: 'pending',
              feedId: 'f1',
              title: '待处理条目',
              url: 'https://example.com/pending',
              publishedAt: now.subtract(const Duration(days: 1)),
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        _wrap(RssPage(controller: controller, data: controller.data)),
      );

      expect(find.text('订阅管理'), findsOneWidget);
      expect(find.text('1 个异常 · 2 个订阅'), findsOneWidget);
      expect(find.text('待处理条目'), findsOneWidget);
      expect(find.text('已处理条目'), findsNothing);

      await tester.tap(find.text('订阅管理'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('隐藏已处理条目'));
      await tester.pumpAndSettle();

      expect(find.text('待处理条目'), findsOneWidget);
      expect(find.text('已处理条目'), findsOneWidget);
      final pendingTop = tester.getTopLeft(find.text('待处理条目')).dy;
      final doneTop = tester.getTopLeft(find.text('已处理条目')).dy;
      expect(pendingTop, lessThan(doneTop));
    },
  );

  testWidgets('research page distinguishes reading topics from run activity', (
    tester,
  ) async {
    final controller = _controller(
      AppData(
        topics: [
          Topic(
            id: 't1',
            title: '长期主题',
            question: '要持续追踪什么？',
            overview: '这是主题综述的简短导读。',
            tracking: true,
            sourceIds: ['i1', 'i2'],
          ),
        ],
        runs: [
          ResearchRun(
            id: 'r1',
            goal: '验证一个外部问题',
            status: 'completed',
            report: '研究记录摘要。',
            calls: 2,
            callLimit: 4,
            sources: [
              ResearchSource(
                id: 's1',
                title: '来源',
                url: 'https://example.com',
                snippet: '片段',
              ),
            ],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      _wrap(ResearchPage(controller: controller, data: controller.data)),
    );

    expect(find.text('主题'), findsOneWidget);
    expect(find.text('研究活动'), findsOneWidget);
    expect(find.text('这是主题综述的简短导读。'), findsOneWidget);
    expect(find.text('跟踪中'), findsOneWidget);
    expect(find.text('2/4 次调用'), findsOneWidget);
    expect(find.text('1 个外部来源'), findsOneWidget);
  });
}

Widget _wrap(Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: readlaterTheme(),
    home: child,
  );
}

AppController _controller(AppData data, {RuntimeState? runtime}) {
  final dir = Directory.systemTemp.createTempSync('readlater_reading_lists_');
  final controller = _ReadingListsController(
    store: LocalStore('${dir.path}/library'),
  );
  controller.data = data;
  controller.runtime = runtime ?? RuntimeState();
  controller.store.saveWithRuntime(controller.data, controller.runtime);
  addTearDown(() {
    controller.dispose();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  return controller;
}

String _today() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}

class _ReadingListsController extends AppController {
  _ReadingListsController({required super.store});

  @override
  Future<void> resume() async {}
}
