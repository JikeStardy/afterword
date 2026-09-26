import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/app_controller.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/store.dart';
import 'package:readlater/main.dart';
import 'package:readlater/ui/common.dart';
import 'package:readlater/ui/settings_page.dart';

class _Controller extends AppController {
  _Controller({required super.store});
  @override
  Future<void> resume() async {}
}

void main() {
  test('preset filter labels remain legible and tab type sizes match', () {
    for (final preset in ReadingPreset.values) {
      final theme = readlaterTheme(preset);
      final ink = theme.chipTheme.labelStyle!.color!.computeLuminance();
      for (final background in [
        theme.colorScheme.surface,
        theme.colorScheme.primaryContainer,
      ]) {
        final light = background.computeLuminance();
        final contrast = (light + .05) / (ink + .05);
        expect(contrast, greaterThanOrEqualTo(4.5));
      }
      expect(
        theme.tabBarTheme.labelStyle!.fontSize,
        theme.tabBarTheme.unselectedLabelStyle!.fontSize,
      );
    }
  });

  testWidgets(
    'appearance persists independently without saving or losing form drafts',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'reading_appearance_',
      );
      final controller = _Controller(store: LocalStore(directory.path));
      addTearDown(() {
        controller.dispose();
        directory.deleteSync(recursive: true);
      });
      controller.store.save(controller.data);
      final originalEndpoint = controller.data.settings.endpoint;
      await tester.pumpWidget(ReadlaterApp(controller: controller));
      await tester.tap(find.text('设置').last);
      await tester.pumpAndSettle();
      final scrollable = find
          .descendant(
            of: find.byType(SettingsPage),
            matching: find.byType(Scrollable),
          )
          .first;
      final endpoint = find.widgetWithText(TextField, '服务地址');
      await tester.scrollUntilVisible(
        endpoint,
        400,
        scrollable: scrollable,
        maxScrolls: 30,
      );
      await tester.enterText(endpoint, 'https://draft.example.com/v1');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final compact = find.byKey(const ValueKey('appearance-compact'));
      await tester.scrollUntilVisible(
        compact,
        -400,
        scrollable: scrollable,
        maxScrolls: 30,
      );
      await Scrollable.ensureVisible(tester.element(compact), alignment: .5);
      await tester.pumpAndSettle();
      await tester.tap(compact);
      await tester.pumpAndSettle();
      expect(
        controller.store.load().settings.readingPreset,
        ReadingPreset.compact,
      );
      expect(controller.store.load().settings.endpoint, originalEndpoint);
      expect(
        Theme.of(tester.element(find.byType(SettingsPage)))
            .extension<ReadingLayout>()!
            .preset,
        ReadingPreset.compact,
      );
      await tester.scrollUntilVisible(
        endpoint,
        400,
        scrollable: scrollable,
        maxScrolls: 30,
      );
      expect(
        tester.widget<TextField>(endpoint).controller!.text,
        'https://draft.example.com/v1',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      controller.data = controller.store.load();
      await tester.pumpWidget(ReadlaterApp(controller: controller));
      expect(
        tester
            .widget<MaterialApp>(find.byType(MaterialApp))
            .theme!
            .extension<ReadingLayout>()!
            .preset,
        ReadingPreset.compact,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final preset in ReadingPreset.values) {
    for (final width in [320.0, 390.0, 430.0]) {
      testWidgets(
        'appearance options fit ${preset.name} width $width at 1.8x',
        (tester) async {
          final directory = Directory.systemTemp.createTempSync(
            'reading_options_',
          );
          final controller = _Controller(store: LocalStore(directory.path));
          controller.data.settings.readingPreset = preset;
          addTearDown(() {
            controller.dispose();
            directory.deleteSync(recursive: true);
          });
          tester.view.physicalSize = Size(width, 850);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: readlaterTheme(preset),
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 850),
                  textScaler: const TextScaler.linear(1.8),
                ),
                child: SettingsPage(
                  controller: controller,
                  data: controller.data,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('appearance-magazine')),
            250,
          );
          expect(tester.takeException(), isNull);
          final permission = find.text('系统通知权限：未知');
          await tester.scrollUntilVisible(permission, 250);
          expect(tester.getSize(permission).width, greaterThan(190));
          final request = find.widgetWithText(FilledButton, '请求权限');
          await tester.scrollUntilVisible(request, 150);
          expect(
            tester.getTopLeft(request).dy,
            greaterThan(tester.getBottomLeft(permission).dy),
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
