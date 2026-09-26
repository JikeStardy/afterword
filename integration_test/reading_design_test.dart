import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:readlater/core/app_controller.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/store.dart';
import 'package:readlater/main.dart';
import 'package:readlater/ui/item_detail.dart';

import '../test/support/reading_fixture.dart';

class _VisualController extends AppController {
  _VisualController({required super.store});
  @override
  Future<void> resume() async {}
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('three reading presets on Android with source round trip', (
    tester,
  ) async {
    final root = await getApplicationSupportDirectory();
    var converted = false;
    Future<void> screenshot(String name) async {
      if (!converted) {
        await binding.convertFlutterSurfaceToImage();
        converted = true;
      }
      await tester.pumpAndSettle();
      await binding.takeScreenshot(name);
    }

    for (final preset in ReadingPreset.values) {
      final directory = await Directory(
        '${root.path}/reading-design-${preset.name}-${DateTime.now().microsecondsSinceEpoch}',
      ).create();
      final controller = _VisualController(store: LocalStore(directory.path));
      controller.data = readingFixture(preset: preset);
      controller.store.save(controller.data);
      await tester.pumpWidget(ReadlaterApp(controller: controller));
      await tester.pumpAndSettle();
      await screenshot('${preset.name}-today');
      await tester.tap(find.text('资料').last);
      await tester.pumpAndSettle();
      await screenshot('${preset.name}-library');
      await tester.tap(find.text(controller.data.items.first.title).first);
      await tester.pumpAndSettle();
      expect(find.byType(ArticleDetailPage), findsOneWidget);
      await screenshot('${preset.name}-analysis');
      await tester.scrollUntilVisible(
        find.text('证据 · 1').first,
        350,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
        maxScrolls: 35,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('证据 · 1').first),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('证据 · 1').first);
      await tester.pumpAndSettle();
      final evidence = find.textContaining('段落 body-1').first;
      await Scrollable.ensureVisible(tester.element(evidence), alignment: .5);
      await tester.pumpAndSettle();
      await screenshot('${preset.name}-evidence');
      await tester.tap(evidence);
      await tester.pumpAndSettle();
      expect(find.textContaining('收藏并不等于理解。'), findsWidgets);
      await screenshot('${preset.name}-source');
      final selectable = find.byType(SelectableText).hitTestable();
      expect(
        selectable,
        findsWidgets,
        reason: 'source text must be selectable on Android',
      );
      if (selectable.evaluate().isNotEmpty) {
        await tester.longPress(selectable.first);
        await tester.pumpAndSettle();
        final selected = tester
            .widgetList<EditableText>(find.byType(EditableText))
            .any(
              (text) =>
                  text.controller.selection.isValid &&
                  !text.controller.selection.isCollapsed,
            );
        expect(
          selected,
          isTrue,
          reason: 'visible source text must support actual selection',
        );
        await tester.tap(find.byType(AppBar).first);
        await tester.pumpAndSettle();
      }
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.textContaining('段落 body-1'), findsWidgets);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('研究').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('阅读如何转化为可用的认识').first);
      await tester.pumpAndSettle();
      await screenshot('${preset.name}-research');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('设置').last);
      await tester.pumpAndSettle();
      await screenshot('${preset.name}-settings');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
