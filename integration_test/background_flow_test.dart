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
import 'package:readlater/services/intelligence_service.dart';

// Keep the deterministic provider stage pending long enough for adb HOME/lock.
// This delay is test-only; the real HTTP and PDF platform paths are retained.
class DelayedFixtureIntelligence extends IntelligenceService {
  @override
  Future<Analysis> analyze(
    AppSettings settings,
    String key,
    LibraryItem item,
    List<LibraryItem> related, {
    List<String> imageDataUrls = const [],
  }) async {
    await Future<void>.delayed(const Duration(seconds: 15));
    return super.analyze(
      settings,
      key,
      item,
      related,
      imageDataUrls: imageDataUrls,
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const fixtureBase = String.fromEnvironment(
    'READLATER_FIXTURE_BASE',
    defaultValue: 'http://127.0.0.1:18765',
  );

  testWidgets('Android background service completes long text and PDF work', (
    tester,
  ) async {
    final support = await getApplicationSupportDirectory();
    final runDirectory = await Directory(
      '${support.path}/v3-background-${DateTime.now().microsecondsSinceEpoch}',
    ).create(recursive: true);
    final marker = File('${runDirectory.path}/background-flow-marker.json');

    Future<void> mark(String stage, {String entityId = ''}) async {
      final payload = {
        'stage': stage,
        'entityId': entityId,
        'path': marker.path,
        'time': DateTime.now().toIso8601String(),
      };
      await marker.writeAsString(jsonEncode(payload), flush: true);
      debugPrint('READLATER_V3_BACKGROUND_FLOW ${jsonEncode(payload)}');
    }

    final controller = AppController(
      store: LocalStore(runDirectory.path),
      intelligence: DelayedFixtureIntelligence(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.saveSettings(
      AppSettings(
        endpoint: '$fixtureBase/v1',
        textModel: 'fixture-text',
        visionModel: 'fixture-vision',
        searchEndpoint: '$fixtureBase/search',
      ),
      apiKey: 'fixture-key',
      searchKey: 'fixture-key',
    );

    await tester.pumpWidget(ReadlaterApp(controller: controller));
    await tester.pumpAndSettle();

    final longText = List.filled(
      2600,
      '后台服务验收资料：长文分段保存、后台继续处理、完成后恢复状态。',
    ).join('\n');
    final longItem = await controller.captureText(longText, notes: '长文后台验收');
    expect(longItem.analysis, isNull);
    expect(
      controller.store.load().items.any((item) => item.id == longItem.id),
      isTrue,
    );
    await mark('long-submitted', entityId: longItem.id);
    await Future<void>.delayed(const Duration(seconds: 20));
    expect(
      WidgetsBinding.instance.lifecycleState,
      isNot(AppLifecycleState.resumed),
      reason: 'External adb coordination must background/lock while the provider is pending.',
    );
    await controller.waitForIdle().timeout(const Duration(minutes: 4));
    expect(longItem.status, 'ready');
    expect(longItem.analysis?.summary.trim(), isNotEmpty);
    await mark('long-complete', entityId: longItem.id);
    final foregroundDeadline = DateTime.now().add(const Duration(minutes: 3));
    while (WidgetsBinding.instance.lifecycleState !=
            AppLifecycleState.resumed &&
        DateTime.now().isBefore(foregroundDeadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    expect(WidgetsBinding.instance.lifecycleState, AppLifecycleState.resumed);

    final pdfBytes = (await http.get(Uri.parse('$fixtureBase/sample.pdf')))
        .bodyBytes;
    expect(pdfBytes, isNotEmpty);
    final pdf = await File('${runDirectory.path}/fixture.pdf')
        .writeAsBytes(pdfBytes, flush: true);
    final pdfItem = await controller.importFile(pdf.path);
    await mark('pdf-submitted', entityId: pdfItem.id);
    await Future<void>.delayed(const Duration(seconds: 20));
    expect(
      WidgetsBinding.instance.lifecycleState,
      isNot(AppLifecycleState.resumed),
      reason: 'External adb coordination must also background/lock PDF work.',
    );
    await controller.waitForIdle().timeout(const Duration(minutes: 4));
    expect(pdfItem.status, 'ready');
    expect(pdfItem.analysis?.summary.trim(), isNotEmpty);
    await mark('pdf-complete', entityId: pdfItem.id);
    expect(
      controller.runtime.jobs.every((job) => job.status == 'complete'),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
