import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:readlater/core/app_controller.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/store.dart';
import 'package:readlater/platform/native_bridge.dart';
import 'package:readlater/services/intelligence_service.dart';
import 'package:readlater/services/knowledge_service.dart';
import 'package:readlater/services/source_understanding_service.dart';

class UnusedIntelligence extends IntelligenceService {}

class _Secrets implements SecretStore {
  @override
  Future<String?> read(String key) async => key == 'modelKey' ? 'key' : null;
  @override
  Future<void> write(String key, String value) async {}
}

class _Native extends NativeBridge {
  final pdfCalls = <({int startPage, int maxPages})>[];
  @override
  Future<void> startBackgroundWork() async {}
  @override
  Future<void> stopBackgroundWork() async {}
  @override
  Future<void> updateBackgroundProgress({
    required String jobId,
    required String title,
    required String stage,
    int? completed,
    int? total,
  }) async {}
  @override
  Future<PdfPages> renderPdf(
    String path, {
    int startPage = 0,
    int maxPages = 4,
  }) async {
    pdfCalls.add((startPage: startPage, maxPages: maxPages));
    return PdfPages(
      pageCount: 5,
      images: startPage == 0
          ? const ['cGFnZTE=', 'cGFnZTI=', 'cGFnZTM=', 'cGFnZTQ=']
          : const ['cGFnZTU='],
    );
  }
}

class _FixtureServer {
  _FixtureServer({this.onSummarize});

  final Future<void> Function()? onSummarize;
  final summarizePrompts = <Json>[];
  final mergePrompts = <Json>[];
  final finalInputs = <Json>[];
  int summarizeCalls = 0, mergeCalls = 0, finalCalls = 0;
  bool _summarizeHookUsed = false;

  IntelligenceService service() => IntelligenceService(
    client: MockClient((request) async {
      final body = jsonDecode(request.body) as Json;
      final messages = body['messages'] as List;
      final user = messages.last as Json;
      final content = user['content'];
      final prompt = content is String
          ? content
          : ((content as List).first as Json)['text'] as String;
      final payload = _decodePrompt(prompt);
      Json response;
      if (payload['task'] == 'summarize_source_segment') {
        summarizeCalls++;
        summarizePrompts.add(payload);
        if (!_summarizeHookUsed && onSummarize != null) {
          _summarizeHookUsed = true;
          await onSummarize!();
        }
        response = {'summary': 'neutral summary $summarizeCalls'};
      } else if (payload['task'] == 'summarize_pdf_pages') {
        summarizeCalls++;
        summarizePrompts.add(payload);
        response = {'summary': 'pdf neutral summary $summarizeCalls'};
      } else if (payload['task'] == 'merge_source_segment_summaries') {
        mergeCalls++;
        mergePrompts.add(payload);
        response = {'summary': 'merged neutral summary $mergeCalls'};
      } else {
        finalCalls++;
        final input = _analysisInput(prompt);
        finalInputs.add(input);
        final evidence = (input['availableEvidence'] as List? ?? const []);
        response = {
          'brief': '最终导读',
          'summary': '最终分析',
          'insights': ['最终观点'],
          'structuredInsights': evidence.isEmpty
              ? [
                  {
                    'id': 'i-1',
                    'title': '最终观点',
                    'finding': '发现',
                    'change': '变化',
                    'impact': '影响',
                    'evidence': [
                      {
                        'sourceId': (input['item'] as Json)['id'],
                        'sourceVersion':
                            (input['item'] as Json)['contentVersion'],
                        'blockId': 'body-1',
                        'quote': '正文',
                      },
                    ],
                    'unknowns': <String>[],
                  },
                ]
              : [
                  {
                    'id': 'i-1',
                    'title': '最终观点',
                    'finding': '发现',
                    'change': '变化',
                    'impact': '影响',
                    'evidence': [evidence.first],
                    'unknowns': <String>[],
                  },
                ],
          'connections': <String>[],
          'questions': <String>[],
          'sourceIds': [(input['item'] as Json)['id']],
          'suggestedTopics': <String>[],
        };
      }
      return _jsonResponse({
        'choices': [
          {
            'message': {'content': jsonEncode(response)},
          },
        ],
      });
    }),
  );

  Json _decodePrompt(String prompt) {
    final trimmed = prompt.trimLeft();
    if (trimmed.startsWith('{')) return jsonDecode(trimmed) as Json;
    return <String, dynamic>{};
  }

  Json _analysisInput(String prompt) {
    final marker = '输入数据：';
    final index = prompt.indexOf(marker);
    if (index < 0) throw StateError('missing analysis input');
    return jsonDecode(prompt.substring(index + marker.length)) as Json;
  }

