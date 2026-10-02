import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/app_controller.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/store.dart';
import 'package:readlater/main.dart';
import 'package:readlater/ui/afterword_art.dart';
import 'package:readlater/ui/common.dart';
import 'package:readlater/ui/research_detail.dart';

void main() {
  testWidgets('navigation keeps app tabs reachable with Afterword icons', (
    tester,
  ) async {
    final controller = _controller(AppData());

    await tester.pumpWidget(ReadlaterApp(controller: controller));
    await tester.pump();

    expect(find.text('今日'), findsWidgets);
    await tester.tap(find.text('资料').last);
    await tester.pumpAndSettle();
    expect(find.text('还没有待处理资料'), findsOneWidget);
    await tester.tap(find.text('研究').last);
    await tester.pumpAndSettle();
    expect(find.text('还没有研究主题'), findsOneWidget);
  });

  testWidgets('empty states require an explicit fox scene', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: readlaterTheme(),
        home: const Scaffold(
          body: EmptyState(
            scene: 'library-empty',
            icon: Icons.collections_bookmark_outlined,
            title: '还没有待处理资料',
            message: '收藏网页、文字、图片或 PDF，让阅读慢慢积累成认识。',
          ),
        ),
      ),
    );

    expect(find.text('还没有待处理资料'), findsOneWidget);
    expect(find.textContaining('收藏网页'), findsOneWidget);
  });

  testWidgets('research complete is done while failed budget paused are not', (
    tester,
  ) async {
    final complete = ResearchRun(
      id: 'complete-run',
      goal: '完成的研究',
      status: 'complete',
      report: '完成报告',
      completedAt: DateTime(2026, 9, 28, 8),
    );
    final failed = ResearchRun(
      id: 'failed-run',
      goal: '失败的研究',
      status: 'failed',
      error: '搜索服务异常',
      completedAt: DateTime(2026, 9, 28, 9),
    );
    final budget = ResearchRun(
      id: 'budget-run',
      goal: '预算用尽的研究',
      status: 'budget',
      report: '已有阶段性报告',
      completedAt: DateTime(2026, 9, 28, 10),
    );
    final paused = ResearchRun(
      id: 'paused-run',
      goal: '暂停的研究',
      status: 'paused',
      completedAt: DateTime(2026, 9, 28, 11),
    );
    final controller = _controller(
      AppData(runs: [complete, failed, budget, paused]),
    );

    await tester.pumpWidget(
      _wrap(ResearchRunPage(controller: controller, runId: complete.id)),
    );
    await tester.pumpAndSettle();
    expect(find.text('已完成'), findsOneWidget);
    expect(find.textContaining('完成：'), findsOneWidget);
    _expectRunScene('complete', FoxMotion.complete);

    await tester.pumpWidget(
      _wrap(ResearchRunPage(controller: controller, runId: failed.id)),
    );
    await tester.pumpAndSettle();
    expect(find.text('有异常'), findsOneWidget);
    expect(find.textContaining('结束：'), findsOneWidget);
    expect(find.textContaining('完成：'), findsNothing);
    _expectRunScene('startup-error', FoxMotion.retry);

    await tester.pumpWidget(
      _wrap(ResearchRunPage(controller: controller, runId: budget.id)),
    );
    await tester.pumpAndSettle();
    expect(find.text('预算用尽'), findsOneWidget);
    expect(find.textContaining('完成：'), findsNothing);
    _expectRunScene('unanalyzed', FoxMotion.paused);

    await tester.pumpWidget(
      _wrap(ResearchRunPage(controller: controller, runId: paused.id)),
    );
    await tester.pumpAndSettle();
    expect(find.text('已暂停'), findsOneWidget);
    expect(find.textContaining('完成：'), findsNothing);
    _expectRunScene('paused', FoxMotion.paused);
  });

  testWidgets('successful UI actions show the saved fox feedback', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: readlaterTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () =>
                    runUiAction(context, () async {}, success: '正文已保存'),
                child: const Text('保存'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.text('正文已保存'), findsOneWidget);
  });
}

Widget _wrap(Widget child) {
  return MaterialApp(theme: readlaterTheme(), home: child);
}

void _expectRunScene(String scene, FoxMotion motion) {
  final sceneFinder = find.byWidgetPredicate(
    (widget) =>
        widget is AfterwordScene &&
        widget.scene == scene &&
        widget.motion == motion,
  );
  expect(sceneFinder, findsOneWidget);
}

AppController _controller(AppData data) {
  final dir = Directory.systemTemp.createTempSync('readlater_afterword_test_');
  final controller = _AfterwordController(store: LocalStore('${dir.path}/db'));
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

class _AfterwordController extends AppController {
  _AfterwordController({required super.store});

  @override
  Future<void> resume() async {}
}
