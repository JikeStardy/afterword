import 'dart:io';

import 'package:flutter/material.dart' hide DiagnosticLevel;
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/app_controller.dart';
import 'package:readlater/core/diagnostics.dart';
import 'package:readlater/core/store.dart';
import 'package:readlater/platform/native_bridge.dart';
import 'package:readlater/ui/diagnostic_events_page.dart';

class _Secrets implements SecretStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _Native extends NativeBridge {
  @override
  Future<Map<String, Object?>> diagnosticEnvironment() async => {'os': 'test'};
}

void main() {
  testWidgets(
    'small large-text diagnostics page toggles DEBUG without model capture',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('diagnostic-ui');
      final controller = AppController(
        store: LocalStore(dir.path),
        secrets: _Secrets(),
        native: _Native(),
      );
      addTearDown(() {
        controller.dispose();
        dir.deleteSync(recursive: true);
      });
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: DiagnosticEventsPage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('日志级别：INFO'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(controller.diagnostics.level, DiagnosticLevel.debug);
      expect(controller.diagnostics.debugEnabled, isFalse);
      controller.diagnostics.log(
        DiagnosticLevel.debug,
        'rss',
        'request_started',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('生成诊断包'), 350);
      // Start file I/O in the real async zone, then wait for durable preview.
      await tester.runAsync(() async {
        await tester.tap(find.text('生成诊断包'));
        for (var i = 0; i < 100; i++) {
          if (File('${dir.path}/diagnostic-transfer/pending.json')
              .existsSync()) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(
          File('${dir.path}/diagnostic-transfer/pending.json').existsSync(),
          isTrue,
        );
      });
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('诊断包预览'), 250);
      expect(find.text('诊断包预览'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
