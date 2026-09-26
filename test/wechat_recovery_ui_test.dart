import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/app_controller.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/store.dart';
import 'package:readlater/platform/native_bridge.dart';
import 'package:readlater/ui/item_detail.dart';

void main() {
  testWidgets('wechat failed article can be recovered from opened page', (
    tester,
  ) async {
    final native = _FakeNativeBridge(
      capture: const WebArticleCapture(
        url: 'https://mp.weixin.qq.com/s/example',
        html: '''
          <html><head><title>页面保存标题</title></head>
          <body><div id="js_content"><p>从打开的页面保存的正文</p></div></body></html>
        ''',
      ),
    );
    final controller = _controller([
      _webItem(url: 'https://mp.weixin.qq.com/s/example', error: '需要验证'),
    ], native: native);

    await _pumpDetail(tester, controller);

    expect(find.text('补全网页正文'), findsOneWidget);
    expect(find.text('打开页面保存'), findsOneWidget);
    await tester.tap(find.text('打开页面保存'));
    await _pumpAction(tester);

    expect(native.captureCalls, 1);
    expect(controller.data.items, hasLength(1));
    expect(controller.data.items.single.body, '从打开的页面保存的正文');
    expect(
      controller.data.items.single.url,
      'https://mp.weixin.qq.com/s/example',
    );
    expect(find.text('正文已保存'), findsOneWidget);
    expect(find.text('正文从打开的页面保存'), findsOneWidget);
  });

  testWidgets('wechat recovery cancellation does not show success', (
    tester,
  ) async {
    final native = _FakeNativeBridge();
    final controller = _controller([
      _webItem(url: 'https://mp.weixin.qq.com/s/example', error: '需要验证'),
    ], native: native);

    await _pumpDetail(tester, controller);
    await tester.tap(find.text('打开页面保存'));
    await _pumpAction(tester);

    expect(native.captureCalls, 1);
    expect(find.text('正文已保存'), findsNothing);
    expect(controller.data.items.single.body, isEmpty);
  });

  testWidgets('wechat recovery errors are visible', (tester) async {
    final native = _FakeNativeBridge(error: StateError('验证窗口异常'));
    final controller = _controller([
      _webItem(url: 'https://mp.weixin.qq.com/s/example', error: '需要验证'),
    ], native: native);

    await _pumpDetail(tester, controller);
    await tester.tap(find.text('打开页面保存'));
    await _pumpAction(tester);

    expect(find.textContaining('验证窗口异常'), findsOneWidget);
  });

  testWidgets('wechat open-page action follows strict url eligibility', (
    tester,
  ) async {
    final controller = _controller([
      _webItem(url: 'https://user@mp.weixin.qq.com/s/example', error: '需要验证'),
    ]);

    await _pumpDetail(tester, controller);

    expect(find.text('补全网页正文'), findsOneWidget);
    expect(find.text('打开页面保存'), findsNothing);
    expect(find.text('粘贴正文'), findsOneWidget);
  });

  testWidgets('manual paste saves body on the existing web item', (
    tester,
  ) async {
    final controller = _controller([
      _webItem(url: 'https://example.com/article', error: '抓取失败'),
    ]);

    await _pumpDetail(
      tester,
      controller,
      size: const Size(320, 560),
      textScale: 1.8,
    );

    expect(find.text('打开页面保存'), findsNothing);
    await tester.ensureVisible(find.text('粘贴正文'));
    await tester.pump();
    await tester.tap(find.text('粘贴正文'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final saveButton = find.widgetWithText(FilledButton, '保存');
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, '人工补入标题');
    await tester.enterText(
      find.byType(TextField).last,
      '这是一段手动粘贴的正文，里面保留 https://mp.weixin.qq.com/s/abc 作为普通文本。',
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);
    await tester.ensureVisible(saveButton);
    await tester.pump();
    expect(saveButton.hitTestable(), findsOneWidget);
    await tester.tap(saveButton);
    await _pumpAction(tester);

    expect(controller.data.items, hasLength(1));
    expect(controller.data.items.single.id, 'web-1');
    expect(controller.data.items.single.title, '人工补入标题');
    expect(controller.data.items.single.url, 'https://example.com/article');
    expect(
      controller.data.items.single.body,
      contains('https://mp.weixin.qq.com/s/abc'),
    );
    expect(controller.data.items.single.bodyOrigin, 'pasted');
    expect(find.text('正文已保存'), findsOneWidget);
    expect(find.text('正文由你粘贴，来源链接保留'), findsOneWidget);
  });

  testWidgets('existing body analysis or waiting errors do not show recovery', (
    tester,
  ) async {
    final waiting = _controller([
      _webItem(
        url: 'https://example.com/waiting',
        status: 'retryable',
        error: '原文已保存，配置模型后可分析',
        body: '已有正文',
      ),
    ]);
    await _pumpDetail(tester, waiting);

    expect(find.text('已有正文'), findsOneWidget);
    expect(find.text('补全网页正文'), findsNothing);
    expect(find.text('粘贴正文'), findsNothing);

    final analysisFailed = _controller([
      _webItem(
        url: 'https://example.com/analysis',
        status: 'failed',
        error: '分析失败：模型暂不可用',
        body: '已有正文',
      ),
    ]);
    await _pumpDetail(tester, analysisFailed);

    expect(find.text('已有正文'), findsOneWidget);
    expect(find.text('补全网页正文'), findsNothing);
    expect(find.text('粘贴正文'), findsNothing);
  });

  testWidgets('paste dialog result is ignored after detail disposal', (
    tester,
  ) async {
    final controller = _controller([
      _webItem(url: 'https://example.com/article', error: '正文提取失败：需要验证'),
    ]);
    final detailVisible = ValueNotifier<bool>(true);
    addTearDown(detailVisible.dispose);

    await _pumpDisposableDetail(tester, controller, detailVisible);
    await tester.tap(find.text('粘贴正文'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField).last, '卸载前输入的正文');
    detailVisible.value = false;
    await tester.pump();
    expect(find.text('保存'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(controller.data.items.single.body, isEmpty);
  });

  testWidgets('archived and trashed failed articles disable recovery actions', (
    tester,
  ) async {
    final archived = _controller([
      _webItem(
        id: 'archived',
        url: 'https://mp.weixin.qq.com/s/archived',
        error: '需要验证',
        archivedAt: DateTime(2026),
      ),
    ]);
    await _pumpDetail(tester, archived);

    expect(find.text('资料已归档，取消归档后才能补正文。'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '打开页面保存'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '粘贴正文'))
          .onPressed,
      isNull,
    );

    final trashed = _controller([
      _webItem(
        id: 'trashed',
        url: 'https://mp.weixin.qq.com/s/trashed',
        error: '需要验证',
        trashedAt: DateTime(2026),
      ),
    ]);
    await _pumpDetail(tester, trashed);

    expect(find.text('资料在回收站，恢复后才能补正文。'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '打开页面保存'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '粘贴正文'))
          .onPressed,
      isNull,
    );
  });
}

_RecoveryController _controller(
  List<LibraryItem> items, {
  NativeBridge? native,
}) {
  final dir = Directory.systemTemp.createTempSync('readlater_wechat_ui_');
  final controller = _RecoveryController(
    store: LocalStore('${dir.path}/lib'),
    native: native,
  );
  controller.data = AppData(items: items);
  controller.store.save(controller.data);
  addTearDown(() {
    controller.dispose();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  return controller;
}

LibraryItem _webItem({
  String id = 'web-1',
  required String url,
  String error = '',
  String status = 'failed',
  String body = '',
  DateTime? archivedAt,
  DateTime? trashedAt,
}) => LibraryItem(
  id: id,
  title: Uri.parse(url).host,
  kind: ItemKind.web,
  url: url,
  body: body,
  status: status,
  error: error,
  archivedAt: archivedAt,
  trashedAt: trashedAt,
);

Future<void> _pumpDetail(
  WidgetTester tester,
  _RecoveryController controller, {
  Size size = const Size(390, 720),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: ArticleDetailPage(
        controller: controller,
        item: controller.data.items.single,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpDisposableDetail(
  WidgetTester tester,
  _RecoveryController controller,
  ValueListenable<bool> detailVisible, {
  Size size = const Size(390, 720),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  await tester.pumpWidget(
    _DisposableDetailHost(
      controller: controller,
      detailVisible: detailVisible,
      textScale: textScale,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpAction(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

class _RecoveryController extends AppController {
  _RecoveryController({required super.store, super.native});

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<void> resume() async {}
}

class _DisposableDetailHost extends StatelessWidget {
  const _DisposableDetailHost({
    required this.controller,
    required this.detailVisible,
    required this.textScale,
  });

  final _RecoveryController controller;
  final ValueListenable<bool> detailVisible;
  final double textScale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: ValueListenableBuilder<bool>(
        valueListenable: detailVisible,
        builder: (context, visible, _) => visible
            ? ArticleDetailPage(
                controller: controller,
                item: controller.data.items.single,
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

class _FakeNativeBridge extends NativeBridge {
  _FakeNativeBridge({this.capture, this.error});

  final WebArticleCapture? capture;
  final Object? error;
  int captureCalls = 0;

  @override
  Future<WebArticleCapture?> captureWebArticle(String url) async {
    captureCalls++;
    if (error != null) throw error!;
    return capture;
  }
}
