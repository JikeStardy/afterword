import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/app_controller.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/store.dart';
import 'package:readlater/platform/native_bridge.dart';
import 'package:readlater/services/intelligence_service.dart';

class RecoverySecrets implements SecretStore {
  int reads = 0;
  @override
  Future<String?> read(String key) async {
    reads++;
    return 'fixture';
  }

  @override
  Future<void> write(String key, String value) async {}
}

class RecoveryNative extends NativeBridge {
  int started = 0, finishedDigests = 0;
  bool allowed = true;
  final notices = <String>[];
  @override
  Future<void> startBackgroundWork() async {
    started++;
  }

  @override
  Future<void> finishDigest() async {
    finishedDigests++;
  }

  @override
  Future<bool> publishNotification({
    required String id,
    required String channel,
    required String title,
    required String body,
    String? entityType,
    String? entityId,
  }) async {
    if (allowed) notices.add(id);
    return allowed;
  }
}

class SegmentedIntelligence extends IntelligenceService {
  int calls = 0;
  final entered = Completer<void>();
  final release = Completer<void>();
  bool blockSecond = false;
  @override
  Future<Analysis> analyze(
    AppSettings settings,
    String key,
    LibraryItem item,
    List<LibraryItem> related, {
    List<String> imageDataUrls = const [],
    List<EvidenceAnchor>? availableEvidence,
  }) async {
    calls++;
    if (blockSecond && calls == 2) {
      entered.complete();
      await release.future;
    }
    return Analysis(summary: '片段 $calls', sourceIds: [item.id]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'digest-only cold start never reads secrets or executes queued work',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'readlater-digest-',
      );
      final store = LocalStore(directory.path);
      final native = RecoveryNative(), secrets = RecoverySecrets();
      store.saveWithRuntime(
        AppData(
          items: [LibraryItem(id: 'a', title: '本地候选', kind: ItemKind.text)],
          topics: [Topic(id: 't', title: '追踪', question: '问题', tracking: true)],
        ),
        RuntimeState(
          jobs: [BackgroundJob(id: 'job', type: 'analysis', entityId: 'a')],
        ),
      );
      final controller = AppController(
        store: store,
        native: native,
        secrets: secrets,
      );
      try {
        await controller.initialize(digestOnly: true);
        await controller.resume();
        await controller.sendDailyDigest();
        await controller.sendDailyDigest();
        expect(secrets.reads, 0);
        expect(native.started, 0);
        expect(native.notices.length, 1);
        expect(controller.runtime.jobs.single.status, 'queued');
        expect(native.finishedDigests, 2);
      } finally {
        controller.dispose();
        directory.deleteSync(recursive: true);
      }
    },
  );

  test('notification replay drops old digests and disabled channels', () async {
    final directory = Directory.systemTemp.createTempSync('readlater-outbox-');
    final store = LocalStore(directory.path);
    final native = RecoveryNative();
    store.saveWithRuntime(
      AppData(
        settings: AppSettings(researchNotifications: false),
        items: [LibraryItem(id: 'a', title: '结果', kind: ItemKind.text)],
      ),
      RuntimeState(
        outbox: [
          PendingNotification(
            id: 'digest:2000-01-01',
            channel: 'digest',
            title: '过期',
            body: '',
            entityType: 'today',
          ),
          PendingNotification(
            id: 'research:old',
            channel: 'research',
            title: '已关闭',
            body: '',
          ),
          PendingNotification(
            id: 'result:current',
            channel: 'results',
            title: '结果',
            body: '',
            entityType: 'item',
            entityId: 'a',
          ),
        ],
      ),
    );
    final controller = AppController(
      store: store,
      native: native,
      secrets: RecoverySecrets(),
    );
    try {
      await controller.initialize();
      await controller.resumeTasks();
      expect(native.notices, ['result:current']);
      expect(controller.runtime.outbox, hasLength(1));
      await controller.resumeTasks();
      expect(native.notices, hasLength(1));
    } finally {
      controller.dispose();
      directory.deleteSync(recursive: true);
    }
  });

  test('queued tasks validate configuration and task version before provider calls', () async {
    final directory = Directory.systemTemp.createTempSync(
      'readlater-preflight-',
    );
    final ai = SegmentedIntelligence();
    final controller = AppController(
      store: LocalStore(directory.path),
      intelligence: ai,
      secrets: RecoverySecrets(),
    );
    try {
      await controller.initialize();
      controller.data.items.add(
        LibraryItem(id: 'a', title: '资料', kind: ItemKind.text),
      );
      controller.runtime.jobs.addAll([
        BackgroundJob(
          id: 'changed',
          type: 'analysis',
          entityId: 'a',
          checkpoint: {'configuration': 'old-provider'},
        ),
        BackgroundJob(
          id: 'future',
          type: 'analysis',
          entityId: 'a',
          version: 999,
        ),
        BackgroundJob(id: 'unknown', type: 'future-action', entityId: 'a'),
      ]);
      await controller.resumeTasks();
      await controller.waitForIdle();
      expect(ai.calls, 0);
      expect(
        controller.runtime.jobs.every((job) => job.status == 'paused'),
        isTrue,
      );
      expect(
        controller.runtime.jobs.every(
          (job) => job.checkpoint['requiresAttention'] == true,
        ),
        isTrue,
      );
      expect(
        () => RuntimeState.fromJson({'version': 999}),
        throwsFormatException,
      );
    } finally {
      controller.dispose();
      directory.deleteSync(recursive: true);
    }
  });

  test('interrupted long text reuses saved chunks and cancelled jobs stay cancelled', () async {
    final directory = Directory.systemTemp.createTempSync(
      'readlater-recovery-',
    );
    final firstAi = SegmentedIntelligence()..blockSecond = true;
    var controller = AppController(
      store: LocalStore(directory.path),
      intelligence: firstAi,
      secrets: RecoverySecrets(),
    );
    await controller.initialize();
    await controller.saveSettings(AppSettings(textModel: 'fixture'));
    final item = await controller.captureText(List.filled(48001, '文').join());
    await firstAi.entered.future.timeout(const Duration(seconds: 3));
    expect(
      controller.runtime.jobs.single.checkpoint['textSections'],
      hasLength(1),
    );
    controller.dispose();
    firstAi.release.complete();
    await controller.waitForIdle();
    final resumedAi = SegmentedIntelligence();
    final native = RecoveryNative();
    controller = AppController(
      store: LocalStore(directory.path),
      intelligence: resumedAi,
      secrets: RecoverySecrets(),
      native: native,
    );
    try {
      await controller.initialize();
      await controller.resumeTasks();
      await controller.waitForIdle();
      expect(
        resumedAi.calls,
        3,
        reason: 'Only unfinished chunks and final synthesis should run.',
      );
      expect(controller.data.items.single.id, item.id);
      expect(controller.data.items.single.status, 'ready');
      expect(controller.runtime.jobs.single.status, 'complete');
      expect(controller.data.notices.join(), contains('费用'));
      expect(native.notices, hasLength(1));
      await controller.resumeTasks();
      await controller.waitForIdle();
      expect(resumedAi.calls, 3);
      expect(native.notices, hasLength(1));
      controller.runtime.jobs.add(
        BackgroundJob(
          id: 'cancelled',
          type: 'analysis',
          entityId: item.id,
          status: 'cancelled',
        ),
      );
      await controller.resumeTasks();
      expect(controller.runtime.jobs.last.status, 'cancelled');
    } finally {
      controller.dispose();
      directory.deleteSync(recursive: true);
    }
  });
}
