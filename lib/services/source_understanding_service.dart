import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../core/models.dart';
import 'intelligence_service.dart';

class SourceUnderstandingService {
  SourceUnderstandingService(this.intelligence, {this.mergeBatchSize = 8})
    : assert(mergeBatchSize >= 2);

  static const promptVersion = 'source-v1';
  static const maxSummaryChars = 2000;

  final IntelligenceService intelligence;
  final int mergeBatchSize;

  List<List<SourceWindow>> segmentWindows(
    List<SourceWindow> windows, {
    required int maxChars,
  }) {
    if (maxChars <= 0) {
      throw ArgumentError.value(maxChars, 'maxChars', 'must be positive');
    }
    final segments = <List<SourceWindow>>[];
    var current = <SourceWindow>[];
    var currentChars = 0;
    for (final window in windows) {
      final pieces = window.text.length > maxChars
          ? _splitWindow(window, maxChars)
          : [window];
      for (final piece in pieces) {
        final size = piece.text.length;
        if (current.isNotEmpty && currentChars + size > maxChars) {
          segments.add(List.unmodifiable(current));
          current = <SourceWindow>[];
          currentChars = 0;
        }
        current.add(piece);
        currentChars += size;
      }
    }
    if (current.isNotEmpty) segments.add(List.unmodifiable(current));
    return List.unmodifiable(segments);
  }

  String textFingerprint(LibraryItem item, List<SourceWindow> windows) {
    if (windows.isEmpty) {
      throw const FormatException('没有可计算指纹的来源窗口');
    }
    _validateTextWindows(item, windows);
    return _digest({
      'promptVersion': promptVersion,
      'sourceId': item.id,
      'title': item.title,
      'sourceVersion': windows.first.sourceVersion,
      'windows': windows
          .map(
            (window) => {
              'id': window.id,
              'blockId': window.blockId,
              'start': window.start,
              'end': window.end,
              'fingerprint': window.fingerprint,
              'text': window.text,
            },
          )
          .toList(),
    });
  }

  String pdfFingerprint(
    LibraryItem item,
    int firstPage,
    List<String> normalizedImages,
    String assetFingerprint,
  ) {
    if (normalizedImages.isEmpty) {
      throw const FormatException('没有可计算指纹的 PDF 页面图像');
    }
    return _digest({
      'promptVersion': promptVersion,
      'sourceId': item.id,
      'title': item.title,
      'sourceVersion': item.contentVersion,
      'firstPage': firstPage,
      'assetFingerprint': assetFingerprint,
      'images': normalizedImages,
    });
  }

  String summaryId(
    String sourceId,
    int sourceVersion,
    int rangeStart,
    int rangeEnd,
    String fingerprint,
  ) {
    if (fingerprint.length < 12) {
      throw const FormatException('来源摘要指纹无效');
    }
    return '$sourceId:$sourceVersion:$rangeStart:$rangeEnd:${fingerprint.substring(0, 12)}';
  }

  Future<SourceSegmentSummary> summarizeText(
    AppSettings settings,
    String key,
    LibraryItem item,
    List<SourceWindow> windows,
  ) async {
    if (windows.isEmpty) {
      throw const FormatException('没有可总结的来源窗口');
    }
    _validateTextWindows(item, windows);
    final sourceVersion = windows.first.sourceVersion;
    final rangeStart = windows.map((window) => window.start).reduce(min);
    final rangeEnd = windows.map((window) => window.end).reduce(max);
    final fingerprint = textFingerprint(item, windows);
    final prompt = _textSummaryPrompt(
      item,
      sourceVersion,
      rangeStart,
      rangeEnd,
      windows,
    );
    _ensurePromptBudget(settings, prompt, settings.textModel);
    final result = await intelligence.complete(settings, key, prompt);
    return SourceSegmentSummary(
      id: summaryId(item.id, sourceVersion, rangeStart, rangeEnd, fingerprint),
      sourceId: item.id,
      sourceVersion: sourceVersion,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      fingerprint: fingerprint,
      promptVersion: promptVersion,
      summary: _summaryText(result),
      evidence: windows.map(_anchorFromWindow).toList(growable: false),
    );
  }

