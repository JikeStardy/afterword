import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/app_controller.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/retrieval.dart';
import 'package:readlater/core/store.dart';
import 'package:readlater/platform/native_bridge.dart';
import 'package:readlater/services/intelligence_service.dart';
import 'package:readlater/services/source_understanding_service.dart';

class _Secrets implements SecretStore {
  @override
  Future<String?> read(String key) async => key == 'modelKey' ? 'key' : null;

  @override
  Future<void> write(String key, String value) async {}
}

class _Native extends NativeBridge {
  @override
  Future<void> startBackgroundWork() async {}

  @override
  Future<void> stopBackgroundWork() async {}
}

class _ConversationIntelligence extends IntelligenceService {
  _ConversationIntelligence({this.blockFirstComplete = false});

  final bool blockFirstComplete;
  final entered = Completer<void>();
  final release = Completer<void>();
  final prompts = <Json>[];
  int completes = 0;

  @override
  Future<Json> complete(
    AppSettings settings,
    String key,
    String prompt, {
    List<String> imageDataUrls = const [],
    Future<void>? abortTrigger,
  }) async {
    completes++;
    prompts.add(_decodePrompt(prompt));
    if (blockFirstComplete && !entered.isCompleted) {
      entered.complete();
      await release.future;
    }
    return {
      'answer': '回答完成',
      'presentation': {'brief': '迟到的知识建议'},
      'evidence': const [],
      'remainingGaps': const [],
      'proposals': [
        {
          'title': '迟到主题',
          'question': '迟到问题',
          'presentation': {'brief': '不应写入的建议'},
          'reason': 'fixture',
        },
      ],
    };
  }

  @override
  Future<Analysis> analyze(
    AppSettings settings,
    String key,
    LibraryItem item,
    List<LibraryItem> related, {
    List<String> imageDataUrls = const [],
    List<EvidenceAnchor>? availableEvidence,
  }) async => Analysis(summary: '补充正文后的分析', sourceIds: [item.id]);

  Json _decodePrompt(String prompt) {
    final marker = '输入数据：';
    final index = prompt.indexOf(marker);
    if (index < 0) return {};
    return jsonDecode(prompt.substring(index + marker.length)) as Json;
  }
}

