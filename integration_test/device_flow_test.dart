import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:readlater/core/app_controller.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/store.dart';
import 'package:readlater/main.dart';
import 'package:readlater/ui/developer_page.dart';
import 'package:readlater/ui/item_detail.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const base = 'http://127.0.0.1:18765';
  testWidgets(
    'Android v2 storage, diagnostics, lifecycle and rendered screens',
    (tester) async {
      final initialSearchCount = jsonDecode(
        (await http.get(Uri.parse('$base/stats'))).body,
      )['search'];
      final temp = await getApplicationSupportDirectory();
      final screens = await Directory('${temp.path}/v2-screens')
          .create(recursive: true);
      var surfaceConverted = false;
      Future<void> screenshot(String name) async {
        if (!surfaceConverted) {
          await binding.convertFlutterSurfaceToImage();
          surfaceConverted = true;
        }
        await tester.pump();
        await tester.pumpAndSettle();
        final bytes = await binding.takeScreenshot(name);
        expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        await File('${screens.path}/$name.png')
            .writeAsBytes(bytes, flush: true);
      }

      final directory = await Directory(
        '${temp.path}/integration-${DateTime.now().microsecondsSinceEpoch}',
      ).create();
      var controller = AppController(store: LocalStore(directory.path));
      await controller.initialize();
      await controller.saveSettings(
        AppSettings(
          endpoint: '$base/v1',
          textModel: 'fixture-text',
          visionModel: 'fixture-vision',
          searchEndpoint: '$base/search',
          explicitInterests: ['适用条件'],
        ),
        apiKey: 'fixture-key',
        searchKey: 'fixture-key',
      );
      await tester.pumpWidget(ReadlaterApp(controller: controller));
      await tester.pumpAndSettle();
      expect(find.text('资料'), findsWidgets);
      final article = await controller.captureUrl('$base/wechat');
      await controller.waitForIdle();
      expect(article.status, 'ready');
      expect(article.body, contains('保留原文出处'));
      expect(article.assets, isNotEmpty);
      expect(
        File(controller.assetPath(article.assets.first)).existsSync(),
        isTrue,
      );
      expect(article.analysis!.sourceIds, contains(article.id));
      expect(article.analysis!.inputItemIds, contains(article.id));
      expect(controller.diagnostics.debugEnabled, isFalse);
      final basicTasks = controller.diagnostics.tasks;
      final basicCalls = basicTasks.expand((task) => task.calls).toList();
      expect(basicCalls, isNotEmpty);
      expect(
        basicCalls.every(
          (call) => call.request == null && call.response == null,
        ),
        isTrue,
      );
      expect(
        basicCalls.any(
          (call) => call.statusCode == 200 && call.model == 'fixture-text',
        ),
        isTrue,
      );
      final basicTaskIds = basicTasks.map((task) => task.id).toSet();
      await controller.setDebugModelLogging(true);
      await controller.analyze(article.id);
      final debugTask = controller.diagnostics.tasks.firstWhere(
        (task) =>
            task.entityId == article.id &&
            task.type == 'analysis' &&
            !basicTaskIds.contains(task.id),
      );
      expect(debugTask.status, 'succeeded');
      expect(debugTask.steps, isNotEmpty);
      final debugCall = debugTask.calls.firstWhere(
        (call) => call.model == 'fixture-text',
      );
      expect(debugCall.statusCode, 200);
      expect(debugCall.request, contains('生成观点卡片'));
      expect(debugCall.response, contains('收藏只有带着问题阅读'));
      expect(
        debugCall.usage,
        isNull,
        reason:
            'The deterministic fixture does not return actual provider usage.',
      );
      expect(
        controller.diagnostics.tasks
            .where((task) => basicTaskIds.contains(task.id))
            .expand((task) => task.calls)
            .every((call) => call.request == null && call.response == null),
        isTrue,
      );
      final exportedLogs = utf8.decode(
        controller.diagnostics.exportLogs(taskId: debugTask.id),
      );
      expect(exportedLogs, contains('生成观点卡片'));
      expect(exportedLogs, isNot(contains('fixture-key')));
      await File('${screens.path}/debug-task-redacted.json')
          .writeAsString(exportedLogs, flush: true);

      final before = jsonDecode(
        (await http.get(Uri.parse('$base/stats'))).body,
      )['analysis'];
      await controller.addFeed('$base/feed');
      final after = jsonDecode(
        (await http.get(Uri.parse('$base/stats'))).body,
      )['analysis'];
      expect(after, before);
      expect(controller.data.entries.length, 2);
      await controller.selectEntry(controller.data.entries.last.id);
      await controller.waitForIdle();
      expect(controller.data.items.length, 2);
      final discovered = controller.data.topics.singleWhere(
        (topic) => topic.automatic,
      );
      expect(discovered.title, '个人知识管理');
      expect(discovered.status, 'ready');
      expect(discovered.overview, isNotEmpty);
      expect(
        discovered.sourceIds,
        containsAll(controller.data.items.map((item) => item.id)),
      );
      expect(
        jsonDecode((await http.get(Uri.parse('$base/stats'))).body)['search'],
        initialSearchCount,
      );
      final pdfBytes = (await http.get(Uri.parse('$base/sample.pdf')))
          .bodyBytes;
      final pdf = await File('${directory.path}/fixture.pdf')
          .writeAsBytes(pdfBytes);
      final rendered = await controller.native.renderPdf(pdf.path);
      expect(rendered.pageCount, 1);
      expect(base64Decode(rendered.images.single), isNotEmpty);
      final pdfItem = await controller.importFile(pdf.path);
      await controller.waitForIdle();
      expect(pdfItem.status, 'ready');
      final image = await File(
        '${directory.path}/fixture.png',
      ).writeAsBytes((await http.get(Uri.parse('$base/image.png'))).bodyBytes);
      final imageItem = await controller.importFile(image.path);
      await controller.waitForIdle();
      expect(imageItem.status, 'ready');
      await expectLater(
        controller.research(goal: '知识管理', confirmed: false),
        throwsStateError,
      );
      final submittedRun = await controller.research(
        goal: imageItem.analysis!.questions.first,
        originItemId: imageItem.id,
        confirmed: true,
        callLimit: 4,
      );
      await controller.waitForIdle();
      final run = controller.data.runs.firstWhere(
        (run) => run.id == submittedRun.id,
      );
      expect(run.status, 'complete');
      expect(run.calls, 4);
      expect(run.sources, isNotEmpty);
      expect(run.report, contains('[S1]'));
      expect(run.inputItemIds, contains(imageItem.id));
      final runTask = controller.diagnostics.tasks.singleWhere(
        (task) => task.type == 'research' && task.entityId == run.id,
      );
      expect(runTask.status, 'succeeded');
      expect(runTask.calls, isNotEmpty);
      expect(
        runTask.calls.every(
          (call) => call.request != null && call.response != null,
        ),
        isTrue,
      );
      expect(
        utf8.decode(controller.diagnostics.exportLogs()),
        isNot(contains('fixture-key')),
      );

      await controller.clearNotices();
      await controller.dismissError();
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('资料'),
        ),
      );
      await tester.pumpAndSettle();
      await screenshot('library');
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ArticleDetailPage(controller: controller, item: article),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ArticleDetailPage), findsOneWidget);
      expect(
        DefaultTabController.of(tester.element(find.byType(TabBar))).index,
        1,
      );
      expect(find.text(article.analysis!.summary), findsOneWidget);
      await screenshot('reader-analysis');

      openDiagnostics(
        tester.element(find.byType(ArticleDetailPage)),
        controller,
        entityId: run.id,
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<DeveloperPage>(find.byType(DeveloperPage)).entityId,
        run.id,
      );
      expect(find.text('仅此资料 / 研究'), findsOneWidget);
      final taskTile = find.widgetWithText(ListTile, runTask.title);
      await tester.scrollUntilVisible(
        taskTile,
        240,
        scrollable: find
            .descendant(
              of: find.byType(DeveloperPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(taskTile);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DiagnosticTaskPage>(find.byType(DiagnosticTaskPage))
            .taskId,
        runTask.id,
      );
      expect(find.text('关联：${run.goal}'), findsOneWidget);
      expect(find.text('执行时间线'), findsOneWidget);
      await screenshot('developer-task');
      navigator.popUntil((route) => route.isFirst);
      await tester.pumpAndSettle();

      final savedAnalysis = jsonEncode(article.analysis!.toJson());
      await controller.archiveItems([article.id]);
      final archivedAt = article.archivedAt;
      expect(archivedAt, isNotNull);
      final analysisCountBeforeArchive = jsonDecode(
        (await http.get(Uri.parse('$base/stats'))).body,
      )['analysis'];
      await expectLater(controller.analyze(article.id), throwsStateError);
      expect(
        jsonDecode((await http.get(Uri.parse('$base/stats'))).body)['analysis'],
        analysisCountBeforeArchive,
      );
      expect(jsonEncode(article.analysis!.toJson()), savedAnalysis);
      await controller.trashItems([article.id]);
      expect(article.isArchived && article.isTrashed, isTrue);
      await controller.restoreItems([article.id]);
      expect(article.archivedAt, archivedAt);
      expect(article.trashedAt, isNull);
      expect(article.isActive, isFalse);
      expect(jsonEncode(article.analysis!.toJson()), savedAnalysis);

      final imagePath = controller.assetPath(imageItem.assets.single);
      final runInputs = List<String>.from(run.inputItemIds!);
      final runReport = run.report;
      await controller.trashItems([imageItem.id]);
      await controller.purgeItems([imageItem.id]);
      expect(File(imagePath).existsSync(), isFalse);
      expect(
        controller.data.items.any((item) => item.id == imageItem.id),
        isFalse,
      );
      final historicRun = controller.data.runs.singleWhere(
        (item) => item.id == run.id,
      );
      expect(historicRun.inputItemIds, runInputs);
      expect(historicRun.report, runReport);
      expect(controller.sourceLabel(imageItem.id), contains('来源已删除'));
      final purgedTasks = controller.diagnostics.tasks.where(
        (task) =>
            task.inputItemIds.contains(imageItem.id) ||
            task.entityId == imageItem.id,
      );
      expect(
        purgedTasks
            .expand((task) => task.calls)
            .every((call) => call.request == null && call.response == null),
        isTrue,
      );
      await controller.trashItems([pdfItem.id]);
      final pdfTrashedAt = pdfItem.trashedAt;
      expect(pdfTrashedAt, isNotNull);
      await controller.dismissError();

      final backup = await controller.backup();
      expect(
        utf8.decode(backup, allowMalformed: true),
        isNot(contains('fixture-key')),
      );
      final count = controller.data.items.length;
      final originalImageBytes = await File(
        controller.assetPath(article.assets.first),
      ).readAsBytes();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      controller.dispose();
      final restoredDirectory = await Directory('${directory.path}-restored')
          .create();
      controller = AppController(store: LocalStore(restoredDirectory.path));
      await controller.initialize();
      expect(controller.data.items, isEmpty);
      expect(controller.data.runs, isEmpty);
      await controller.restore(backup);
      expect(controller.data.items.length, count);
      expect(controller.data.settings.debugModelLogging, isFalse);
      expect(controller.diagnostics.debugEnabled, isFalse);
      expect(
        controller.data.items
            .singleWhere((item) => item.id == article.id)
            .archivedAt,
        archivedAt,
      );
      expect(
        controller.data.items
            .singleWhere((item) => item.id == pdfItem.id)
            .trashedAt,
        pdfTrashedAt,
      );
      expect(
        controller.data.runs
            .singleWhere((item) => item.id == run.id)
            .inputItemIds,
        runInputs,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      controller.dispose();
      controller = AppController(store: LocalStore(restoredDirectory.path));
      await controller.initialize();
      expect(controller.data.items.length, count);
      expect(controller.data.runs.single.report, contains('适用性'));
      final restoredArticle = controller.data.items.firstWhere(
        (item) => item.id == article.id,
      );
      expect(
        File(controller.assetPath(restoredArticle.assets.first)).existsSync(),
        isTrue,
      );
      expect(restoredArticle.body, article.body);
      expect(restoredArticle.archivedAt, archivedAt);
      expect(restoredArticle.trashedAt, isNull);
      expect(
        controller.data.items
            .singleWhere((item) => item.id == pdfItem.id)
            .trashedAt,
        pdfTrashedAt,
      );
      expect(
        controller.data.runs
            .singleWhere((item) => item.id == run.id)
            .inputItemIds,
        runInputs,
      );
      expect(restoredArticle.analysis!.summary, article.analysis!.summary);
      expect(
        await File(controller.assetPath(restoredArticle.assets.first))
            .readAsBytes(),
        originalImageBytes,
      );
      await tester.pumpWidget(ReadlaterApp(controller: controller));
      await tester.pumpAndSettle();
      expect(find.text('资料'), findsWidgets);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('资料'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '已归档'));
      await tester.pumpAndSettle();
      expect(find.text(restoredArticle.title), findsOneWidget);
      await screenshot('restored-archives');
      await File('${screens.path}/evidence.json').writeAsString(
        jsonEncode({
          'fixture': base,
          'screens': [
            'library.png',
            'reader-analysis.png',
            'developer-task.png',
            'restored-archives.png',
          ],
          'diagnosticTaskId': runTask.id,
          'diagnosticEntityId': run.id,
          'archivedAt': archivedAt!.toIso8601String(),
          'trashedAt': pdfTrashedAt!.toIso8601String(),
          'purgedItemId': imageItem.id,
          'preservedResearchInputs': runInputs,
          'restoredItemCount': count,
        }),
        flush: true,
      );
      // Remove the app's resume timer before disposing the test controller.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      controller.dispose();
      // Leave the genuine rendered archive view visible after test cleanup.
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: Center(
              child: Image.file(
                File('${screens.path}/restored-archives.png'),
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    },
  );
}