  Future<SourceSegmentSummary> summarizePdf(
    AppSettings settings,
    String key,
    LibraryItem item,
    int firstPage,
    List<String> normalizedImages,
    String assetFingerprint,
  ) async {
    if (normalizedImages.isEmpty) {
      throw const FormatException('没有可总结的 PDF 页面图像');
    }
    if (assetFingerprint.trim().isEmpty) {
      throw const FormatException('PDF 图像缺少稳定指纹');
    }
    final pageCount = normalizedImages.length;
    final lastPage = firstPage + pageCount - 1;
    final fingerprint = pdfFingerprint(
      item,
      firstPage,
      normalizedImages,
      assetFingerprint,
    );
    final prompt = _pdfSummaryPrompt(
      item,
      firstPage,
      lastPage,
      assetFingerprint,
    );
    _ensurePromptBudget(settings, prompt, settings.visionModel);
    final result = await intelligence.complete(
      settings,
      key,
      prompt,
      imageDataUrls: normalizedImages
          .map((image) => 'data:image/jpeg;base64,$image')
          .toList(growable: false),
    );
    return SourceSegmentSummary(
      id: summaryId(
        item.id,
        item.contentVersion,
        firstPage,
        lastPage,
        fingerprint,
      ),
      sourceId: item.id,
      sourceVersion: item.contentVersion,
      rangeStart: firstPage,
      rangeEnd: lastPage,
      pdf: true,
      fingerprint: fingerprint,
      promptVersion: promptVersion,
      summary: _summaryText(result),
      evidence: List.generate(
        pageCount,
        (index) => EvidenceAnchor(
          sourceId: item.id,
          sourceVersion: item.contentVersion,
          pdfPage: firstPage + index,
          assetFingerprint: assetFingerprint,
          unresolved: true,
        ),
      ),
    );
  }

  Future<String> mergeSummaries(
    AppSettings settings,
    String key,
    List<SourceSegmentSummary> summaries,
  ) async {
    if (summaries.isEmpty) return '';
    var layer = summaries
        .map(
          (summary) =>
              _MergeNode(summary.summary, summary.rangeStart, summary.rangeEnd),
        )
        .where((node) => node.text.trim().isNotEmpty)
        .toList(growable: false);
    if (layer.isEmpty) return '';
    while (layer.length > 1) {
      final previousLength = layer.length;
      final next = <_MergeNode>[];
      var index = 0;
      while (index < layer.length) {
        final batch = _boundedMergeBatch(settings, layer, index);
        if (batch.length == 1) {
          next.add(batch.single);
        } else {
          final merged = await _mergeBatch(settings, key, batch);
          next.add(_MergeNode(merged, batch.first.start, batch.last.end));
        }
        index += batch.length;
      }
      if (next.length >= previousLength) {
        throw const FormatException('摘要合并无法在当前模型上下文预算内继续');
      }
      layer = next;
    }
    return layer.single.text;
  }

  Future<String> _mergeBatch(
    AppSettings settings,
    String key,
    List<_MergeNode> batch,
  ) async {
    if (batch.length == 1) return batch.single.text;
    final prompt = _mergePrompt(batch);
    _ensurePromptBudget(settings, prompt, settings.textModel);
    final result = await intelligence.complete(settings, key, prompt);
    return _summaryText(result);
  }

  List<_MergeNode> _boundedMergeBatch(
    AppSettings settings,
    List<_MergeNode> layer,
    int start,
  ) {
    final remaining = layer.length - start;
    if (remaining <= 1) return [layer[start]];
    final maxCount = min(mergeBatchSize, remaining);
    for (var count = maxCount; count >= 2; count--) {
      final batch = layer.skip(start).take(count).toList();
      if (_promptFits(settings, _mergePrompt(batch), settings.textModel)) {
        return batch;
      }
    }
    throw const FormatException('摘要合并输入超过当前模型上下文预算');
  }

  void _validateTextWindows(LibraryItem item, List<SourceWindow> windows) {
    final version = windows.first.sourceVersion;
    for (final window in windows) {
      if (window.sourceId != item.id) {
        throw const FormatException('来源窗口不属于当前资料');
      }
      if (window.sourceVersion != version) {
        throw const FormatException('来源窗口版本不一致');
      }
      if (window.end < window.start) {
        throw const FormatException('来源窗口范围无效');
      }
    }
  }

  EvidenceAnchor _anchorFromWindow(SourceWindow window) => EvidenceAnchor(
    sourceId: window.sourceId,
    sourceVersion: window.sourceVersion,
    blockId: window.blockId,
    windowId: window.id,
    start: window.start,
    end: window.end,
    quote: window.text,
  );

  String _summaryText(Json result) {
    final summary = result['summary'];
    if (summary is! String || summary.trim().isEmpty) {
      throw const FormatException('模型未生成有效来源摘要');
    }
    final text = summary.trim();
    if (text.length > maxSummaryChars) {
      throw const FormatException('模型返回的来源摘要超过 2000 字限制');
    }
    return text;
  }

  String _jsonPrompt(Json payload) => jsonEncode(payload);

