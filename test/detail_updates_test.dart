// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';

import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
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
  late FilePickerPlatform originalPicker;
  late _FakeFilePicker picker;

  setUp(() {
    calls = <MethodCall>[];
    originalPicker = FilePickerPlatform.instance;
    picker = _FakeFilePicker();
    FilePickerPlatform.instance = picker;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    FilePickerPlatform.instance = originalPicker;
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
          if (call.method == 'renderPdf') {
            return {'pageCount': 1, 'images': <String>[]};
          }
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

    expect(calls.where((call) => call.method == 'openFile'), hasLength(1));
    expect(find.textContaining('没有可用查看器'), findsOneWidget);
  });

  testWidgets('article detail opens preserved content revisions', (
    tester,
  ) async {
    final controller = _controller(
      AppData(
        items: [
          LibraryItem(
            id: 'i1',
            title: '当前标题',
            kind: ItemKind.web,
            body: '当前正文',
            contentHistory: [
              ContentRevision(
                version: 1,
                title: '旧标题',
                body: '旧正文保留下来',
                blocks: [
                  ContentBlock(
                    id: 'old-1',
                    kind: ContentBlockKind.paragraph,
                    text: '旧段落可查看',
                  ),
                ],
                savedAt: DateTime(2026, 9, 22, 20),
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

    expect(find.text('历史正文 · 1'), findsOneWidget);
    await tester.tap(find.text('历史正文 · 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('v1 · 旧标题'));
    await tester.pumpAndSettle();

    expect(find.textContaining('旧段落可查看'), findsOneWidget);
    expect(find.textContaining('当前正文'), findsOneWidget);
  });

  testWidgets('web warning offers image-only retry without refetching text', (
    tester,
  ) async {
    final controller = _controller(
      AppData(
        items: [
          LibraryItem(
            id: 'i1',
            title: '网页',
            kind: ItemKind.web,
            body: '正文',
            warning: '正文已保存，2 张图片未能下载，可重试补图',
          ),
        ],
      ),
    );
    controller.runtime.jobs.add(
      BackgroundJob(
        id: 'old',
        type: 'fetch',
        entityId: 'i1',
        status: 'complete',
        checkpoint: {
          'imageUrls': ['https://example.com/a.png'],
          'savedImages': <String, Object?>{},
        },
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

    expect(find.text('重试补图'), findsOneWidget);
    await tester.ensureVisible(find.byIcon(Icons.image_search_outlined));
    await tester.pumpAndSettle();
    final button = tester.widget<TextButton>(
      find.widgetWithIcon(TextButton, Icons.image_search_outlined),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('highlight prompt saves note and lists annotations', (
    tester,
  ) async {
    final controller = _controller(
      AppData(
        items: [
          LibraryItem(
            id: 'i1',
            title: '可批注文章',
            kind: ItemKind.text,
            body: '正文',
            contentBlocks: [
              ContentBlock(
                id: 'b1',
                kind: ContentBlockKind.paragraph,
                text: '需要高亮的段落',
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

    await tester.tap(find.byTooltip('高亮本段'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '这是一条批注');
    await tester.tap(find.text('保存').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('笔记'));
    await tester.pumpAndSettle();

    expect(find.text('高亮与页笔记'), findsOneWidget);
    expect(find.text('需要高亮的段落'), findsOneWidget);
    expect(find.text('这是一条批注'), findsOneWidget);
    await tester.tap(find.byTooltip('编辑批注'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '更新后的批注');
    await tester.pump();
    expect(
      controller.store.load().items.single.annotations.single.note,
      '更新后的批注',
    );
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(controller.data.items.single.annotations.single.note, '更新后的批注');
    expect(find.text('更新后的批注'), findsOneWidget);
    controller.data.items.single.annotations.single.anchor.unresolved = true;
    await controller.updateAnnotation(
      'i1',
      controller.data.items.single.annotations.single.id,
      '保留旧批注',
    );
    await tester.pump();
    expect(find.text('原文位置已失效，已保留摘录'), findsOneWidget);
    expect(find.text('需要高亮的段落'), findsOneWidget);
  });

  testWidgets('PDF restores page, navigates, and autosaves page notes', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'renderPdf') {
            return {'pageCount': 3, 'images': <String>[]};
          }
          return null;
        });
    final controller = _controller(
      AppData(
        items: [
          LibraryItem(
            id: 'pdf',
            title: 'PDF正文',
            kind: ItemKind.pdf,
            readingPosition: ReadingPosition(pdfPage: 2),
            assets: [
              Asset(
                path: 'assets/a.pdf',
                name: 'a.pdf',
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
    await tester.pumpAndSettle();
    expect(find.text('PDF 第 2/3 页'), findsOneWidget);
    expect(
      (calls.where((call) => call.method == 'renderPdf').single.arguments
          as Map)['startPage'],
      1,
    );
    await tester.tap(find.text('下一页'));
    await tester.pumpAndSettle();
    expect(find.text('PDF 第 3/3 页'), findsOneWidget);
    expect(controller.data.items.single.readingPosition?.pdfPage, 3);
    await tester.tap(find.text('页笔记'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '第3页的判断');
    await tester.pump();
    final saved = controller.store.load().items.single.annotations.single;
    expect(saved.note, '第3页的判断');
    expect(saved.anchor.pdfPage, 3);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('页笔记'));
    await tester.pumpAndSettle();
    expect(find.text('第3页的判断'), findsOneWidget);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'context picker preserves note provenance and excludes archives',
    (tester) async {
      SourceContextInput? selected;
      await tester.pumpWidget(
        _wrap(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  selected = await showSourceContextPicker(context, [
                    LibraryItem(
                      id: 'active',
                      title: '可用资料',
                      kind: ItemKind.text,
                      body: '资料正文',
                      notes: '个人笔记',
                    ),
                    LibraryItem(
                      id: 'archived',
                      title: '旧归档',
                      kind: ItemKind.text,
                      body: '禁止导入',
                      archivedAt: DateTime(2026),
                    ),
                  ]);
                },
                child: const Text('导入'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('导入'));
      await tester.pumpAndSettle();
      expect(find.text('旧归档'), findsNothing);
      expect(find.text('禁止导入'), findsNothing);
      expect(find.text('个人笔记'), findsOneWidget);
      await tester.tap(find.text('加入'));
      await tester.pumpAndSettle();
      expect(selected?.sourceId, 'active');
      expect(selected?.text, '个人笔记');
    },
  );

  testWidgets('evidence target opens original even when source has analysis', (
    tester,
  ) async {
    final controller = _controller(
      AppData(
        items: [
          LibraryItem(
            id: 'source',
            title: '来源',
            kind: ItemKind.text,
            body: '证据原文',
            contentBlocks: [
              ContentBlock(
                id: 'target',
                kind: ContentBlockKind.paragraph,
                text: '证据原文',
              ),
            ],
            analysis: Analysis(summary: '来源分析'),
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      _wrap(
        ArticleDetailPage(
          controller: controller,
          item: controller.data.items.single,
          initialBlockId: 'target',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('证据原文'), findsOneWidget);
    expect(find.text('来源分析'), findsNothing);
    expect(controller.data.items.single.readingPosition?.blockId, 'target');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('article markdown export writes a real markdown file payload', (
    tester,
  ) async {
    final controller = _controller(
      AppData(
        items: [
          LibraryItem(
            id: 'i1',
            title: '导出文章',
            kind: ItemKind.text,
            body: '正文',
            notes: '导出笔记',
            analysis: Analysis(summary: '导出总结'),
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

    await tester.tap(find.byTooltip('导出 Markdown'));
    await tester.pump();

    expect(picker.savedFileName, endsWith('.md'));
    final markdown = utf8.decode(picker.savedBytes!);
    expect(markdown, contains('# 导出文章'));
    expect(markdown, contains('导出笔记'));
    expect(markdown, contains('导出总结'));
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

class _FakeFilePicker extends FilePickerPlatform
    with MockPlatformInterfaceMixin {
  String? savedFileName;
  Uint8List? savedBytes;
  String? savedMimeType;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    savedFileName = fileName;
    savedBytes = bytes;
    savedMimeType = mimeType;
    return Uri.parse('content://readlater/$fileName');
  }
}
