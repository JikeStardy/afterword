import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/app_controller.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/store.dart';
import 'package:readlater/services/intelligence_service.dart';

class QueueSecrets implements SecretStore {
  @override
  Future<String?> read(String key) async => 'fixture-key';
  @override
  Future<void> write(String key, String value) async {}
}

class BlockingAnalysis extends IntelligenceService {
  final entered = Completer<void>();
  final release = Completer<void>();
  int calls = 0;
  @override
  Future<Analysis> analyze(
    AppSettings settings,
    String key,
    LibraryItem item,
    List<LibraryItem> related, {
    List<String> imageDataUrls = const [],
  }) async {
    calls++;
    if (!entered.isCompleted) entered.complete();
    await release.future;
    return Analysis(summary: '已完成分析', sourceIds: [item.id]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'capture acknowledges durable input without waiting for model',
    () async {
      final directory = Directory.systemTemp.createTempSync('readlater-queue-');
      final ai = BlockingAnalysis();
      final controller = AppController(
        store: LocalStore(directory.path),
        intelligence: ai,
        secrets: QueueSecrets(),
      );
      await controller.initialize();
      await controller.saveSettings(AppSettings(textModel: 'fixture'));
      final saving = controller.captureText('在后台分析的原始资料', notes: '我的关注点');
      try {
        await ai.entered.future.timeout(const Duration(seconds: 2));
        final item = await saving.timeout(const Duration(milliseconds: 100));
        expect(item.analysis, isNull);
        expect(controller.store.load().items.single.body, '在后台分析的原始资料');
        await controller.updateNotes(item.id, '分析进行时编辑的笔记');
        ai.release.complete();
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (item.analysis == null && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(item.analysis?.summary, '已完成分析');
        expect(item.analysis?.stale, isTrue);
        expect(controller.store.load().items.single.notes, '分析进行时编辑的笔记');
      } finally {
        if (!ai.release.isCompleted) ai.release.complete();
        await saving;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        controller.dispose();
        directory.deleteSync(recursive: true);
      }
    },
  );
}