  String _textSummaryPrompt(
    LibraryItem item,
    int sourceVersion,
    int rangeStart,
    int rangeEnd,
    List<SourceWindow> windows,
  ) => _jsonPrompt({
    'task': 'summarize_source_segment',
    'promptVersion': promptVersion,
    'instructions': [
      '只总结当前来源片段，不使用用户偏好、历史记录、笔记或外部知识。',
      '保留事实、限定条件、分歧和不确定性。',
      '不要编造引用；证据窗口由调用方根据实际窗口附加。',
      '返回 {"summary":"120到300字中文中立摘要，最多2000字"}。',
    ],
    'source': {
      'id': item.id,
      'title': item.title,
      'kind': item.kind.name,
      'sourceVersion': sourceVersion,
      'rangeStart': rangeStart,
      'rangeEnd': rangeEnd,
    },
    'windows': windows
        .map(
          (window) => {
            'id': window.id,
            'blockId': window.blockId,
            'start': window.start,
            'end': window.end,
            'text': window.text,
          },
        )
        .toList(),
  });

  String _pdfSummaryPrompt(
    LibraryItem item,
    int firstPage,
    int lastPage,
    String assetFingerprint,
  ) => _jsonPrompt({
    'task': 'summarize_pdf_pages',
    'promptVersion': promptVersion,
    'instructions': [
      '只总结随请求提供的 PDF 页面图像，不使用用户偏好、历史记录、笔记或外部知识。',
      '如果图像无法确认，明确写出不确定性。',
      '返回 {"summary":"120到300字中文中立摘要，最多2000字"}。',
    ],
    'source': {
      'id': item.id,
      'title': item.title,
      'kind': item.kind.name,
      'sourceVersion': item.contentVersion,
      'firstPage': firstPage,
      'lastPage': lastPage,
      'assetFingerprint': assetFingerprint,
    },
  });

  String _mergePrompt(List<_MergeNode> batch) => _jsonPrompt({
    'task': 'merge_source_segment_summaries',
    'promptVersion': promptVersion,
    'instructions': [
      '合并这些同一来源或同一任务中的中立片段摘要。',
      '保留事实、限定条件、分歧和未知，不添加外部知识。',
      '返回 {"summary":"中文合并摘要，最多2000字"}。',
    ],
    'segments': batch
        .map(
          (node) => {
            'rangeStart': node.start,
            'rangeEnd': node.end,
            'summary': node.text,
          },
        )
        .toList(),
  });

  bool _promptFits(AppSettings settings, String prompt, String model) {
    final serializedChars = IntelligenceService.textualRequestChars(
      prompt,
      model: model,
    );
    return serializedChars <= settings.modelTextContextChars &&
        utf8.encode(prompt).length <= IntelligenceService.textWireLimit;
  }

  void _ensurePromptBudget(AppSettings settings, String prompt, String model) {
    if (!_promptFits(settings, prompt, model)) {
      throw const FormatException('来源摘要上下文超过本次模型预算，请继续拆分资料');
    }
  }

  String _digest(Json payload) =>
      sha256.convert(utf8.encode(jsonEncode(payload))).toString();

  List<SourceWindow> _splitWindow(SourceWindow window, int maxChars) {
    final pieces = <SourceWindow>[];
    var localStart = 0;
    while (localStart < window.text.length) {
      final localEnd = _safeChunkEnd(window.text, localStart, maxChars);
      final text = window.text.substring(localStart, localEnd);
      final start = window.start + localStart;
      final end = window.start + localEnd;
      final fingerprint = _digest({
        'parentFingerprint': window.fingerprint,
        'start': start,
        'end': end,
        'text': text,
      });
      pieces.add(
        SourceWindow(
          id: '${window.id}:${pieces.length}',
          sourceId: window.sourceId,
          sourceVersion: window.sourceVersion,
          blockId: window.blockId,
          start: start,
          end: end,
          text: text,
          fingerprint: fingerprint,
          readActionId: window.readActionId,
        ),
      );
      localStart = localEnd;
    }
    return pieces;
  }

  int _safeChunkEnd(String text, int start, int maxChars) {
    var end = min(text.length, start + maxChars);
    if (end == text.length) return end;
    if (end > start &&
        _isHighSurrogate(text.codeUnitAt(end - 1)) &&
        _isLowSurrogate(text.codeUnitAt(end))) {
      end--;
    }
    if (end == start) {
      end = min(text.length, start + 2);
    }
    return end;
  }

  bool _isHighSurrogate(int codeUnit) =>
      codeUnit >= 0xD800 && codeUnit <= 0xDBFF;
  bool _isLowSurrogate(int codeUnit) =>
      codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;
}

class _MergeNode {
  const _MergeNode(this.text, this.start, this.end);

  final String text;
  final int start, end;
}
