import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/app_controller.dart';
import 'package:readlater/core/store.dart';
import 'package:readlater/services/intelligence_service.dart';
import 'package:readlater/services/knowledge_service.dart';

class _Secrets implements SecretStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final legacyPayload = <String, dynamic>{
    'summary': 'Legacy summary',
    'highlights': [
      {
        'title': 'Legacy title',
        'explanation': 'Legacy explanation',
        'evidence': [
          {'sourceId': 'article', 'quote': 'Forged excerpt', 'page': 5},
        ],
      },
    ],
  };
  test('legacy highlights remain readable only for stored analyses', () async {
    expect(Analysis.fromJson(legacyPayload).structuredInsights, hasLength(1));
    final service = IntelligenceService(
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': jsonEncode(legacyPayload)},
              },
            ],
          }),
          200,
        ),
      ),
    );
    final analysis = await service.analyze(
      AppSettings(textModel: 'fixture'),
      'fixture-key',
      LibraryItem(
        id: 'article',
        title: 'Article',
        kind: ItemKind.text,
        body: 'Original',
      ),
      [],
      availableEvidence: [],
    );
    expect(analysis.structuredInsights, isEmpty);
  });
  test('cached final analyses cannot inject legacy highlights', () async {
    final directory = Directory.systemTemp.createTempSync(
      'readlater-legacy-cache-',
    );
    final store = LocalStore(directory.path);
    final settings = AppSettings(textModel: 'fixture');
    final item = LibraryItem(
      id: 'article',
      title: 'Long article',
      kind: ItemKind.text,
      body: List.filled(25000, 'x').join(),
    );
    store.saveWithRuntime(
      AppData(settings: settings, items: [item]),
      RuntimeState(
        jobs: [
          BackgroundJob(
            id: 'job',
            type: 'analysis',
            entityId: item.id,
            checkpoint: {
              'configuration': jsonEncode([
                settings.endpoint,
                settings.textModel,
                settings.visionModel,
                settings.searchEndpoint,
              ]),
              'textSections': [
                jsonEncode({'summary': 'First'}),
                jsonEncode({'summary': 'Second'}),
              ],
              'finalAnalysis': legacyPayload,
            },
          ),
        ],
      ),
    );
    var providerCalls = 0;
    final controller = AppController(
      store: store,
      secrets: _Secrets()..values['modelKey'] = 'fixture-key',
      intelligence: IntelligenceService(
        client: MockClient((request) async {
          providerCalls++;
          throw StateError('Cached analysis must not call provider');
        }),
      ),
    );
    addTearDown(() {
      controller.dispose();
      directory.deleteSync(recursive: true);
    });
    await controller.initialize();
    await controller.resumeTasks();
    await controller.waitForIdle();
    final restored = controller.data.items.single;
    expect(restored.status, 'ready', reason: restored.error);
    expect(providerCalls, 0);
    expect(restored.analysis!.structuredInsights, isEmpty);
  });
  final original = LibraryItem(
    id: 'article',
    title: 'Source',
    kind: ItemKind.text,
    body: 'The effect is now\u00a0 here.\nAnother line.',
  );
  test(
    'quotes accept equivalent whitespace while preserving word boundaries',
    () {
      KnowledgeService.validateEvidenceAnchor(
        {
          'sourceId': original.id,
          'blockId': 'body-1',
          'quote': 'The effect is now here. Another line.',
        },
        {original.id: original},
      );
      expect(
        () => KnowledgeService.validateEvidenceAnchor(
          {
            'sourceId': original.id,
            'blockId': 'body-1',
            'quote': 'The effect is nowhere.',
          },
          {original.id: original},
        ),
        throwsFormatException,
      );
    },
  );

  for (final kind in [ItemKind.text, ItemKind.pdf]) {
    test(
      '$kind aggregation reuses only previously collected evidence',
      () async {
        final proof = EvidenceAnchor(
          sourceId: original.id,
          sourceVersion: 2,
          blockId: kind == ItemKind.text ? 'body-7' : '',
          pdfPage: kind == ItemKind.pdf ? 5 : null,
          quote: 'Original source words',
        );
        final combined = LibraryItem(
          id: original.id,
          title: 'Intermediate analysis',
          kind: kind,
          body: 'Generated summary that is not original source text',
          pdfPageCount: kind == ItemKind.pdf ? 8 : null,
        );
        Map<String, dynamic>? requestBody;
        var returnedProof = proof.toJson();
        final service = IntelligenceService(
          client: MockClient((request) async {
            requestBody = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                'choices': [
                  {
                    'message': {
                      'content': jsonEncode({
                        'summary': 'Combined finding',
                        'structuredInsights': [
                          {
                            'id': 'finding',
                            'finding': 'Finding',
                            'change': 'Change',
                            'impact': 'Impact',
                            'evidence': [returnedProof],
                          },
                        ],
                      }),
                    },
                  },
                ],
              }),
              200,
            );
          }),
        );
        Future<Analysis> analyze() => service.analyze(
          AppSettings(textModel: 'fixture'),
          'fixture-key',
          combined,
          [],
          availableEvidence: [proof],
        );
        final result = await analyze();
        expect(
          result.structuredInsights.single.evidence.single.quote,
          proof.quote,
        );
        expect(jsonEncode(requestBody), contains('availableEvidence'));
        returnedProof = {
          ...proof.toJson(),
          'quote': combined.body,
          if (kind == ItemKind.text) 'blockId': 'body-1',
          if (kind == ItemKind.pdf) 'pdfPage': 1,
        };
        await expectLater(analyze(), throwsFormatException);
        returnedProof = {...proof.toJson(), 'unresolved': true};
        await expectLater(analyze(), throwsFormatException);
      },
    );
  }

  for (final forged in [false, true]) {
    test(
      'long text controller keeps original anchors (forged: $forged)',
      () async {
        final directory = Directory.systemTemp.createTempSync(
          'readlater-proof-',
        );
        late Map<String, dynamic> finalInput;
        final service = IntelligenceService(
          client: MockClient((request) async {
            final prompt =
                jsonDecode(request.body)['messages'][1]['content'] as String;
            final input =
                jsonDecode(prompt.split('输入数据：').last) as Map<String, dynamic>;
            final item = input['item'] as Map<String, dynamic>;
            final isFinal = (item['content'] as String).contains(
              'Generated summary',
            );
            Map<String, dynamic> anchor;
            if (isFinal) {
              finalInput = input;
              final collected = input['availableEvidence'] as List?;
              anchor = collected?.isNotEmpty == true
                  ? Map<String, dynamic>.from(collected!.last as Map)
                  : {
                      'sourceId': item['id'],
                      'blockId': 'body-1',
                      'quote': 'Generated summary',
                    };
              if (forged) anchor = {...anchor, 'quote': 'Generated summary'};
            } else {
              final block = (item['contentBlocks'] as List).first as Map;
              final text = block['text'] as String;
              anchor = {
                'sourceId': item['id'],
                'blockId': block['id'],
                'quote': text.startsWith('a') ? 'aaaa' : text,
              };
            }
            return http.Response(
              jsonEncode({
                'choices': [
                  {
                    'message': {
                      'content': jsonEncode({
                        'summary': 'Generated summary',
                        'structuredInsights': [
                          {
                            'id': 'proof',
                            'finding': 'Finding',
                            'change': 'Change',
                            'impact': 'Impact',
                            'evidence': [anchor],
                          },
                        ],
                      }),
                    },
                  },
                ],
              }),
              200,
            );
          }),
        );
        final controller = AppController(
          store: LocalStore(directory.path),
          secrets: _Secrets(),
          intelligence: service,
        );
        addTearDown(() {
          controller.dispose();
          directory.deleteSync(recursive: true);
        });
        await controller.initialize();
        final item = await controller.captureText(
          '${List.filled(24000, 'a').join()}\n\nOriginal source words',
        );
        await controller.waitForIdle();
        item.contentVersion = 3;
        await controller.saveSettings(
          AppSettings(textModel: 'fixture'),
          apiKey: 'fixture-key',
        );
        await controller.analyze(item.id);
        expect(finalInput['availableEvidence'], isNotEmpty);
        if (forged) {
          expect(item.status, 'error');
          expect(item.error, contains('只能复用'));
        } else {
          expect(item.status, 'ready', reason: item.error);
          final anchor =
              item.analysis!.structuredInsights.single.evidence.single;
          expect(anchor.blockId, 'body-2');
          expect(anchor.sourceVersion, 3);
          expect(anchor.unresolved, isFalse);
        }
      },
    );
  }
}
