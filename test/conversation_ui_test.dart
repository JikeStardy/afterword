import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/app_controller.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/retrieval.dart';
import 'package:readlater/core/store.dart';
import 'package:readlater/ui/common.dart';
import 'package:readlater/ui/conversation_page.dart';
import 'package:readlater/ui/item_detail.dart';
import 'package:readlater/ui/knowledge_page.dart';

class _DialogueController extends AppController {
  _DialogueController({required super.store});

  @override
  Future<void> resume() async {}
}

_DialogueController _controller(AppData data) {
  final directory = Directory.systemTemp.createTempSync(
    'readlater_conversation_ui_',
  );
  final controller = _DialogueController(
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

void _setSurface(
  WidgetTester tester, {
  double width = 360,
  double height = 800,
}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
}

Widget _wrap(Widget child, {double scale = 1}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: readlaterTheme(),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child,
      ),
    ),
  );
}

void main() {
  testWidgets(
    'conversation source picker and completed answer evidence render',
    (tester) async {
      _setSurface(tester, width: 320, height: 800);
      final item = LibraryItem(
        id: 'item-1',
        title: '长资料',
        kind: ItemKind.web,
        body: '来源原文',
      );
      final archived = LibraryItem(
        id: 'archived-1',
        title: '归档资料',
        kind: ItemKind.text,
        body: '不应进入来源选择',
        archivedAt: DateTime(2026, 10, 1),
      );
      final controller = _controller(
        AppData(
          items: [item, archived],
          conversations: [
            Conversation(
              id: 'conversation-1',
              title: '资料追问',
              scope: ConversationScope.item,
              scopeId: 'item-1',
              sourceIds: const ['item-1'],
            ),
            Conversation(
              id: 'library-history',
              title: '旧知识库会话',
              scope: ConversationScope.library,
              updatedAt: DateTime(2026, 10, 2),
            ),
          ],
          conversationTurns: [
            ConversationTurn(
              id: 'turn-1',
              conversationId: 'conversation-1',
              question: '这篇资料的核心是什么？',
              status: 'completed',
              stage: '完成回答',
              answer: '回答会引用来源窗口。',
              calls: 2,
              callLimit: 5,
              textBudgetChars: 24000,
              inputItemIds: const ['item-1'],
              sourceVersions: {'item-1': item.contentVersion},
              sourceFingerprints: {'item-1': sourceFingerprint(item)},
              evidence: [EvidenceAnchor(sourceId: 'item-1', quote: '来源原文')],
              windows: [
                SourceWindow(
                  id: 'window-1',
                  sourceId: 'item-1',
                  sourceVersion: 1,
                  blockId: 'body-1',
                  start: 0,
                  end: 4,
                  text: '来源原文',
                  fingerprint: 'fp',
                ),
              ],
              visualEvidence: [
                VisualEvidence(
                  sourceId: 'item-1',
                  sourceVersion: 1,
                  assetFingerprint: 'asset-fp',
                  observation: '图中包含流程图',
                ),
              ],
            ),
            ConversationTurn(
              id: 'turn-paused',
              conversationId: 'conversation-1',
              question: '暂停问题',
              status: 'paused',
              error: '等待用户重试',
              calls: 1,
              callLimit: 3,
              inputItemIds: const ['item-1'],
              sourceVersions: {'item-1': item.contentVersion},
              sourceFingerprints: {'item-1': sourceFingerprint(item)},
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        _wrap(
          ConversationPage(
            controller: controller,
            scope: ConversationScope.item,
            scopeId: 'item-1',
            sourceIds: const ['item-1'],
          ),
          scale: 1.8,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('回答会引用来源窗口。'), findsOneWidget);
      expect(find.text('调用：2/5'), findsOneWidget);
      expect(find.text('预算：24000 字符'), findsOneWidget);
      expect(find.textContaining('视觉观察不是精确校验'), findsOneWidget);
      expect(find.text('沉淀为知识'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.scrollUntilVisible(
        find.text('暂停问题'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('暂停问题'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.showKeyboard(find.byType(TextField));
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pump();
      expect(tester.takeException(), isNull);
      tester.testTextInput.hide();
      tester.view.resetViewInsets();
      await tester.pump();

      await tester.pumpWidget(
        _wrap(
          ConversationPage(
            controller: controller,
            scope: ConversationScope.library,
            title: '问知识库',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('旧知识库会话'), findsOneWidget);
      await tester.tap(find.byTooltip('新对话'));
      await tester.pumpAndSettle();
      expect(find.text('选择对话来源'), findsOneWidget);
      expect(find.text('已排除 1 个归档或回收站资料。'), findsOneWidget);
      expect(find.text('归档资料'), findsNothing);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('长资料'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(
        controller.data.conversations.last.scope,
        ConversationScope.library,
      );
      expect(controller.data.conversations.last.sourceIds, ['item-1']);
    },
  );

  testWidgets('conversation evidence opens original source position', (
    tester,
  ) async {
    _setSurface(tester, width: 360, height: 800);
    final textItem = LibraryItem(
      id: 'text-source',
      title: '段落资料',
      kind: ItemKind.text,
      analysis: Analysis(summary: '已有分析不应成为初始页签'),
      contentBlocks: [
        ContentBlock(
          id: 'intro',
          kind: ContentBlockKind.paragraph,
          text: '开头段落',
        ),
        ContentBlock(
          id: 'target-block',
          kind: ContentBlockKind.paragraph,
          text: '需要定位的原文段落',
        ),
      ],
    );
    final pdfItem = LibraryItem(
      id: 'pdf-source',
      title: 'PDF资料',
      kind: ItemKind.pdf,
      assets: [
        Asset(
          path: '/tmp/missing.pdf',
          name: 'missing.pdf',
          mime: 'application/pdf',
        ),
      ],
      analysis: Analysis(summary: 'PDF已有分析不应优先打开'),
      pdfPageCount: 5,
    );
    final controller = _controller(
      AppData(
        items: [textItem, pdfItem],
        conversations: [
          Conversation(
            id: 'conversation-1',
            title: '定位对话',
            scope: ConversationScope.library,
          ),
        ],
        conversationTurns: [
          ConversationTurn(
            id: 'turn-1',
            conversationId: 'conversation-1',
            question: '定位证据',
            status: 'completed',
            answer: '请查看原文位置。',
            windows: [
              SourceWindow(
                id: 'window-1',
                sourceId: 'text-source',
                sourceVersion: 1,
                blockId: 'target-block',
                start: 0,
                end: 8,
                text: '需要定位的原文段落',
                fingerprint: 'window-fp',
              ),
            ],
            evidence: [
              EvidenceAnchor(
                sourceId: 'pdf-source',
                blockId: 'pdf-page-3',
                pdfPage: 3,
                quote: 'PDF第三页证据',
              ),
            ],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      _wrap(
        ConversationPage(
          controller: controller,
          scope: ConversationScope.library,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('读取窗口 · 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('段落资料'));
    await tester.pumpAndSettle();
    final textPage = tester.widget<ArticleDetailPage>(
      find.byType(ArticleDetailPage),
    );
    expect(textPage.initialBlockId, 'target-block');
    expect(textPage.initialPdfPage, isNull);

    Navigator.of(tester.element(find.byType(ArticleDetailPage))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('证据 · 1'));
    await tester.pumpAndSettle();
    final pdfTile = find.ancestor(
      of: find.text('PDF资料'),
      matching: find.byType(ListTile),
    );
    await tester.tap(pdfTile);
    await tester.pumpAndSettle();
    final pdfPage = tester.widget<ArticleDetailPage>(
      find.byType(ArticleDetailPage),
    );
    expect(pdfPage.initialBlockId, 'pdf-page-3');
    expect(pdfPage.initialPdfPage, 3);
  });

  testWidgets('knowledge proposal can be edited, accepted and rejected', (
    tester,
  ) async {
    _setSurface(tester, width: 360, height: 800);
    final item = LibraryItem(
      id: 'item-1',
      title: '长资料',
      kind: ItemKind.text,
      body: '分段证据',
    );
    final fingerprint = sourceFingerprint(item);
    final controller = _controller(
      AppData(
        items: [item],
        topics: [
          Topic(
            id: 'topic-1',
            title: '长资料理解',
            question: '怎样避免整篇塞给模型？',
            overview: '旧的自动综述仍可阅读。',
            currentKnowledgeRevisionId: 'rev-1',
          ),
        ],
        knowledgeRevisions: [
          KnowledgeRevision(
            id: 'rev-1',
            topicId: 'topic-1',
            presentation: ReadingPresentation(brief: '旧版确认知识'),
            inputItemIds: const ['item-1'],
            sourceVersions: {'item-1': item.contentVersion},
            sourceFingerprints: {'item-1': fingerprint},
          ),
          KnowledgeRevision(
            id: 'rev-old',
            topicId: 'topic-1',
            presentation: ReadingPresentation(brief: '更早版本'),
            inputItemIds: const ['item-1'],
            sourceVersions: {'item-1': item.contentVersion},
            sourceFingerprints: {'item-1': fingerprint},
          ),
        ],
        knowledgeProposals: [
          KnowledgeProposal(
            id: 'proposal-1',
            topicId: 'topic-1',
            title: '分段读取',
            question: '如何处理超长资料？',
            presentation: ReadingPresentation(brief: '先分段摘要，再按问题读取窗口。'),
            baseRevisionId: 'rev-1',
            inputItemIds: const ['item-1'],
            sourceVersions: {'item-1': item.contentVersion},
            sourceFingerprints: {'item-1': fingerprint},
            evidence: [EvidenceAnchor(sourceId: 'item-1', quote: '分段证据')],
            createdAt: DateTime(2026, 10, 2, 12),
          ),
          KnowledgeProposal(
            id: 'proposal-2',
            topicId: 'topic-1',
            title: '待拒绝',
            question: '是否保留？',
            createdAt: DateTime(2026, 10, 1, 12),
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      _wrap(KnowledgePage(controller: controller, topicId: 'topic-1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('已确认知识'), findsOneWidget);
    expect(find.text('自动综述'), findsOneWidget);
    expect(find.text('变更对照'), findsNWidgets(2));

    await tester.scrollUntilVisible(
      find.text('编辑并确认').first,
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑并确认').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '摘要'), '编辑后的确认知识');
    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.pumpAndSettle();

    final proposal1 = controller.data.knowledgeProposals.firstWhere(
      (proposal) => proposal.id == 'proposal-1',
    );
    expect(proposal1.status, 'accepted');
    expect(
      controller.data.knowledgeRevisions.last.presentation.brief,
      '编辑后的确认知识',
    );

    await tester.tap(find.text('拒绝').first);
    await tester.pumpAndSettle();
    expect(
      controller.data.knowledgeProposals
          .firstWhere((proposal) => proposal.id == 'proposal-2')
          .status,
      'rejected',
    );

    await tester.scrollUntilVisible(
      find.text('更早版本'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final oldRevisionTile = find.ancestor(
      of: find.text('更早版本'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: oldRevisionTile, matching: find.text('恢复')),
    );
    await tester.pumpAndSettle();
    expect(controller.data.knowledgeRevisions.last.parentId, isNotNull);
    expect(controller.data.knowledgeRevisions.last.presentation.brief, '更早版本');
    expect(tester.takeException(), isNull);
  });

  testWidgets('topic overview is not shown as confirmed knowledge', (
    tester,
  ) async {
    _setSurface(tester, width: 360, height: 800);
    final controller = _controller(
      AppData(
        topics: [
          Topic(
            id: 'topic-without-revision',
            title: '只有自动综述',
            question: '旧综述是否算确认知识？',
            overview: '这只是自动综述，不是已确认知识。',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      _wrap(
        KnowledgePage(
          controller: controller,
          topicId: 'topic-without-revision',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已确认知识'), findsOneWidget);
    expect(find.text('暂无已确认知识。'), findsOneWidget);
    expect(find.text('自动综述'), findsOneWidget);
    expect(find.text('这只是自动综述，不是已确认知识。'), findsNothing);

    await tester.tap(find.text('自动综述'));
    await tester.pumpAndSettle();
    expect(find.text('这只是自动综述，不是已确认知识。'), findsOneWidget);
  });
  testWidgets('explicit initial thread opens the notified older conversation', (
    tester,
  ) async {
    final controller = _controller(
      AppData(
        conversations: [
          Conversation(
            id: 'older',
            title: '原会话',
            scope: ConversationScope.library,
            updatedAt: DateTime(2020),
          ),
          Conversation(
            id: 'newer',
            title: '新会话',
            scope: ConversationScope.library,
            updatedAt: DateTime(2026),
          ),
        ],
        conversationTurns: [
          ConversationTurn(
            id: 'oldturn',
            conversationId: 'older',
            question: '原问题',
            answer: '通知指向的原回答',
            status: 'completed',
          ),
          ConversationTurn(
            id: 'newturn',
            conversationId: 'newer',
            question: '新问题',
            answer: '新会话回答',
            status: 'completed',
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      _wrap(
        ConversationPage(
          controller: controller,
          scope: ConversationScope.library,
          initialConversationId: 'older',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('通知指向的原回答'), findsOneWidget);
    expect(find.text('新会话回答'), findsNothing);
  });
}