  http.Response _jsonResponse(Json body) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

String _longBody() {
  final first = '${'甲' * 1599}😀${'甲' * 15399}';
  final second = List.filled(9000, '乙').join();
  return '$first\n\n$second TAIL_SENTINEL';
}

Future<AppController> _controller(
  Directory directory,
  _FixtureServer server, {
  NativeBridge? native,
}) async {
  final controller = AppController(
    store: LocalStore(directory.path),
    intelligence: server.service(),
    native: native ?? _Native(),
    secrets: _Secrets(),
  );
  await controller.initialize();
  await controller.saveSettings(
    AppSettings(
      textModel: 'fixture-text',
      visionModel: 'fixture-vision',
      modelTextContextChars: 24000,
    ),
    apiKey: 'key',
  );
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  LibraryItem textSource() => LibraryItem(
    id: 'text-1',
    title: '长文',
    kind: ItemKind.text,
    contentVersion: 2,
    contentBlocks: [
      ContentBlock(
        id: 'body-1',
        kind: ContentBlockKind.paragraph,
        text: '证据窗口说明，长文需要先中立分段，再进入最终分析。',
      ),
    ],
  );

  LibraryItem pdfSource() => LibraryItem(
    id: 'pdf-1',
    title: 'PDF',
    kind: ItemKind.pdf,
    contentVersion: 3,
    pdfPageCount: 8,
    pdfPageStart: 2,
    pdfPageEnd: 6,
  );

  Json insightWith(EvidenceAnchor anchor) => {
    'finding': '发现',
    'change': '变化',
    'impact': '影响',
    'evidence': [anchor.toJson()],
  };

  test(
    'accepts unverified PDF visual anchors with real page and asset SHA',
    () {
      final sources = {'pdf-1': pdfSource()};

      expect(
        () => KnowledgeService.validateEvidenceAnchor({
          'sourceId': 'pdf-1',
          'sourceVersion': 3,
          'pdfPage': 3,
          'assetFingerprint': 'asset-sha',
          'unresolved': true,
        }, sources),
        returnsNormally,
      );
      expect(
        () => KnowledgeService.validateEvidenceAnchor({
          'sourceId': 'pdf-1',
          'sourceVersion': 3,
          'pdfPage': 3,
          'unresolved': true,
        }, sources),
        throwsFormatException,
      );
      expect(
        () => KnowledgeService.validateEvidenceAnchor({
          'sourceId': 'pdf-1',
          'sourceVersion': 3,
          'pdfPage': 7,
          'assetFingerprint': 'asset-sha',
          'unresolved': true,
        }, sources),
        throwsFormatException,
      );
    },
  );

  test('availableEvidence matching rejects mutated windowId and asset SHA', () {
    final textProof = EvidenceAnchor(
      sourceId: 'text-1',
      sourceVersion: 2,
      blockId: 'body-1',
      windowId: 'window-1',
      start: 0,
      end: 8,
      quote: '证据窗口说明',
    );
    final pdfProof = EvidenceAnchor(
      sourceId: 'pdf-1',
      sourceVersion: 3,
      pdfPage: 4,
      assetFingerprint: 'asset-sha',
      unresolved: true,
    );
    final sources = {'text-1': textSource(), 'pdf-1': pdfSource()};

    expect(
      () => KnowledgeService.validateStructuredInsights(
        [insightWith(textProof), insightWith(pdfProof)],
        sources,
        availableEvidence: [textProof, pdfProof],
      ),
      returnsNormally,
    );

    final mutatedWindow = EvidenceAnchor.fromJson(textProof.toJson())
      ..windowId = 'other-window';
    expect(
      () => KnowledgeService.validateStructuredInsights(
        [insightWith(mutatedWindow)],
        sources,
        availableEvidence: [textProof],
      ),
      throwsFormatException,
    );

    final mutatedAsset = EvidenceAnchor.fromJson(pdfProof.toJson())
      ..assetFingerprint = 'other-sha';
    expect(
      () => KnowledgeService.validateStructuredInsights(
        [insightWith(mutatedAsset)],
        sources,
        availableEvidence: [pdfProof],
      ),
      throwsFormatException,
    );
  });

  test('neutral summary cache keys include source title used by prompts', () {
    final service = SourceUnderstandingService(UnusedIntelligence());
    final base = textSource();
    final renamed = LibraryItem.fromJson(base.toJson())..title = '新标题';
    final windows = [
      SourceWindow(
        id: 'window-1',
        sourceId: 'text-1',
        sourceVersion: 2,
        blockId: 'body-1',
        start: 0,
        end: 8,
        text: '证据窗口说明',
        fingerprint: 'window-sha',
      ),
    ];

    final fingerprint = service.textFingerprint(base, windows);
    expect(fingerprint, hasLength(64));
    expect(service.textFingerprint(renamed, windows), isNot(fingerprint));
    expect(
      service.summaryId('text-1', 2, 0, 8, fingerprint),
      'text-1:2:0:8:${fingerprint.substring(0, 12)}',
    );
  });

  test(
    'text V2 covers full tail and reuses persisted neutral segment cache',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'readlater-source-cache-text-',
      );
      late AppController controller;
      final server = _FixtureServer();
      try {
        controller = await _controller(directory, server);
        final item = await controller.captureText(
          _longBody(),
          title: '超长正文',
          notes: 'PRIVATE_NOTES_SHOULD_NOT_ENTER_NEUTRAL_BATCH',
          analyzeAutomatically: false,
        );

        await controller.queueAnalysis(item.id);
        await controller.waitForIdle();

        expect(controller.data.items.single.status, 'ready');
        expect(controller.data.items.single.analysis?.summary, '最终分析');
        expect(server.summarizeCalls, greaterThan(1));
        expect(controller.data.segmentSummaries.length, server.summarizeCalls);
        final neutralWire = jsonEncode(server.summarizePrompts);
        expect(neutralWire, contains('TAIL_SENTINEL'));
        expect(neutralWire, contains('😀'));
        expect(neutralWire, contains('"blockId":"body-1"'));
        expect(neutralWire, contains('"blockId":"body-2"'));
        expect(
          neutralWire,
          isNot(contains('PRIVATE_NOTES_SHOULD_NOT_ENTER_NEUTRAL_BATCH')),
        );
        expect(neutralWire, isNot(contains('explicitInterests')));
        expect(neutralWire, isNot(contains('confirmedInterests')));
        expect(neutralWire, isNot(contains('PRIVATE_HISTORY_SENTINEL')));

        final summarizeAfterFirst = server.summarizeCalls;
        controller.data.items.single.notes = 'changed notes only';
        await controller.queueAnalysis(item.id);
        await controller.waitForIdle();

        expect(server.summarizeCalls, summarizeAfterFirst);
        expect(server.finalCalls, 2);
        expect(controller.data.segmentSummaries.length, summarizeAfterFirst);
      } finally {
        controller.dispose();
        directory.deleteSync(recursive: true);
      }
    },
  );

  test('late content version edit does not commit neutral cache', () async {
    final directory = Directory.systemTemp.createTempSync(
      'readlater-source-cache-cancel-',
    );
    late AppController controller;
    late _FixtureServer server;
    try {
      server = _FixtureServer(
        onSummarize: () async {
          controller.data.items.single.contentVersion++;
        },
      );
      controller = await _controller(directory, server);
      final item = await controller.captureText(
        _longBody(),
        title: '会变化的正文',
        analyzeAutomatically: false,
      );

      await controller.queueAnalysis(item.id);
      await controller.waitForIdle();

      expect(controller.data.segmentSummaries, isEmpty);
      expect(controller.data.items.single.analysis, isNull);
    } finally {
      controller.dispose();
      directory.deleteSync(recursive: true);
    }
  });

  test('PDF V2 batches rendered pages and retains unresolved page asset evidence', () async {
    final directory = Directory.systemTemp.createTempSync(
      'readlater-source-cache-pdf-',
    );
    late AppController controller;
    final server = _FixtureServer();
    final native = _Native();
    try {
      controller = await _controller(directory, server, native: native);
      final asset = await controller.store.writeAsset(
        Uint8List.fromList(utf8.encode('pdf bytes')),
        'fixture.pdf',
        'application/pdf',
      );
      controller.data.items.add(
        LibraryItem(
          id: 'pdf-1',
          title: 'PDF资料',
          kind: ItemKind.pdf,
          assets: [asset],
          contentVersion: 4,
          notes: 'PDF_PRIVATE_NOTES',
        ),
      );
      controller.store.saveWithRuntime(controller.data, controller.runtime);

      await controller.queueAnalysis('pdf-1');
      await controller.waitForIdle();

      expect(
        native.pdfCalls,
        [(startPage: 0, maxPages: 4), (startPage: 4, maxPages: 4)],
        reason:
            'status=${controller.data.items.single.status} error=${controller.data.items.single.error}',
      );
      expect(server.summarizeCalls, 2);
      expect(
        jsonEncode(server.summarizePrompts),
        isNot(contains('PDF_PRIVATE_NOTES')),
      );
      expect(
        jsonEncode(server.summarizePrompts),
        isNot(contains('availableEvidence')),
      );
      expect(
        server.summarizePrompts.first['source'],
        containsPair('firstPage', 1),
      );
      expect(
        server.summarizePrompts.first['source'],
        containsPair('lastPage', 4),
      );
      expect(
        server.summarizePrompts.last['source'],
        containsPair('firstPage', 5),
      );
      expect(
        server.summarizePrompts.last['source'],
        containsPair('lastPage', 5),
      );
      expect(server.finalInputs.single['availableEvidence'], isNotEmpty);

      final evidence = controller
          .data
          .items
          .single
          .analysis!
          .structuredInsights
          .single
          .evidence
          .single;
      expect(evidence.sourceId, 'pdf-1');
      expect(evidence.pdfPage, 1);
      expect(evidence.assetFingerprint, isNotEmpty);
      expect(evidence.unresolved, isTrue);
      expect(evidence.quote, isEmpty);
    } finally {
      controller.dispose();
      directory.deleteSync(recursive: true);
    }
  });
}
