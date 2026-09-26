import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/app_controller.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/store.dart';
import 'package:readlater/main.dart';

AppController _controller(AppData data) {
  final dir = Directory.systemTemp.createTempSync('readlater_ui_test_');
  final controller = _UiController(store: LocalStore('${dir.path}/library'));
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

void main() {
  testWidgets('cold start immediately resumes pending shares', (tester) async {
    final dir = Directory.systemTemp.createTempSync('readlater_ui_share_test_');
    final controller = _ShareResumeController(
      store: LocalStore('${dir.path}/library'),
    );
    addTearDown(() {
      controller.dispose();
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });

    await tester.pumpWidget(ReadlaterApp(controller: controller));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('资料').last);
    await tester.pumpAndSettle();

    expect(controller.resumeCalls, 1);
    expect(controller.data.items.single.body, '一段从系统分享来的文字');
    expect(find.text('一段从系统分享来的文字'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'shows library, detail analysis and research suggestion boundary',
    (tester) async {
      final data = AppData(
        items: [
          LibraryItem(
            id: 'i1',
            title: '个人知识管理博客',
            kind: ItemKind.web,
            url: 'https://example.com/pkm',
            body: '把收藏变成认识，需要观点、依据和适用条件。',
            notes: '关注适用条件',
            analysis: Analysis(
              summary: '这篇文章主张用观点卡片沉淀认识。',
              insights: ['观点卡片需要保留来源和适用条件'],
              connections: ['与已有摘录方法互补'],
              questions: ['查证卡片笔记在研究型阅读中的限制'],
              sourceIds: ['i1'],
            ),
          ),
        ],
      );
      final controller = _controller(data);

      await tester.pumpWidget(ReadlaterApp(controller: controller));
      expect(find.text('资料'), findsWidgets);
      expect(find.text('RSS'), findsOneWidget);
      expect(find.text('研究'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);

      await tester.tap(find.text('资料').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('个人知识管理博客'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('原文'), findsOneWidget);
      expect(find.text('分析'), findsWidgets);
      expect(
        find.widgetWithText(SelectableText, '这篇文章主张用观点卡片沉淀认识。'),
        findsOneWidget,
      );
      expect(find.text('研究建议'), findsOneWidget);
      expect(find.text('确认研究'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('rss entries stay browsable until user selects them', (
    tester,
  ) async {
    final data = AppData(
      feeds: [Feed(id: 'f1', url: 'https://example.com/feed.xml', title: '博客')],
      entries: [
        FeedEntry(
          id: 'e1',
          feedId: 'f1',
          title: '一篇待读 RSS',
          url: 'https://example.com/post',
          summary: '先停留在收件箱，不自动分析。',
        ),
      ],
    );
    final controller = _controller(data);

    await tester.pumpWidget(ReadlaterApp(controller: controller));
    await tester.tap(find.text('RSS'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('一篇待读 RSS'), findsOneWidget);
    expect(find.text('未分析'), findsOneWidget);
    expect(find.text('选中处理'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'topic detail links external runs and exposes tracking controls',
    (tester) async {
      final data = AppData(
        topics: [
          Topic(
            id: 't1',
            title: '个人知识管理',
            question: '怎样把收藏变成认识？',
            overview: '当前综述引用了外部研究来源 [r1]。',
            sourceIds: ['r1'],
          ),
        ],
        runs: [
          ResearchRun(
            id: 'r1',
            goal: '比较卡片笔记和渐进总结',
            topicId: 't1',
            status: 'complete',
            report: '研究报告 [S1]',
            sources: [
              ResearchSource(
                id: 'S1',
                title: 'PKM Paper',
                url: 'https://example.com/pkm-paper',
                snippet: 'source',
              ),
            ],
            completedAt: DateTime(2026, 9, 21, 10),
          ),
        ],
      );
      final controller = _controller(data);

      await tester.pumpWidget(ReadlaterApp(controller: controller));
      await tester.tap(find.text('研究').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('个人知识管理'));
      await tester.pumpAndSettle();

      expect(find.textContaining('外部研究来源 [2]'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('关联外部研究'),
        350,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('关联外部研究'), findsOneWidget);
      expect(find.textContaining('1 个来源'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('授权追踪'),
        350,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('授权追踪'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('settings separate model and search keys', (tester) async {
    final controller = _controller(AppData());

    await tester.pumpWidget(ReadlaterApp(controller: controller));
    await tester.tap(find.byIcon(Icons.tune_outlined));
    await tester.pumpAndSettle();
    final scrollable = find
        .descendant(
          of: find.byType(ListView).last,
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('搜索 API Key（独立于模型 Key）'),
      400,
      scrollable: scrollable,
      maxScrolls: 30,
    );
    expect(find.text('搜索 API Key（独立于模型 Key）'), findsOneWidget);
    expect(find.text('搜索服务使用独立 Key，不与模型 Key 共用'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('公网鉴权服务需使用 HTTPS；本机或私有网络调试可使用 HTTP'),
      -300,
      scrollable: scrollable,
      maxScrolls: 30,
    );
    expect(find.text('公网鉴权服务需使用 HTTPS；本机或私有网络调试可使用 HTTP'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _UiController extends AppController {
  _UiController({required super.store});

  @override
  Future<void> resume() async {}
}

class _ShareResumeController extends AppController {
  _ShareResumeController({required super.store});

  int resumeCalls = 0;

  @override
  Future<void> resume() async {
    resumeCalls++;
    if (data.items.isEmpty) {
      data.items.add(
        LibraryItem(
          id: 'shared',
          title: '一段从系统分享来的文字',
          kind: ItemKind.text,
          body: '一段从系统分享来的文字',
        ),
      );
      notifyListeners();
    }
  }
}
