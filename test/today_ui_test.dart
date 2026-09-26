import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/app_controller.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/store.dart';
import 'package:readlater/main.dart';

void main() {
  testWidgets('today is the default tab with stable recommendations and jobs', (
    tester,
  ) async {
    final controller = _controller(
      AppData(
        items: [
          LibraryItem(
            id: 'i1',
            title: '未判断资料',
            kind: ItemKind.text,
            body: '个人知识管理需要复查。',
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
              ),
            ],
          ),
        ],
      ),
      runtime: RuntimeState(
        jobs: [
          BackgroundJob(
            id: 'j1',
            type: 'analysis',
            entityId: 'i1',
            status: 'running',
            stage: '分析正文',
            checkpoint: {'completed': 1, 'total': 3},
          ),
        ],
      ),
    );

    await tester.pumpWidget(ReadlaterApp(controller: controller));
    await tester.pump();

    expect(find.text('今日'), findsWidgets);
    expect(find.text('未判断资料'), findsWidgets);
    expect(find.text('尚待判断，决定精读、保留或跳过'), findsOneWidget);
    expect(find.text('分析正文'), findsOneWidget);

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('少推荐类似'));
    await tester.pump();
    expect(controller.data.items.single.feedback, -1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('today complete clears topic review reminders', (tester) async {
    final reviewAt = DateTime.now().subtract(const Duration(days: 1));
    final controller = _controller(
      AppData(
        topics: [
          Topic(
            id: 't1',
            title: '待复查主题',
            question: '还有什么要确认？',
            reviewAt: reviewAt,
          ),
        ],
        todaySnapshots: [
          TodaySnapshot(
            day: _today(),
            entries: [
              TodayEntry(
                id: 'topic:t1',
                entityType: 'topic',
                entityId: 't1',
                reason: '复查日期已到',
              ),
            ],
          ),
        ],
      ),
    );

    await tester.pumpWidget(ReadlaterApp(controller: controller));
    await tester.pump();
    await tester.tap(find.text('已处理'));
    await tester.pumpAndSettle();

    expect(controller.data.topics.single.reviewAt, isNull);
    expect(controller.todaySnapshot.entries, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

AppController _controller(AppData data, {RuntimeState? runtime}) {
  final dir = Directory.systemTemp.createTempSync('readlater_today_ui_test_');
  final controller = _TodayController(store: LocalStore('${dir.path}/library'));
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

class _TodayController extends AppController {
  _TodayController({required super.store});

  @override
  Future<void> resume() async {}
}
