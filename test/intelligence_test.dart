import 'dart:async';
import 'dart:convert';

import 'package:readlater/core/diagnostics.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/services/intelligence_service.dart';

http.Response completion(Map<String, dynamic> result) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'content': jsonEncode(result)},
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void main() {
  test('analysis sends explicit and inferred preferences separately and removes nonexistent sources', () async {
    Map<String, dynamic>? body;
    final service = IntelligenceService(
      client: MockClient((request) async {
        expect(request.url.path, '/v1/chat/completions');
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return completion({
          'summary': '有条件有效',
          'insights': ['观点 [a]'],
          'sourceIds': ['a', 'invented'],
        });
      }),
    );
    final result = await service.analyze(
      AppSettings(
        textModel: 'configured',
        explicitInterests: ['适用条件'],
        inferredInterests: ['笔记'],
      ),
      'test-key',
      LibraryItem(
        id: 'a',
        title: '文章',
        kind: ItemKind.text,
        body: '内容',
        readCount: 3,
        researchAdoptions: 1,
        feedback: -1,
      ),
      [],
    );
    expect(result.sourceIds, ['a']);
    expect(result.summary, '有条件有效');
    expect(jsonEncode(body), contains('适用条件'));
    expect(jsonEncode(body), contains('不是认同'));
    expect(body!.containsKey('tools'), isFalse);
    final prompt = body!['messages'][1]['content'] as String;
    final input =
        jsonDecode(prompt.split('输入数据：').last) as Map<String, dynamic>;
    expect(input['item']['attentionNotAgreement'], {
      'reads': 3,
      'researchAdoptions': 1,
    });
    expect(input['item']['feedback'], -1);
  });
  test('analysis prompt includes structured content and validates evidence anchors', () async {
    Map<String, dynamic>? body;
    final service = IntelligenceService(
      client: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return completion({
          'summary': '结构化认识 [a]',
          'insights': ['结构化内容可定位 [a]'],
          'structuredInsights': [
            {
              'id': 's1',
              'finding': '发现',
              'change': '补充旧认识',
              'impact': '影响复查安排',
              'evidence': [
                {
                  'sourceId': 'a',
                  'sourceVersion': 1,
                  'blockId': 'body-1',
                  'quote': '第一段证据',
                },
              ],
              'unknowns': ['长期效果'],
              'verdict': 'new',
            },
          ],
          'sourceIds': ['a'],
        });
      }),
    );

    final result = await service.analyze(
      AppSettings(textModel: 'm'),
      'key',
      LibraryItem(
        id: 'a',
        title: '文章',
        kind: ItemKind.text,
        body: '第一段证据\n\n第二段',
        notes: '我的判断',
      ),
      [],
    );

    expect(result.summary, '结构化认识 [a]');
    final prompt = body!['messages'][1]['content'] as String;
    final input =
        jsonDecode(prompt.split('输入数据：').last) as Map<String, dynamic>;
    expect(input['item']['contentBlocks'].first['id'], 'body-1');
    expect(input['item']['notes'], '我的判断');
    expect(prompt, contains('structuredInsights'));
  });

  test('analysis rejects fabricated structured evidence anchors', () async {
    final service = IntelligenceService(
      client: MockClient(
        (_) async => completion({
          'summary': '认识',
          'structuredInsights': [
            {
              'id': 'pdf-anchor',
              'finding': '发现',
              'change': '改变',
              'impact': '影响',
              'evidence': [
                {
                  'sourceId': 'a',
                  'sourceVersion': 1,
                  'blockId': 'missing',
                  'quote': '不存在',
                },
              ],
            },
          ],
          'sourceIds': ['a'],
        }),
      ),
    );

    await expectLater(
      service.analyze(
        AppSettings(textModel: 'm'),
        'key',
        LibraryItem(id: 'a', title: '文章', kind: ItemKind.text, body: '正文'),
        [],
      ),
      throwsFormatException,
    );
  });

  test('unresolved structured evidence must retain the quote', () async {
    final service = IntelligenceService(
      client: MockClient(
        (_) async => completion({
          'summary': '认识',
          'structuredInsights': [
            {
              'id': 'pdf-anchor',
              'finding': '发现',
              'change': '改变',
              'impact': '影响',
              'evidence': [
                {'sourceId': 'a', 'unresolved': true},
              ],
            },
          ],
          'sourceIds': ['a'],
        }),
      ),
    );

    await expectLater(
      service.analyze(
        AppSettings(textModel: 'm'),
        'key',
        LibraryItem(id: 'a', title: '文章', kind: ItemKind.text, body: '正文'),
        [],
      ),
      throwsFormatException,
    );
  });
  test('pdf page evidence is accepted only for pdf sources', () async {
    final service = IntelligenceService(
      client: MockClient(
        (_) async => completion({
          'summary': '认识',
          'structuredInsights': [
            {
              'id': 'pdf-anchor',
              'finding': '发现',
              'change': '改变',
              'impact': '影响',
              'evidence': [
                {'sourceId': 'a', 'sourceVersion': 1, 'pdfPage': 3},
              ],
            },
          ],
          'sourceIds': ['a'],
        }),
      ),
    );

    await expectLater(
      service.analyze(
        AppSettings(textModel: 'm'),
        'key',
        LibraryItem(id: 'a', title: '文章', kind: ItemKind.text, body: '正文'),
        [],
      ),
      throwsFormatException,
    );

    final result = await service.analyze(
      AppSettings(textModel: 'm'),
      'key',
      LibraryItem(
        id: 'a',
        title: 'PDF',
        kind: ItemKind.pdf,
        body: '正文',
        pdfPageCount: 3,
      ),
      [],
    );
    expect(result.structuredInsights.single.evidence.single.pdfPage, 3);
    await expectLater(
      service.analyze(
        AppSettings(textModel: 'm'),
        'key',
        LibraryItem(id: 'a', title: 'PDF', kind: ItemKind.pdf, pdfPageCount: 2),
        [],
      ),
      throwsFormatException,
    );
  });
  test(
    'multimodal analysis uses configured vision model and image blocks',
    () async {
      final service = IntelligenceService(
        client: MockClient((r) async {
          final body = jsonDecode(r.body) as Map<String, dynamic>;
          expect(body['model'], 'vision');
          expect(jsonEncode(body), contains('data:image/png;base64,YQ=='));
          return completion({
            'summary': '图表含义',
            'sourceIds': ['a'],
          });
        }),
      );
      final result = await service.analyze(
        AppSettings(textModel: 'text', visionModel: 'vision'),
        'key',
        LibraryItem(id: 'a', title: '图', kind: ItemKind.image),
        [],
        imageDataUrls: ['data:image/png;base64,YQ=='],
      );
      expect(result.summary, '图表含义');
    },
  );
  test('research authorization denial causes zero outbound requests', () async {
    var requests = 0;
    final service = IntelligenceService(
      client: MockClient((r) async {
        requests++;
        return completion({});
      }),
    );
    final run = ResearchRun(id: 'r', goal: '问题');
    await expectLater(
      service.research(
        AppSettings(textModel: 'm'),
        'key',
        'search',
        run,
        authorized: () => false,
        onProgress: () async {},
      ),
      throwsStateError,
    );
    expect(requests, 0);
  });
  test(
    'research iterates within exact call budget and preserves fetched evidence',
    () async {
      var requests = 0;
      final service = IntelligenceService(
        client: MockClient((r) async {
          requests++;
          if (r.url.path == '/search') {
            return http.Response(
              jsonEncode({
                'results': [
                  {
                    'title': '原始依据',
                    'url': 'https://example.com/proof',
                    'content': '实际证据',
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return completion({
            'report': '认识 [S1]',
            'nextQuery': '查证适用条件',
            'meaningful': true,
          });
        }),
      );
      final run = ResearchRun(id: 'r', goal: '笔记方法', callLimit: 4);
      await service.research(
        AppSettings(textModel: 'm'),
        'key',
        'search',
        run,
        authorized: () => true,
        onProgress: () async {},
      );
      expect(requests, 4);
      expect(run.calls, 4);
      expect(run.sources.single.url, 'https://example.com/proof');
      expect(run.report, contains('S1'));
      expect(run.status, 'budget');
    },
  );
  test(
    'research resumes after a completed search without repeating it',
    () async {
      var searchRequests = 0, modelRequests = 0;
      final service = IntelligenceService(
        client: MockClient((request) async {
          if (request.url.path == '/search') {
            searchRequests++;
            return http.Response(jsonEncode({'results': []}), 200);
          }
          modelRequests++;
          return completion({
            'report': '恢复比较 [S1]',
            'nextQuery': '',
            'meaningful': true,
          });
        }),
      );
      final run = ResearchRun(
        id: 'r',
        goal: '问题',
        callLimit: 2,
        calls: 1,
        steps: ['检索：问题', '检索完成：问题'],
        sources: [
          ResearchSource(
            id: 'S1',
            title: '已有来源',
            url: 'https://example.com/a',
            snippet: '证据',
          ),
        ],
      );

      await service.research(
        AppSettings(textModel: 'm'),
        'key',
        'search',
        run,
        authorized: () => true,
        onProgress: () async {},
      );

      expect(searchRequests, 0);
      expect(modelRequests, 1);
      expect(run.calls, 2);
      expect(run.status, 'complete');
      expect(run.report, contains('S1'));
    },
  );
  test(
    'research resumes a saved report without repeating provider calls',
    () async {
      var requests = 0;
      final service = IntelligenceService(
        client: MockClient((request) async {
          requests++;
          if (request.url.path == '/search') {
            return http.Response(jsonEncode({'results': []}), 200);
          }
          return completion({
            'report': '不应再次生成 [S1]',
            'nextQuery': '',
            'meaningful': true,
          });
        }),
      );
      final run = ResearchRun(
        id: 'r',
        goal: '问题',
        callLimit: 4,
        calls: 2,
        report: '已保存报告 [S1]',
        steps: ['检索：问题', '检索完成：问题', '比较证据并检查研究缺口'],
        sources: [
          ResearchSource(
            id: 'S1',
            title: '已有来源',
            url: 'https://example.com/a',
            snippet: '证据',
          ),
        ],
      );

      await service.research(
        AppSettings(textModel: 'm'),
        'key',
        'search',
        run,
        authorized: () => true,
        onProgress: () async {},
      );

      expect(requests, 0);
      expect(run.calls, 2);
      expect(run.status, 'complete');
      expect(run.report, '已保存报告 [S1]');
    },
  );
  test(
    'research resumes a second round compare without repeating search',
    () async {
      var searchRequests = 0, modelRequests = 0;
      final service = IntelligenceService(
        client: MockClient((request) async {
          if (request.url.path == '/search') {
            searchRequests++;
            return http.Response(jsonEncode({'results': []}), 200);
          }
          modelRequests++;
          return completion({
            'report': '第二轮更新 [S2]',
            'nextQuery': '',
            'meaningful': true,
          });
        }),
      );
      final run = ResearchRun(
        id: 'r',
        goal: '问题',
        callLimit: 4,
        calls: 3,
        report: '第一轮报告 [S1]',
        pendingStage: 'compare',
        pendingQuery: '问题\n补充查证（限定原主题）：新证据',
        steps: [
          '检索：问题',
          '检索完成：问题',
          '比较证据并检查研究缺口',
          '待查：问题\n补充查证（限定原主题）：新证据',
          '检索：问题\n补充查证（限定原主题）：新证据',
          '检索完成：问题\n补充查证（限定原主题）：新证据',
        ],
        sources: [
          ResearchSource(
            id: 'S1',
            title: '旧来源',
            url: 'https://example.com/old',
            snippet: '旧证据',
          ),
          ResearchSource(
            id: 'S2',
            title: '新来源',
            url: 'https://example.com/new',
            snippet: '新证据',
          ),
        ],
      );

      await service.research(
        AppSettings(textModel: 'm'),
        'key',
        'search',
        run,
        authorized: () => true,
        onProgress: () async {},
      );

      expect(searchRequests, 0);
      expect(modelRequests, 1);
      expect(run.calls, 4);
      expect(run.status, 'complete');
      expect(run.report, '第二轮更新 [S2]');
      expect(run.pendingStage, isEmpty);
    },
  );
  test('research keeps a completed exhausted-budget report complete', () async {
    var requests = 0;
    final service = IntelligenceService(
      client: MockClient((request) async {
        requests++;
        return completion({'report': '不应调用 [S1]', 'nextQuery': ''});
      }),
    );
    final run = ResearchRun(
      id: 'r',
      goal: '问题',
      callLimit: 4,
      calls: 4,
      report: '最终报告 [S2]',
      steps: [
        '检索：问题',
        '检索完成：问题',
        '比较证据并检查研究缺口',
        '待查：历史追查',
        '检索：历史追查',
        '检索完成：历史追查',
        '比较证据并检查研究缺口',
      ],
      sources: [
        ResearchSource(
          id: 'S2',
          title: '最终来源',
          url: 'https://example.com/final',
          snippet: '最终证据',
        ),
      ],
    );

    await service.research(
      AppSettings(textModel: 'm'),
      'key',
      'search',
      run,
      authorized: () => true,
      onProgress: () async {},
    );

    expect(requests, 0);
    expect(run.status, 'complete');
    expect(run.report, '最终报告 [S2]');
  });
  test('research exposes requestPending before remote calls finish', () async {
    final seenPending = <bool>[];
    final service = IntelligenceService(
      client: MockClient((request) async {
        return request.url.path == '/search'
            ? http.Response(jsonEncode({'results': []}), 200)
            : completion({'report': 'report', 'nextQuery': ''});
      }),
    );
    final run = ResearchRun(id: 'r', goal: '问题', callLimit: 2);

    await service.research(
      AppSettings(textModel: 'm'),
      'key',
      'search',
      run,
      authorized: () => true,
      onProgress: () async {
        seenPending.add(run.requestPending);
      },
    );

    expect(seenPending, contains(true));
    expect(run.requestPending, isFalse);
  });
  test('research checks revocation between remote operations', () async {
    var authorized = true, requests = 0;
    final service = IntelligenceService(
      client: MockClient((r) async {
        requests++;
        authorized = false;
        return http.Response(
          jsonEncode({'results': []}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final run = ResearchRun(id: 'r', goal: '研究');
    await service.research(
      AppSettings(textModel: 'm'),
      'key',
      'search',
      run,
      authorized: () => authorized,
      onProgress: () async {},
    );
    expect(requests, 1);
    expect(run.status, 'paused');
  });
  test(
    'provider failures expose status without leaking authorization',
    () async {
      final service = IntelligenceService(
        client: MockClient((r) async => http.Response('secret-key', 401)),
      );
      await expectLater(
        service.analyze(
          AppSettings(textModel: 'm'),
          'secret-key',
          LibraryItem(id: 'a', title: 'a', kind: ItemKind.text),
          [],
        ),
        throwsA(
          predicate(
            (e) =>
                e.toString().contains('401') &&
                !e.toString().contains('secret-key'),
          ),
        ),
      );
    },
  );
  test('analysis rejects fabricated inline source references', () async {
    final service = IntelligenceService(
      client: MockClient(
        (r) async => completion({
          'summary': '见 [invented]',
          'sourceIds': ['a'],
        }),
      ),
    );
    await expectLater(
      service.analyze(
        AppSettings(textModel: 'm'),
        'key',
        LibraryItem(id: 'a', title: 'a', kind: ItemKind.text),
        [],
      ),
      throwsFormatException,
    );
  });
  test(
    'topic synthesis rejects inline references outside the provided library',
    () async {
      final service = IntelligenceService(
        client: MockClient(
          (r) async => completion({
            'overview': '观点见 [missing]',
            'sourceIds': ['a'],
          }),
        ),
      );
      await expectLater(
        service.synthesize(
          AppSettings(textModel: 'm'),
          'key',
          Topic(id: 't', title: '主题', question: '问题'),
          [LibraryItem(id: 'a', title: 'a', kind: ItemKind.text)],
        ),
        throwsFormatException,
      );
    },
  );
  test('topic synthesis uses selected confirmed context and explicit empty source scope', () async {
    Map<String, dynamic>? body;
    final service = IntelligenceService(
      client: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return completion({'overview': '只基于背景', 'sourceIds': []});
      }),
    );

    await service.synthesize(
      AppSettings(textModel: 'm'),
      'key',
      Topic(
        id: 't',
        title: '主题',
        question: '问题',
        selectedSourceIds: [],
        selectedContextIds: ['confirmed', 'draft'],
        contextEntries: [
          ContextEntry(
            id: 'confirmed',
            kind: 'judgement',
            text: '用户确认判断',
            confirmed: true,
          ),
          ContextEntry(
            id: 'draft',
            kind: 'judgement',
            text: 'AI 待确认判断',
            confirmed: false,
          ),
          ContextEntry(
            id: 'inactive',
            kind: 'background',
            text: '停用背景',
            confirmed: true,
            active: false,
          ),
        ],
      ),
      [LibraryItem(id: 'a', title: 'a', kind: ItemKind.text, body: '正文')],
    );

    final prompt = body!['messages'][1]['content'] as String;
    final payload = jsonDecode(prompt.split('\n').last) as Map<String, dynamic>;
    expect(payload['sources'], isEmpty);
    expect(payload['contexts'], hasLength(1));
    expect(payload['contexts'].single['text'], '用户确认判断');
  });
  test('external research prompt carries provided local context', () async {
    String? modelPrompt;
    final service = IntelligenceService(
      client: MockClient((request) async {
        if (request.url.path == '/search') {
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'title': 'source',
                  'url': 'https://example.com/a',
                  'content': 'evidence',
                },
              ],
            }),
            200,
          );
        }
        modelPrompt = request.body;
        return completion({'report': 'report [S1]', 'nextQuery': ''});
      }),
    );

    await service.research(
      AppSettings(textModel: 'm'),
      'key',
      'search',
      ResearchRun(id: 'r', goal: 'question', callLimit: 2),
      authorized: () => true,
      onProgress: () async {},
      localContext: {
        'contexts': [
          {'id': 'c1', 'text': '用户确认背景'},
        ],
      },
    );

    expect(modelPrompt, contains('用户确认背景'));
  });
  test('external report with a fabricated nonstandard citation is not marked complete', () async {
    final service = IntelligenceService(
      client: MockClient((request) async {
        if (request.url.path == '/search') {
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'title': 'source',
                  'url': 'https://example.com/a',
                  'content': 'evidence',
                },
              ],
            }),
            200,
          );
        }
        return completion({
          'report': 'See [invented]',
          'nextQuery': '',
          'meaningful': true,
        });
      }),
    );
    final run = ResearchRun(id: 'r', goal: 'question', callLimit: 2);
    await service.research(
      AppSettings(textModel: 'm'),
      'key',
      'search',
      run,
      authorized: () => true,
      onProgress: () async {},
    );
    expect(run.status, 'failed');
    expect(run.report, isEmpty);
  });
  test('authenticated cloud endpoints reject cleartext before transmitting credentials', () async {
    var requests = 0;
    final service = IntelligenceService(
      client: MockClient((r) async {
        requests++;
        return completion({'summary': 'x'});
      }),
    );
    await expectLater(
      service.analyze(
        AppSettings(endpoint: 'http://public.example/v1', textModel: 'm'),
        'secret',
        LibraryItem(id: 'a', title: 'a', kind: ItemKind.text),
        [],
      ),
      throwsFormatException,
    );
    expect(requests, 0);
  });
  group('task scoped request instrumentation', () {
    late DiagnosticStore logs;
    setUp(() {
      logs = DiagnosticStore(':memory:');
    });
    tearDown(() {
      logs.close();
    });
    Future<Map<String, dynamic>> invoke(
      IntelligenceService service, {
      bool Function()? allowed,
    }) => logs.runTask(
      type: 'analysis',
      title: 'model call',
      allowed: allowed,
      body: () => logs.step(
        'model',
        () => service.complete(
          AppSettings(textModel: 'm'),
          'actual-key',
          'private prompt',
        ),
      ),
    );
    test(
      'disabled capture retains actual usage, ids, model and timing only',
      () async {
        final service = IntelligenceService(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'id': 'completion-id',
                'usage': {'prompt_tokens': 9, 'completion_tokens': 2},
                'choices': [
                  {
                    'message': {'content': '{"answer":"private answer"}'},
                  },
                ],
              }),
              200,
              headers: {'x-request-id': 'request-id'},
            ),
          ),
        );
        await invoke(service);
        final task = logs.tasks.single, call = logs.tasks.single.calls.single;
        expect(task.status, 'succeeded');
        expect(call.model, 'm');
        expect(call.requestId, 'request-id');
        expect(call.statusCode, 200);
        expect(call.usage, {'prompt_tokens': 9, 'completion_tokens': 2});
        expect(call.endedAt, isNotNull);
        expect(call.request, isNull);
        expect(call.response, isNull);
        expect(call.stepId, task.steps.single.id);
        expect(
          utf8.decode(logs.exportLogs()),
          isNot(contains('private prompt')),
        );
      },
    );
    test('enabled capture redacts credential echo and images, missing usage stays null', () async {
      logs.debugEnabled = true;
      final service = IntelligenceService(
        client: MockClient((_) async => completion({'answer': 'actual-key'})),
      );
      await logs.runTask(
        type: 'model',
        title: 'vision',
        body: () => service.complete(
          AppSettings(visionModel: 'v'),
          'actual-key',
          'prompt',
          imageDataUrls: ['data:image/png;base64,YWJj'],
        ),
      );
      final call = logs.tasks.single.calls.single;
      expect(call.request, contains('image:png'));
      expect(call.usage, isNull);
      expect(utf8.decode(logs.exportLogs()), isNot(contains('YWJj')));
      expect(utf8.decode(logs.exportLogs()), isNot(contains('actual-key')));
    });
    test(
      'non 2xx reads bounded response and records failure even if caught',
      () async {
        logs.debugEnabled = true;
        final service = IntelligenceService(
          client: MockClient(
            (_) async => http.Response(
              '{"message":"actual-key","api_key":"other-secret"}',
              429,
            ),
          ),
        );
        await logs.runTask(
          type: 'model',
          title: 'caught HTTP',
          body: () async {
            try {
              await service.complete(
                AppSettings(textModel: 'm'),
                'actual-key',
                'prompt',
              );
            } catch (_) {}
          },
        );
        final task = logs.tasks.single, call = logs.tasks.single.calls.single;
        expect(task.status, 'failed');
        expect(call.statusCode, 429);
        expect(call.response, isNotNull);
        expect(call.error, contains('429'));
        final exported = utf8.decode(logs.exportLogs());
        expect(exported, isNot(contains('actual-key')));
        expect(exported, isNot(contains('other-secret')));
      },
    );
    test('malformed provider JSON does not leak payload into ordinary error metadata', () async {
      final service = IntelligenceService(
        client: MockClient(
          (_) async =>
              http.Response('private raw response that is not JSON', 200),
        ),
      );
      await expectLater(invoke(service), throwsFormatException);
      final task = logs.tasks.single;
      expect(task.status, 'failed');
      expect(task.calls.single.error, isNotNull);
      expect(
        utf8.decode(logs.exportLogs()),
        isNot(contains('private raw response')),
      );
    });
    test('malformed model content is recorded as call failure', () async {
      final service = IntelligenceService(
        client: MockClient(
          (_) async => http.Response(
            '{"choices":[{"message":{"content":"not JSON"}}]}',
            200,
          ),
        ),
      );
      await expectLater(invoke(service), throwsFormatException);
      expect(logs.tasks.single.calls.single.error, isNotNull);
    });
    test('timeout and oversized responses have recorded failures', () async {
      final timeout = IntelligenceService(
        requestTimeout: const Duration(milliseconds: 1),
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 15));
          return completion({});
        }),
      );
      await expectLater(invoke(timeout), throwsA(isA<TimeoutException>()));
      expect(logs.tasks.single.calls.single.error, isNotNull);
      final oversized = IntelligenceService(
        responseLimitBytes: 10,
        client: MockClient((_) async => completion({'answer': 'too large'})),
      );
      await expectLater(invoke(oversized), throwsStateError);
      expect(logs.tasks.first.calls.single.error, contains('响应过大'));
    });
    test(
      'guards block before sending and discard responses after source changes',
      () async {
        var sends = 0, allowed = true;
        final service = IntelligenceService(
          client: MockClient((_) async {
            sends++;
            allowed = false;
            return completion({'answer': 'late'});
          }),
        );
        await expectLater(
          invoke(service, allowed: () => false),
          throwsA(isA<DiagnosticCancelled>()),
        );
        expect(sends, 0);
        await expectLater(
          invoke(service, allowed: () => allowed),
          throwsA(isA<DiagnosticCancelled>()),
        );
        expect(sends, 1);
        expect(logs.tasks.first.status, 'cancelled');
        expect(logs.tasks.first.calls.single.error, isNotNull);
      },
    );
    test(
      'research excludes canonical blocked URLs from model evidence',
      () async {
        String? modelPrompt;
        final service = IntelligenceService(
          client: MockClient((request) async {
            if (request.url.path == '/search') {
              return http.Response(
                jsonEncode({
                  'results': [
                    {
                      'url': 'https://example.com/blocked/#part',
                      'content': 'excluded evidence',
                    },
                    {
                      'url': 'https://example.com/allowed',
                      'content': 'allowed evidence',
                    },
                  ],
                }),
                200,
              );
            }
            modelPrompt = request.body;
            return completion({'report': 'report [S1]', 'nextQuery': ''});
          }),
        );
        final run = ResearchRun(id: 'r', goal: 'question', callLimit: 2);
        await logs.runTask(
          type: 'research',
          title: 'research',
          excludedUrls: {'https://example.com/blocked'},
          body: () => service.research(
            AppSettings(textModel: 'm'),
            'key',
            'search-key',
            run,
            authorized: () => true,
            onProgress: () async {},
          ),
        );
        expect(run.sources.single.url, 'https://example.com/allowed');
        expect(modelPrompt, isNot(contains('excluded evidence')));
      },
    );

    test(
      'research records diagnostic timeline steps for every remote call',
      () async {
        var searchCount = 0;
        final service = IntelligenceService(
          client: MockClient((request) async {
            if (request.url.path == '/search') {
              searchCount++;
              return http.Response(
                jsonEncode({
                  'results': [
                    {
                      'title': 'source $searchCount',
                      'url': 'https://example.com/source-$searchCount',
                      'content': 'evidence $searchCount',
                    },
                  ],
                }),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }
            return completion({
              'report': 'report [S1]',
              'nextQuery': searchCount == 1 ? 'more evidence' : '',
              'meaningful': true,
            });
          }),
        );
        final run = ResearchRun(id: 'r', goal: '笔记方法', callLimit: 4);

        await logs.runTask(
          type: 'research',
          title: 'research',
          body: () => service.research(
            AppSettings(textModel: 'm'),
            'key',
            'search-key',
            run,
            authorized: () => true,
            onProgress: () async {},
          ),
        );

        final task = logs.tasks.single;
        expect(task.status, 'succeeded');
        expect(task.calls, hasLength(4));
        expect(task.steps, hasLength(4));
        expect(task.steps.map((step) => step.label), [
          '检索：笔记方法',
          '比较证据并检查研究缺口',
          '检索：笔记方法\n补充查证（限定原主题）：more evidence',
          '比较证据并检查研究缺口',
        ]);
        expect(task.steps.every((step) => step.status == 'succeeded'), isTrue);
        expect(task.calls.map((call) => call.stepId), [
          task.steps[0].id,
          task.steps[1].id,
          task.steps[2].id,
          task.steps[3].id,
        ]);
        expect(
          task.steps.every(
            (step) =>
                step.endedAt!.difference(step.startedAt).inMilliseconds >= 0,
          ),
          isTrue,
        );
      },
    );

    test('optional numeric or structured response ids never fail valid completions', () async {
      for (final id in [
        123,
        {'provider': 'nested'},
        ['unexpected'],
      ]) {
        logs.clear();
        final service = IntelligenceService(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'id': id,
                'choices': [
                  {
                    'message': {'content': '{"answer":"valid"}'},
                  },
                ],
              }),
              200,
            ),
          ),
        );
        final result = await invoke(service);
        expect(result['answer'], 'valid');
        expect(logs.tasks.single.status, 'succeeded');
        expect(
          logs.tasks.single.calls.single.requestId,
          id is num ? '123' : null,
        );
      }
    });
  });
}
