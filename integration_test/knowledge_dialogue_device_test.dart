import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:readlater/core/app_controller.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/store.dart';
import 'package:readlater/main.dart';
import 'package:readlater/ui/conversation_page.dart';
import 'package:readlater/ui/knowledge_page.dart';

class _MemorySecrets implements SecretStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

class _KnowledgeDialogueFixture {
  _KnowledgeDialogueFixture._(this.server);

  final HttpServer server;
  final counts = <String, int>{
    'analysis': 0,
    'sourceSummary': 0,
    'pdfSummary': 0,
    'sourceMerge': 0,
    'dialogue': 0,
  };

  Uri get base => Uri.parse('http://127.0.0.1:${server.port}');

  static Future<_KnowledgeDialogueFixture> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fixture = _KnowledgeDialogueFixture._(server);
    fixture._serve();
    return fixture;
  }

  void _serve() {
    server.listen((request) async {
      try {
        await _handle(request);
      } catch (error, stackTrace) {
        stderr.writeln('knowledge_dialogue_fixture error: $error');
        stderr.writeln(stackTrace);
        await _send(request.response, 500, 'text/plain', 'fixture error');
      }
    });
  }

  Future<void> close() => server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    if (path == '/stats') {
      await _send(
        request.response,
        200,
        'application/json',
        jsonEncode(counts),
      );
      return;
    }
    if (path == '/image.png') {
      await _sendBytes(request.response, 200, 'image/png', _pngBytes);
      return;
    }
    if (path == '/sample.pdf') {
      await _sendBytes(request.response, 200, 'application/pdf', _pdfBytes());
      return;
    }
    if (path == '/v1/chat/completions' && request.method == 'POST') {
      if (request.headers.value(HttpHeaders.authorizationHeader) !=
          'Bearer fixture-key') {
        await _send(request.response, 401, 'text/plain', 'fixture auth');
        return;
      }
      final body = jsonDecode(await utf8.decoder.bind(request).join());
      final prompt = _promptText(Map<String, dynamic>.from(body as Map));
      final result = _complete(prompt);
      await _send(
        request.response,
        200,
        'application/json; charset=utf-8',
        jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': jsonEncode(result)},
            },
          ],
        }),
      );
      return;
    }
    await _send(request.response, 404, 'text/plain', 'not found');
  }

  String _promptText(Map<String, dynamic> body) {
    final messages = body['messages'] as List;
    final content = (messages.last as Map)['content'];
    if (content is String) return content;
    if (content is List) {
      return ((content.first as Map)['text'] as String?) ?? '';
    }
    return '';
  }

  Map<String, dynamic> _complete(String prompt) {
    if (prompt.contains('"task":"summarize_source_segment"')) {
      counts['sourceSummary'] = counts['sourceSummary']! + 1;
      final payload = _jsonAfterFirstBrace(prompt);
      final source = payload['source'] as Map;
      return {
        'summary':
            '中立摘要：${source['title']} 的这一段说明，超长资料应先分段压缩，只保存稳定窗口证据，再按问题读取原文。尾部事实仍应保持可追溯。',
      };
    }
    if (prompt.contains('"task":"summarize_pdf_pages"')) {
      counts['pdfSummary'] = counts['pdfSummary']! + 1;
      return {'summary': '中立摘要：PDF 页面展示了本地证明材料，视觉证据保持未精确文字核验。'};
    }
    if (prompt.contains('"task":"merge_source_segment_summaries"')) {
      counts['sourceMerge'] = counts['sourceMerge']! + 1;
      return {'summary': '合并摘要：资料主张先分段理解，再用对话按需读取原文窗口，避免每次提交全文。'};
    }
    if (prompt.contains('生成观点卡片')) {
      counts['analysis'] = counts['analysis']! + 1;
      final marker = '\n输入数据：';
      final input = jsonDecode(
        prompt.substring(prompt.indexOf(marker) + marker.length),
      ) as Map<String, dynamic>;
      final item = Map<String, dynamic>.from(input['item'] as Map);
      final itemId = item['id'] as String;
      final availableEvidence = input['availableEvidence'];
      final evidence = availableEvidence is List && availableEvidence.isNotEmpty
          ? [Map<String, dynamic>.from(availableEvidence.first as Map)]
          : _evidenceFromItem(item);
      return {
        'brief': '这份资料说明长上下文需要先被压缩成可复用摘要，再保留可核验来源窗口。',
        'summary': '资料强调分段摘要、按需读取和证据窗口，避免每次把全文交给模型。[$itemId]',
        'insights': ['分段摘要可降低每次对话的上下文压力 [$itemId]'],
        'structuredInsights': [
          if (evidence.isNotEmpty)
            {
              'id': 'structured-$itemId',
              'title': '长上下文先分段摘要',
              'finding': '超长资料先形成中立摘要，再按问题读取窗口。',
              'change': '减少重复提交全文。',
              'impact': '降低超时概率。',
              'unknowns': ['仍需人工确认摘要是否覆盖关键限制。'],
              'evidence': evidence,
              'verdict': 'new',
            },
        ],
        'connections': ['本地资料之间可通过稳定来源窗口继续追问。'],
        'questions': ['哪些问题需要回读原文尾部？'],
        'sourceIds': [itemId],
        'suggestedTopics': ['长上下文知识管理'],
      };
    }
    if (prompt.contains('本地知识库对话')) {
      counts['dialogue'] = counts['dialogue']! + 1;
      final marker = '\n输入数据：';
      final payload = jsonDecode(
        prompt.substring(prompt.indexOf(marker) + marker.length),
      ) as Map<String, dynamic>;
      final visual = payload['visualEvidence'] as List? ?? const [];
      if (visual.isNotEmpty) {
        final proof = Map<String, dynamic>.from(visual.first as Map);
        return {
          'answer': '我已读取本地附件的视觉证明；它只能作为未经精确文字核验的观察。',
          'evidence': [
            {
              'sourceId': proof['sourceId'],
              'sourceVersion': proof['sourceVersion'],
              'assetFingerprint': proof['assetFingerprint'],
              if (proof['page'] != null) 'pdfPage': proof['page'],
              'unresolved': true,
              'note': '视觉内容未经精确文字核验',
            },
          ],
          'remainingGaps': ['视觉内容仍需打开原始附件复核。'],
          'proposals': [],
        };
      }
      final windows = (payload['windows'] as List? ?? const [])
          .map((window) => Map<String, dynamic>.from(window as Map))
          .toList();
      final selected = windows.firstWhere(
        (window) => (window['text'] as String).contains('尾部事实'),
        orElse: () => windows.isEmpty ? <String, dynamic>{} : windows.first,
      );
      return {
        'answer': '尾部事实说明：长资料应先缓存中立摘要，追问时只补读相关窗口。',
        'presentation': {
          'brief': '对话把尾部事实沉淀为可确认知识。',
          'sections': [
            {'title': '处理超长资料', 'body': '先分段摘要，再按问题回读具体窗口，可以减少重复提交全文。'},
          ],
        },
        'evidence': selected.isEmpty
            ? []
            : [
                {
                  'sourceId': selected['sourceId'],
                  'sourceVersion': selected['sourceVersion'],
                  'blockId': selected['blockId'],
                  'windowId': selected['id'],
                  'start': selected['start'],
                  'end': selected['end'],
                  'quote': selected['text'],
                },
              ],
        'remainingGaps': [],
        'proposals': [],
      };
    }
    throw StateError(
      'Unhandled fixture prompt: ${prompt.substring(0, min(160, prompt.length))}',
    );
  }

  List<Map<String, dynamic>> _evidenceFromItem(Map<String, dynamic> item) {
    final blocks = item['contentBlocks'];
    if (blocks is! List || blocks.isEmpty) return const [];
    final block = Map<String, dynamic>.from(blocks.first as Map);
    final text = (block['text'] as String? ?? '').trim();
    if (text.isEmpty) return const [];
    return [
      {
        'sourceId': item['id'],
        'sourceVersion': item['contentVersion'],
        'blockId': block['id'],
        'quote': text.substring(0, min(80, text.length)),
      },
    ];
  }

  Map<String, dynamic> _jsonAfterFirstBrace(String prompt) {
    final start = prompt.indexOf('{');
    return jsonDecode(prompt.substring(start)) as Map<String, dynamic>;
  }

  Future<void> _send(
    HttpResponse response,
    int status,
    String contentType,
    String body,
  ) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.parse(contentType);
    response.write(body);
    await response.close();
  }

  Future<void> _sendBytes(
    HttpResponse response,
    int status,
    String contentType,
    List<int> bytes,
  ) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.parse(contentType);
    response.add(bytes);
    await response.close();
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('device knowledge dialogue keeps source windows and proof local', (
    tester,
  ) async {
    final fixture = await _KnowledgeDialogueFixture.start();
    addTearDown(fixture.close);
    final support = await getApplicationSupportDirectory();
    final root = await Directory(
      '${support.path}/knowledge-dialogue-device-${DateTime.now().microsecondsSinceEpoch}',
    ).create(recursive: true);
    final screens = await Directory('${root.path}/screens').create();
    final controller = AppController(
      store: LocalStore('${root.path}/library-test'),
      secrets: _MemorySecrets(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.saveSettings(
      AppSettings(
        endpoint: '${fixture.base}/v1',
        textModel: 'fixture-text',
        visionModel: 'fixture-vision',
        modelTextContextChars: 24000,
      ),
      apiKey: 'fixture-key',
    );

    var converted = false;
    Future<void> screenshot(String name) async {
      if (!converted) {
        await binding.convertFlutterSurfaceToImage();
        converted = true;
      }
      await tester.pumpAndSettle();
      final bytes = await binding.takeScreenshot(name);
      expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      await File('${screens.path}/$name.png').writeAsBytes(bytes, flush: true);
    }

    final longText = [
      for (var i = 0; i < 740; i++)
        '第$i段：长上下文资料用于验证分段摘要缓存。这里反复说明资料很多，不能每次全部提交给模型。',
      '尾部事实：对话应该读取这个尾部窗口，而不是把整篇资料再次塞进模型。',
    ].join('\n');
    expect(longText.length, greaterThan(24000));
    final longItem = await controller.captureText(longText, title: '超长资料');
    await controller.waitForIdle().timeout(const Duration(minutes: 4));
    expect(longItem.status, 'ready', reason: longItem.error);
    expect(controller.data.segmentSummaries, isNotEmpty);
    final sourceSummaryCalls = fixture.counts['sourceSummary']!;
    expect(sourceSummaryCalls, greaterThan(0));
    await controller.analyze(longItem.id);
    await controller.waitForIdle().timeout(const Duration(minutes: 4));
    expect(fixture.counts['sourceSummary'], sourceSummaryCalls);

    final conversationId = await controller.startConversation(
      ConversationScope.item,
      scopeId: longItem.id,
    );
    final turnId = await controller.submitQuestion(
      conversationId,
      '尾部事实对超长资料处理有什么要求？',
    );
    await controller.waitForIdle().timeout(const Duration(minutes: 4));
    final turn = controller.data.conversationTurns.singleWhere(
      (candidate) => candidate.id == turnId,
    );
    expect(turn.status, 'completed', reason: turn.error);
    expect(turn.answer, contains('尾部事实'));
    expect(turn.windows.map((window) => window.text).join(), contains('尾部事实'));
    expect(turn.evidence.single.windowId, isNotEmpty);
    final proposalId = await controller.proposeKnowledgeFromTurn(turn.id);
    final revisionId = await controller.acceptKnowledgeProposal(proposalId);
    final revision = controller.data.knowledgeRevisions.singleWhere(
      (candidate) => candidate.id == revisionId,
    );
    expect(revision.originTurnId, turn.id);
    expect(
      controller.data.knowledgeProposals
          .singleWhere((proposal) => proposal.id == proposalId)
          .status,
      'accepted',
    );

    final pdfFile = await File('${root.path}/sample.pdf')
        .writeAsBytes(_pdfBytes(), flush: true);
    final rendered = await controller.native.renderPdf(pdfFile.path);
    expect(rendered.pageCount, 1);
    expect(rendered.images, isNotEmpty);
    final pdfItem = await controller.importFile(pdfFile.path, name: '证明.pdf');
    await controller.waitForIdle().timeout(const Duration(minutes: 4));
    expect(pdfItem.status, 'ready', reason: pdfItem.error);
    expect(pdfItem.pdfPageCount, 1);
    final pdfConversationId = await controller.startConversation(
      ConversationScope.item,
      scopeId: pdfItem.id,
    );
    final pdfTurnId = await controller.submitQuestion(
      pdfConversationId,
      '读取第一页视觉证据',
    );
    await controller.waitForIdle().timeout(const Duration(minutes: 4));
    final pdfTurn = controller.data.conversationTurns.singleWhere(
      (candidate) => candidate.id == pdfTurnId,
    );
    expect(pdfTurn.status, 'completed', reason: pdfTurn.error);
    expect(pdfTurn.visualEvidence.single.page, 1);
    expect(pdfTurn.visualEvidence.single.assetFingerprint, hasLength(64));
    expect(pdfTurn.visualEvidence.single.unverified, isTrue);
    expect(
      pdfTurn.evidence.single.assetFingerprint,
      pdfTurn.visualEvidence.single.assetFingerprint,
    );

    final pngFile = await File('${root.path}/standalone.png')
        .writeAsBytes(_pngBytes, flush: true);
    final originalPng = await pngFile.readAsBytes();
    final normalized = base64Decode(
      await controller.native.normalizeImage(pngFile.path),
    );
    expect(normalized.length, lessThanOrEqualTo(1024 * 1024));
    expect(await pngFile.readAsBytes(), originalPng);
    await _expectExifOrientation(controller, root, orientation: 5);
    await _expectExifOrientation(controller, root, orientation: 7);

    final pendingConversation = Conversation(
      id: 'restore-conversation',
      title: '恢复验证',
      scope: ConversationScope.library,
    );
    final pendingTurn = ConversationTurn(
      id: 'restore-turn',
      conversationId: pendingConversation.id,
      question: '恢复后不应自动重发',
      status: 'running',
      requestPending: true,
    );
    controller.data.conversations.add(pendingConversation);
    controller.data.conversationTurns.add(pendingTurn);
    controller.store.saveWithRuntime(controller.data, controller.runtime);
    final backup = await controller.backup();
    final restoredRoot = await Directory('${root.path}/restored').create();
    final restored = AppController(
      store: LocalStore('${restoredRoot.path}/library-test'),
      secrets: _MemorySecrets(),
    );
    addTearDown(restored.dispose);
    await restored.initialize();
    await restored.restore(backup);
    final restoredTurn = restored.data.conversationTurns.singleWhere(
      (candidate) => candidate.id == pendingTurn.id,
    );
    expect(restoredTurn.status, 'interrupted');
    expect(restoredTurn.requestPending, isTrue);
    expect(
      restored.runtime.jobs.where((job) => job.type == 'conversation'),
      isEmpty,
    );

    await tester.pumpWidget(ReadlaterApp(controller: controller));
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ConversationPage(
          controller: controller,
          scope: ConversationScope.item,
          scopeId: longItem.id,
          sourceIds: [longItem.id],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('尾部事实说明'), findsOneWidget);
    await screenshot('knowledge-dialogue-conversation');
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            KnowledgePage(controller: controller, topicId: revision.topicId),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('已确认知识'), findsOneWidget);
    await screenshot('knowledge-dialogue-knowledge');

    await File('${root.path}/evidence.json').writeAsString(
      jsonEncode({
        'fixture': fixture.base.toString(),
        'libraryRoot': controller.store.root,
        'screens': [
          'knowledge-dialogue-conversation.png',
          'knowledge-dialogue-knowledge.png',
        ],
        'sourceSummaryCalls': sourceSummaryCalls,
        'sourceSummaryCallsAfterSecondAnalysis':
            fixture.counts['sourceSummary'],
        'dialogueCalls': fixture.counts['dialogue'],
        'longTextChars': longText.length,
        'tailWindowIds': turn.windows
            .where((window) => window.text.contains('尾部事实'))
            .map((window) => window.id)
            .toList(),
        'pdfVisualEvidence': pdfTurn.visualEvidence.single.toJson(),
        'normalizedPngBytes': normalized.length,
        'originalPngSha256': sha256.convert(originalPng).toString(),
        'acceptedRevisionId': revisionId,
        'restoredTurnStatus': restoredTurn.status,
        'restoredTurnRequestPending': restoredTurn.requestPending,
      }),
      flush: true,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAIAAADYYG7QAAAAQklEQVR4nO3OMQ0AIBAAsXfHiBD877jgGJpUQGed/ZXJB0JCQkL1QEhISKgeCAkJCdUDISEhoXogJCQkVA+EhIQeu13nCYghyLU9AAAAAElFTkSuQmCC',
);

Uint8List _pdfBytes() {
  final stream = 'BT /F1 20 Tf 40 120 Td (Readlater local PDF evidence) Tj ET';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 200] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Length ${stream.length} >>\nstream\n$stream\nendstream',
  ];
  var data = '%PDF-1.4\n';
  final offsets = <int>[];
  for (final (index, object) in objects.indexed) {
    offsets.add(utf8.encode(data).length);
    data += '${index + 1} 0 obj\n$object\nendobj\n';
  }
  final xref = utf8.encode(data).length;
  data += 'xref\n0 6\n0000000000 65535 f \n';
  for (final offset in offsets) {
    data += '${offset.toString().padLeft(10, '0')} 00000 n \n';
  }
  data += 'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n$xref\n%%EOF';
  return Uint8List.fromList(utf8.encode(data));
}

Future<void> _expectExifOrientation(
  AppController controller,
  Directory root, {
  required int orientation,
}) async {
  final source = await File('${root.path}/orientation-source.png')
      .writeAsBytes(await _cornerPng(), flush: true);
  final normalizedJpeg = base64Decode(
    await controller.native.normalizeImage(source.path),
  );
  final exifFile = await File('${root.path}/orientation-$orientation.jpg')
      .writeAsBytes(
        _injectExifOrientation(normalizedJpeg, orientation),
        flush: true,
      );
  final normalized = base64Decode(
    await controller.native.normalizeImage(exifFile.path),
  );
  final image = await _decodeRgba(normalized);
  expect(image.width, 150);
  expect(image.height, 100);
  final corners = _corners(image);
  if (orientation == 5) {
    _expectApproxColor(corners.topLeft, _cornerColors.topLeft);
    _expectApproxColor(corners.topRight, _cornerColors.bottomLeft);
    _expectApproxColor(corners.bottomLeft, _cornerColors.topRight);
    _expectApproxColor(corners.bottomRight, _cornerColors.bottomRight);
  } else if (orientation == 7) {
    _expectApproxColor(corners.topLeft, _cornerColors.bottomRight);
    _expectApproxColor(corners.topRight, _cornerColors.topRight);
    _expectApproxColor(corners.bottomLeft, _cornerColors.bottomLeft);
    _expectApproxColor(corners.bottomRight, _cornerColors.topLeft);
  } else {
    throw ArgumentError.value(orientation, 'orientation');
  }
}

Future<Uint8List> _cornerPng() async {
  const width = 100.0;
  const height = 150.0;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  void rect(
    double left,
    double top,
    double right,
    double bottom,
    ui.Color color,
  ) {
    canvas.drawRect(
      ui.Rect.fromLTRB(left, top, right, bottom),
      ui.Paint()..color = color,
    );
  }

  rect(0, 0, width / 2, height / 2, _cornerColors.topLeft);
  rect(width / 2, 0, width, height / 2, _cornerColors.topRight);
  rect(0, height / 2, width / 2, height, _cornerColors.bottomLeft);
  rect(width / 2, height / 2, width, height, _cornerColors.bottomRight);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width.toInt(), height.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

Uint8List _injectExifOrientation(List<int> jpeg, int orientation) {
  if (jpeg.length < 2 || jpeg[0] != 0xff || jpeg[1] != 0xd8) {
    throw const FormatException('Expected a JPEG with SOI marker');
  }
  final payload = BytesBuilder()
    ..add(ascii.encode('Exif'))
    ..add([0, 0])
    ..add(ascii.encode('II'))
    ..add([0x2a, 0x00])
    ..add([0x08, 0x00, 0x00, 0x00])
    ..add([0x01, 0x00])
    ..add([0x12, 0x01])
    ..add([0x03, 0x00])
    ..add([0x01, 0x00, 0x00, 0x00])
    ..add([orientation, 0x00, 0x00, 0x00])
    ..add([0x00, 0x00, 0x00, 0x00]);
  final app1Payload = payload.toBytes();
  final length = app1Payload.length + 2;
  final app1 = BytesBuilder()
    ..add([0xff, 0xe1, (length >> 8) & 0xff, length & 0xff])
    ..add(app1Payload);
  return Uint8List.fromList([
    jpeg[0],
    jpeg[1],
    ...app1.toBytes(),
    ...jpeg.skip(2),
  ]);
}

Future<_DecodedImage> _decodeRgba(List<int> bytes) async {
  final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final decoded = _DecodedImage(
    width: image.width,
    height: image.height,
    rgba: data!.buffer.asUint8List(),
  );
  image.dispose();
  codec.dispose();
  return decoded;
}

_CornerSample _corners(_DecodedImage image) {
  const inset = 8;
  return _CornerSample(
    topLeft: image.pixel(inset, inset),
    topRight: image.pixel(image.width - inset - 1, inset),
    bottomLeft: image.pixel(inset, image.height - inset - 1),
    bottomRight: image.pixel(image.width - inset - 1, image.height - inset - 1),
  );
}

void _expectApproxColor(ui.Color actual, ui.Color expected) {
  const tolerance = 70;
  int channel(double value) => (value * 255.0).round().clamp(0, 255);
  expect(
    (channel(actual.r) - channel(expected.r)).abs(),
    lessThanOrEqualTo(tolerance),
  );
  expect(
    (channel(actual.g) - channel(expected.g)).abs(),
    lessThanOrEqualTo(tolerance),
  );
  expect(
    (channel(actual.b) - channel(expected.b)).abs(),
    lessThanOrEqualTo(tolerance),
  );
}

class _DecodedImage {
  const _DecodedImage({
    required this.width,
    required this.height,
    required this.rgba,
  });

  final int width, height;
  final Uint8List rgba;

  ui.Color pixel(int x, int y) {
    final offset = (y * width + x) * 4;
    return ui.Color.fromARGB(
      rgba[offset + 3],
      rgba[offset],
      rgba[offset + 1],
      rgba[offset + 2],
    );
  }
}

class _CornerSample {
  const _CornerSample({
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
  });

  final ui.Color topLeft, topRight, bottomLeft, bottomRight;
}

class _CornerColors {
  const _CornerColors({
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
  });

  final ui.Color topLeft, topRight, bottomLeft, bottomRight;
}

const _cornerColors = _CornerColors(
  topLeft: ui.Color(0xffff0000),
  topRight: ui.Color(0xff00c800),
  bottomLeft: ui.Color(0xff0032ff),
  bottomRight: ui.Color(0xffffff00),
);