Future<AppController> _controller(
  Directory directory,
  _ConversationIntelligence intelligence,
) async {
  final controller = AppController(
    store: LocalStore(directory.path),
    intelligence: intelligence,
    native: _Native(),
    secrets: _Secrets(),
  );
  await controller.initialize();
  await controller.saveSettings(
    AppSettings(
      textModel: 'fixture-text',
      visionModel: 'fixture-vision',
      conversationCallLimit: 3,
      modelTextContextChars: 16000,
    ),
    apiKey: 'key',
  );
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('settings round trip keeps reader scale with dialogue budgets', () {
    final settings = AppSettings(
      readerFontScale: 1.35,
      conversationCallLimit: 7,
      modelTextContextChars: 32000,
    );

    final restored = AppSettings.fromJson(settings.toJson());

    expect(restored.readerFontScale, 1.35);
    expect(restored.conversationCallLimit, 7);
    expect(restored.modelTextContextChars, 32000);
  });

  test('old settings snapshots receive dialogue budget defaults', () {
    final restored = AppSettings.fromJson({
      'readerFontScale': 1.2,
      'readingPreset': 'magazine',
    });

    expect(restored.readerFontScale, 1.2);
    expect(restored.conversationCallLimit, 5);
    expect(restored.modelTextContextChars, 24000);
  });

  test('invalid dialogue budgets are rejected during settings restore', () {
    expect(
      () => AppSettings.fromJson({'conversationCallLimit': 0}),
      throwsArgumentError,
    );
    expect(
      () => AppSettings.fromJson({'modelTextContextChars': 7999}),
      throwsArgumentError,
    );
  });

  test(
    'conversation prompt skips neutral summaries from replaced source versions',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'readlater-branch-consolidation-cache-',
      );
      final intelligence = _ConversationIntelligence();
      late AppController controller;
      try {
        controller = await _controller(directory, intelligence);
        final item = LibraryItem(
          id: 'web-1',
          title: '旧文章',
          kind: ItemKind.web,
          url: 'https://example.com/article',
          body: '旧正文用于中立缓存',
          bodyOrigin: 'pasted',
          contentBlocks: [
            ContentBlock(
              id: 'body-1',
              kind: ContentBlockKind.paragraph,
              text: '旧正文用于中立缓存',
            ),
          ],
          status: 'saved',
        );
        controller.data.items.add(item);
        final window = readSourceWindow(item, 'body-1', 0, item.body.length);
        final fingerprint = SourceUnderstandingService(intelligence)
            .textFingerprint(item, [window]);
        controller.data.segmentSummaries.add(
          SourceSegmentSummary(
            id: 'old-summary',
            sourceId: item.id,
            sourceVersion: 1,
            rangeStart: 0,
            rangeEnd: item.body.length,
            fingerprint: fingerprint,
            promptVersion: SourceUnderstandingService.promptVersion,
            summary: 'OLD_NEUTRAL_CACHE_SHOULD_NOT_REAPPEAR',
            evidence: [
              EvidenceAnchor(
                sourceId: item.id,
                sourceVersion: 1,
                blockId: 'body-1',
                start: 0,
                end: item.body.length,
                quote: '旧正文用于中立缓存',
              ),
            ],
          ),
        );
        controller.store.saveWithRuntime(controller.data, controller.runtime);

        await controller.supplementWebArticle(item.id, body: '新版正文用于当前会话');
        final conversationId = await controller.startConversation(
          ConversationScope.item,
          scopeId: item.id,
        );
        await controller.submitQuestion(conversationId, '当前正文是什么？');
        await controller.waitForIdle();

        final promptWire = jsonEncode(intelligence.prompts);
        expect(promptWire, contains('新版正文用于当前会话'));
        expect(
          promptWire,
          isNot(contains('OLD_NEUTRAL_CACHE_SHOULD_NOT_REAPPEAR')),
        );
      } finally {
        if (!intelligence.release.isCompleted) intelligence.release.complete();
        controller.dispose();
        directory.deleteSync(recursive: true);
      }
    },
  );

  test(
    'late conversation answer cannot write knowledge after source replacement',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'readlater-branch-consolidation-late-',
      );
      final intelligence = _ConversationIntelligence(blockFirstComplete: true);
      late AppController controller;
      try {
        controller = await _controller(directory, intelligence);
        final item = LibraryItem(
          id: 'web-1',
          title: '网页',
          kind: ItemKind.web,
          url: 'https://example.com/article',
          body: '旧正文',
          bodyOrigin: 'pasted',
          contentBlocks: [
            ContentBlock(
              id: 'body-1',
              kind: ContentBlockKind.paragraph,
              text: '旧正文',
            ),
          ],
          status: 'saved',
        );
        controller.data.items.add(item);
        controller.store.saveWithRuntime(controller.data, controller.runtime);
        final conversationId = await controller.startConversation(
          ConversationScope.item,
          scopeId: item.id,
        );

        await controller.submitQuestion(conversationId, '生成知识建议');
        await intelligence.entered.future.timeout(const Duration(seconds: 2));
        await controller.supplementWebArticle(item.id, body: '新版正文');
        intelligence.release.complete();
        await controller.waitForIdle();

        expect(controller.data.knowledgeProposals, isEmpty);
      } finally {
        if (!intelligence.release.isCompleted) intelligence.release.complete();
        controller.dispose();
        directory.deleteSync(recursive: true);
      }
    },
  );

  test(
    'cancelling a conversation turn leaves background capture queued',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'readlater-branch-consolidation-cancel-',
      );
      final intelligence = _ConversationIntelligence();
      late AppController controller;
      try {
        controller = await _controller(directory, intelligence);
        controller.data.conversationTurns.add(
          ConversationTurn(
            id: 'turn-1',
            conversationId: 'conversation-1',
            question: '问题',
            status: 'queued',
          ),
        );
        controller.runtime.jobs.addAll([
          BackgroundJob(
            id: 'conversation-job',
            type: 'conversation',
            entityId: 'turn-1',
            lane: 'interactive',
          ),
          BackgroundJob(
            id: 'capture-job',
            type: 'capture',
            entityId: 'web-1',
            lane: 'background',
          ),
        ]);
        controller.store.saveWithRuntime(controller.data, controller.runtime);

        await controller.cancelTurn('turn-1');

        expect(
          controller.runtime.jobs
              .singleWhere((job) => job.id == 'conversation-job')
              .status,
          'cancelled',
        );
        expect(
          controller.runtime.jobs
              .singleWhere((job) => job.id == 'capture-job')
              .status,
          'queued',
        );
      } finally {
        if (!intelligence.release.isCompleted) intelligence.release.complete();
        controller.dispose();
        directory.deleteSync(recursive: true);
      }
    },
  );
}
