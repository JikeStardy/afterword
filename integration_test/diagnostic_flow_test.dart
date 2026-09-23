import 'dart:io';

import 'package:flutter/material.dart' hide DiagnosticLevel;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:readlater/core/app_controller.dart';
import 'package:readlater/core/diagnostic_controller.dart';
import 'package:readlater/core/diagnostics.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/store.dart';
import 'package:readlater/services/diagnostic_transfer.dart';
import 'package:readlater/ui/diagnostic_events_page.dart';
import 'package:readlater/ui/common.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const restart = bool.fromEnvironment('DIAGNOSTIC_RESTART_VERIFY');
  testWidgets(
    restart
        ? 'process restart resets INFO and preserves reports/config'
        : 'DEBUG RSS failure bundle and authenticated local upload',
    (tester) async {
      final support = await getApplicationSupportDirectory();
      final root = Directory('${support.path}/diagnostic-device-flow');
      if (!restart && await root.exists()) await root.delete(recursive: true);
      final controller = AppController(store: LocalStore(root.path));
      await controller.initialize();
      expect(controller.diagnostics.level, DiagnosticLevel.info);
      if (restart) {
        expect(controller.diagnostics.latestDebugSessionId, isNotNull);
        expect(
          controller.diagnostics.events.any(
            (event) => event.level == DiagnosticLevel.debug,
          ),
          isTrue,
        );
        expect(
          (await controller.loadDiagnosticUploadConfig()).endpoint,
          'http://127.0.0.1:18766/diagnostics',
        );
        expect(await controller.pendingDiagnosticBundle(), isNotNull);
      } else {
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: readlaterTheme(),
            home: DiagnosticEventsPage(controller: controller),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        expect(controller.diagnostics.level, DiagnosticLevel.debug);
        expect(controller.diagnostics.debugEnabled, isFalse);
        controller.setForeground(false);
        controller.setForeground(true);
        expect(controller.diagnostics.level, DiagnosticLevel.debug);
        await controller.addFeed('http://127.0.0.1:18765/feed');
        controller.data.feeds.add(
          Feed(
            id: 'failure-feed',
            url: 'http://127.0.0.1:18765/unavailable?aihot_actor=must-not-export',
            title: 'failed feed',
          ),
        );
        await controller.refreshFeeds();
        expect(
          controller.data.feeds.where((feed) => feed.error.isNotEmpty),
          hasLength(1),
        );
        expect(
          controller.diagnostics.tasks.any((task) => task.status == 'failed'),
          isTrue,
        );
        final env = await controller.native.diagnosticEnvironment();
        expect(env['platform'], 'android');
        expect(env['networkType'], isNotNull);
        await controller.saveDiagnosticUploadConfig(
          'http://127.0.0.1:18766/diagnostics',
          'device-test-token',
        );
        final bundle = await controller.prepareDiagnosticBundle(
          DiagnosticSelection(sessionId: controller.diagnostics.sessionId),
        );
        expect(bundle.eventCount, greaterThan(0));
        await controller.uploadDiagnosticBundle(bundle);
        // Reopen to exercise persistent configuration and immutable local preview.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: readlaterTheme(),
          home: DiagnosticEventsPage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await binding.takeScreenshot(
        restart ? 'diagnostics-info-controls' : 'diagnostics-debug-controls',
      );
      await tester.ensureVisible(find.text('生成诊断包'));
      await tester.pumpAndSettle();
      await binding.takeScreenshot(
        restart ? 'diagnostics-restart-info' : 'diagnostics-debug-preview',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      controller.dispose();
    },
  );
}
