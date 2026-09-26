import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/app_controller.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/diagnostics.dart';
import 'package:readlater/ui/app_shell.dart';
import 'package:readlater/core/store.dart';
import 'package:readlater/main.dart';
import 'package:readlater/ui/common.dart';
import 'package:readlater/ui/developer_page.dart';
import 'package:readlater/ui/item_detail.dart';

class _UiController extends AppController {
  _UiController({required super.store});
  @override
  Future<void> resume() async {}
}

_UiController _controllerWith(List<LibraryItem> items) {
  final directory = Directory.systemTemp.createTempSync('readlater_v2_ui_');
  final controller = _UiController(
    store: LocalStore('${directory.path}/library'),
  );
  controller.data = AppData(items: items);
  controller.store.save(controller.data);
  addTearDown(() {
    controller.dispose();
    directory.deleteSync(recursive: true);
  });
  return controller;
}

LibraryItem article(String id) => LibraryItem(
  id: id,
  title: '阅读资料 $id',
  kind: ItemKind.text,
  body: '这是保留在本地的完整原文。阅读、思考与记录，慢慢形成自己的认识。',
  analysis: Analysis(summary: '这是一段已经完成的分析。', inputItemIds: [id]),
);

void main() {
  testWidgets('batch archive, trash restore and confirmed permanent deletion', (
    tester,
  ) async {
    final c = _controllerWith([article('one'), article('two')]);
    await tester.pumpWidget(ReadlaterApp(controller: c));
    await tester.tap(find.text('资料').last);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('阅读资料 one'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('全选当前结果'));
    await tester.pump();
    expect(find.text('已选 2 项'), findsOneWidget);
    await tester.tap(find.byTooltip('管理资料').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('归档'));
    await tester.pumpAndSettle();
    expect(c.data.items.every((item) => item.isArchived), isTrue);
    expect(find.text('阅读资料 one'), findsNothing);
    await tester.tap(find.text('已归档'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('管理资料').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('移入回收站'));
    await tester.pumpAndSettle();
    final deletedId = c.data.items.firstWhere((item) => item.isTrashed).id;
    await tester.tap(find.text('回收站'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('管理资料').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复资料'));
    await tester.pumpAndSettle();
    expect(
      c.data.items.firstWhere((item) => item.id == deletedId).isArchived,
      isTrue,
    );
    expect(c.data.items.any((item) => item.isTrashed), isFalse);
    await c.trashItems([deletedId]);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('清空回收站'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(c.data.items.length, 2);
    await tester.tap(find.byTooltip('清空回收站'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('永久删除').last);
    await tester.pumpAndSettle();
    expect(c.data.items.length, 1);
    expect(find.text('回收站为空'), findsOneWidget);
  });

  testWidgets('search and lifecycle scope survive bottom navigation', (
    tester,
  ) async {
    final c = _controllerWith([article('one'), article('two')]);
    await c.archiveItems(['one']);
    await tester.pumpWidget(ReadlaterApp(controller: c));
    await tester.tap(find.text('资料').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('已归档'));
    await tester.enterText(find.byType(SearchBar), 'one');
    await tester.pump();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('资料').last);
    await tester.pumpAndSettle();
    expect(find.text('阅读资料 one'), findsOneWidget);
    expect(find.text('阅读资料 two'), findsNothing);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '已归档'))
          .selected,
      isTrue,
    );
    await tester.enterText(find.byType(SearchBar), 'missing');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的资料'), findsOneWidget);
  });

  testWidgets(
    'reader starts on analysis, switches tabs, archives remain readable',
    (tester) async {
      final item = article('one');
      final c = _controllerWith([item]);
      await c.archiveItems([item.id]);
      await tester.pumpWidget(
        MaterialApp(
          theme: readlaterTheme(),
          home: ArticleDetailPage(controller: c, item: item),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('这是一段已经完成的分析。'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == '重新分析',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('原文'));
      await tester.pumpAndSettle();
      expect(find.text(item.body), findsOneWidget);
      await tester.tap(find.text('笔记'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '我的阅读笔记');
      await tester.ensureVisible(find.text('保存笔记'));
      await tester.tap(find.text('保存笔记'));
      await tester.pumpAndSettle();
      expect(c.data.items.single.notes, '我的阅读笔记');
    },
  );

  testWidgets(
    'developer filters entity, displays task timeline and clears only after confirmation',
    (tester) async {
      final c = _controllerWith([article('one')]);
      c.diagnostics.debugEnabled = true;
      await c.diagnostics.runTask(
        type: 'analysis',
        title: '资料分析任务',
        entityId: 'one',
        body: () async {
          await c.diagnostics.step('读取本地资料', () async {});
          final call = DiagnosticScope.beginCall(
            endpoint: 'https://example.com/model',
            request: {'prompt': '资料摘要'},
            credential: 'secret-key',
            model: 'fixture-model',
          );
          DiagnosticScope.finishCall(
            call,
            response: '模拟分析响应',
            statusCode: 200,
            requestId: 'fixture-request',
            usage: {'total_tokens': 42},
          );
        },
      );
      await c.diagnostics.runTask(
        type: 'research',
        title: '其他研究任务',
        entityId: 'two',
        body: () async {},
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: readlaterTheme(),
          home: DeveloperPage(controller: c, entityId: 'one'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('资料分析任务'), findsOneWidget);
      expect(find.text('其他研究任务'), findsNothing);
      await tester.tap(find.text('资料分析任务'));
      await tester.pumpAndSettle();
      expect(find.text('执行时间线'), findsOneWidget);
      expect(find.text('读取本地资料'), findsOneWidget);
      await tester.ensureVisible(find.text('fixture-model'));
      await tester.tap(find.text('fixture-model'));
      await tester.pumpAndSettle();
      expect(find.text('请求 ID：fixture-request'), findsOneWidget);
      expect(find.textContaining('total_tokens'), findsOneWidget);
      expect(find.text('模拟分析响应'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('清空日志'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(c.diagnostics.tasks.length, 2);
      await tester.tap(find.byTooltip('清空日志'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();
      expect(c.diagnostics.tasks, isEmpty);
    },
  );

  testWidgets(
    'settings save preserves debug, retention and confirmed interests',
    (tester) async {
      final c = _controllerWith([]);
      c.data.settings.debugModelLogging = true;
      c.data.settings.trashRetentionDays = 3;
      c.data.settings.confirmedInterests = ['持续学习'];
      await tester.pumpWidget(ReadlaterApp(controller: c));
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('保存设置'),
        500,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('保存设置'));
      await tester.pumpAndSettle();
      expect(c.data.settings.debugModelLogging, isTrue);
      expect(c.data.settings.trashRetentionDays, 3);
      expect(c.data.settings.confirmedInterests, ['持续学习']);
    },
  );

  testWidgets(
    'trash header and results remain reachable with small screen keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final c = _controllerWith([article('one')]);
      await c.trashItems(['one']);
      await tester.pumpWidget(
        MaterialApp(
          theme: readlaterTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: ReadlaterShell(controller: c),
        ),
      );
      await tester.tap(find.text('资料').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('回收站'));
      await tester.tap(find.text('回收站'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(SearchBar), 'one');
      final focus = tester
          .widget<EditableText>(find.byType(EditableText).first)
          .focusNode;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(focus.hasFocus, isTrue);
      await tester.scrollUntilVisible(
        find.text('阅读资料 one'),
        180,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('阅读资料 one')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      expect(find.text('阅读资料 one').hitTestable(), findsOneWidget);
      expect(focus.hasFocus, isTrue);
      await tester.longPress(find.text('阅读资料 one'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('全选当前结果').hitTestable(), findsOneWidget);
      expect(find.byTooltip('管理资料').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('退出多选'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(SearchBar),
        -180,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.enterText(find.byType(SearchBar), 'missing');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('没有匹配的资料'),
        180,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('没有匹配的资料').hitTestable(), findsOneWidget);
      await c.purgeItems(['one']);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('回收站为空'),
        180,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('回收站为空').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'related diagnostics includes capture tasks linked only by input IDs',
    (tester) async {
      final c = _controllerWith([article('one')]);
      await c.diagnostics.runTask(
        type: 'capture',
        title: '抓取失败任务',
        inputItemIds: ['one'],
        body: () async {
          c.diagnostics.failCurrent('提取失败');
        },
      );
      await c.diagnostics.runTask(
        type: 'capture',
        title: '无关任务',
        inputItemIds: ['two'],
        body: () async {},
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: readlaterTheme(),
          home: DeveloperPage(controller: c, entityId: 'one'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('抓取失败任务'), findsOneWidget);
      expect(find.text('无关任务'), findsNothing);
      await tester.tap(find.text('抓取失败任务'));
      await tester.pumpAndSettle();
      expect(find.text('提取失败'), findsOneWidget);
    },
  );

  for (final width in [320.0, 390.0, 430.0]) {
    testWidgets('warm unified screens fit width $width at 1.8 text scale', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = _controllerWith([article('one')]);
      Widget wrap(Widget child) => MaterialApp(
        theme: readlaterTheme(),
        builder: (context, widget) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.8)),
          child: widget!,
        ),
        home: child,
      );
      await tester.pumpWidget(
        wrap(ArticleDetailPage(controller: c, item: c.data.items.single)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('原文'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(wrap(DeveloperPage(controller: c)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          theme: readlaterTheme(),
          builder: (context, widget) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.8)),
            child: widget!,
          ),
          home: ReadlaterShell(controller: c),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final label in ['RSS', '研究', '设置']) {
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.drag(find.byType(ListView).last, const Offset(0, -1800));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
