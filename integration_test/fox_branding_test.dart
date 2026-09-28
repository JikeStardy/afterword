import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:readlater/core/app_controller.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/store.dart';
import 'package:readlater/main.dart';
import 'package:readlater/ui/afterword_art.dart';
import 'package:readlater/ui/common.dart';

import '../test/support/reading_fixture.dart';

class _BrandingController extends AppController {
  _BrandingController({required super.store});

  @override
  Future<void> resume() async {}
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'fox branding in real Android navigation, empty states and reading',
    (tester) async {
      final root = await getApplicationSupportDirectory();
      final directory = await Directory(
        '${root.path}/fox-branding-${DateTime.now().microsecondsSinceEpoch}',
      ).create();
      final controller = _BrandingController(store: LocalStore(directory.path))
        ..data = AppData();
      var converted = false;
      Future<void> capture(String name) async {
        if (!converted) {
          await binding.convertFlutterSurfaceToImage();
          converted = true;
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await binding.takeScreenshot(name);
      }

      try {
        await tester.pumpWidget(ReadlaterApp(controller: controller));
        await tester.pumpAndSettle();
        expect(find.byType(AfterwordScene), findsWidgets);
        expect(find.byType(AfterwordIcon), findsWidgets);
        await capture('fox-empty-today');
        for (final tab in ['资料', 'RSS', '研究', '设置']) {
          await tester.tap(find.text(tab).last);
          await capture('fox-tab-${['资料', 'RSS', '研究', '设置'].indexOf(tab)}');
        }

        controller.data = readingFixture();
        controller.data.runs.add(
          ResearchRun(
            id: 'fox-complete-run',
            goal: '长尾狐图标的设备验证',
            status: 'complete',
            report: '这是设备视觉测试夹具，研究已完成。',
            completedAt: DateTime.now(),
          ),
        );
        controller.notifyListeners();
        await tester.tap(find.text('资料').last);
        await capture('fox-populated-library');
        await tester.tap(find.text(controller.data.items.first.title).first);
        await capture('fox-reader');
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('研究').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('长尾狐图标的设备验证'));
        await capture('fox-research-complete');
        expect(find.text('已完成'), findsWidgets);

        // Native rendering evidence for all motion classes, independent of providers.
        await tester.pumpWidget(
          MaterialApp(
            theme: readlaterTheme(),
            home: Scaffold(
              appBar: AppBar(title: const Text('长尾狐 · 原生动效')),
              body: GridView.count(
                crossAxisCount: 2,
                childAspectRatio: 1.1,
                children: [
                  for (final entry in const <(String, FoxMotion)>[
                    ('today-clear', FoxMotion.idle),
                    ('capturing', FoxMotion.collect),
                    ('analyzing', FoxMotion.analyze),
                    ('saved', FoxMotion.saved),
                    ('library-empty', FoxMotion.empty),
                    ('startup-error', FoxMotion.retry),
                    ('paused', FoxMotion.paused),
                    ('complete', FoxMotion.complete),
                  ])
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AfterwordScene(
                          scene: entry.$1,
                          motion: entry.$2,
                          size: 94,
                        ),
                        Text(entry.$2.name),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
        await capture('fox-native-motions');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        await directory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
