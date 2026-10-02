import 'dart:convert';

import '../core/models.dart';

class KnowledgeService {
  const KnowledgeService._();

  static List<Json> contentBlocksForItem(LibraryItem item) {
    final rawBlocks = item.toJson()['contentBlocks'];
    if (rawBlocks is List && rawBlocks.isNotEmpty) {
      return rawBlocks
          .whereType<Map>()
          .map((block) => _normalizeBlock(Map<String, dynamic>.from(block)))
          .where((block) => (block['text'] as String? ?? '').trim().isNotEmpty)
          .toList(growable: false);
    }
    final text = item.body.trim().isEmpty ? item.url.trim() : item.body.trim();
    if (text.isEmpty) return const <Json>[];
    final paragraphs = text
        .split(RegExp(r'\n{2,}'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    return [
      for (final entry in paragraphs.indexed)
        {
          'id': 'body-${entry.$1 + 1}',
          'kind': 'paragraph',
          'text': entry.$2,
          'sourceContext': 'legacy-body',
        },
    ];
  }

  static int contentVersionForItem(LibraryItem item) {
    final value = item.toJson()['contentVersion'];
    return value is int && value > 0 ? value : 1;
  }

  static Json _normalizeBlock(Json block) {
    final kind = block['kind'] as String? ?? 'paragraph';
    var text = (block['text'] as String? ?? '').trim();
    if (text.isEmpty && block['items'] is List) {
      text = (block['items'] as List)
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .join('\n');
    }
    if (text.isEmpty && block['rows'] is List) {
      text = (block['rows'] as List)
          .whereType<List>()
          .map((row) => row.map((cell) => cell.toString().trim()).join(' | '))
          .where((row) => row.trim().isNotEmpty)
          .join('\n');
    }
    if (text.isEmpty) text = (block['alt'] as String? ?? '').trim();
    return {
      ...block,
      'kind': kind == 'list' ? 'listItem' : kind,
      'text': text,
      if ((block['assetId'] as String? ?? '').isNotEmpty)
        'assetPath': block['assetId'],
    };
  }

  static Json itemPayload(LibraryItem item, {int? clipChars = 8000}) {
    var remaining = clipChars;
    var truncated = false;
    final blocks = <Json>[];
    // The budget belongs to the whole source, not to each paragraph. Null is
    // reserved for the current article, whose segmentation is caller-owned.
    for (final block in contentBlocksForItem(item)) {
      if (remaining == 0) {
        truncated = true;
        break;
      }
      var text = (block['text'] as String? ?? '').trim();
      if (remaining != null) {
        if (text.length > remaining) {
          text = text.substring(0, remaining);
          truncated = true;
        }
        remaining -= text.length;
      }
      blocks.add({
        'id': block['id'],
        'kind': block['kind'],
        if (block['level'] != null) 'level': block['level'],
        if (block['page'] != null) 'page': block['page'],
        'text': text,
        if ((block['sourceContext'] as String? ?? '').isNotEmpty)
          'sourceContext': block['sourceContext'],
        if ((block['imageUrl'] as String? ?? '').isNotEmpty)
          'imageUrl': block['imageUrl'],
        if ((block['assetPath'] as String? ?? '').isNotEmpty)
          'assetPath': block['assetPath'],
      });
    }
    return {
      'id': item.id,
      'title': item.title,
      'kind': item.kind.name,
      'url': item.url,
      'notes': item.notes,
      'annotations': item.annotations
          .map((annotation) => annotation.toJson())
          .toList(),
      'feedback': item.feedback,
      'contentVersion': contentVersionForItem(item),
      if (item.pdfPageCount != null) 'pdfPageCount': item.pdfPageCount,
      if (item.pdfPageCount != null)
        'providedPdfPages': {
          'first': item.pdfPageStart,
          'last': item.pdfPageEnd ?? item.pdfPageCount,
        },
      'contentBlocks': blocks,
      if (truncated) 'contentTruncated': true,
    };
  }

  static List<Json> contextEntriesForTopic(
    Topic topic, {
    bool confirmedOnly = false,
  }) {
    final raw = topic.toJson()['contextEntries'];
    if (raw is! List) return const <Json>[];
    return raw
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .where((entry) => (entry['text'] as String? ?? '').trim().isNotEmpty)
        .where((entry) => entry['active'] != false)
        .where((entry) => !confirmedOnly || entry['confirmed'] == true)
        .toList(growable: false);
  }

  static List<String>? selectedSourceIdsForTopic(Topic topic) {
    final raw = topic.toJson()['selectedSourceIds'];
    if (raw is! List) return null;
    return raw.whereType<String>().toList(growable: false);
  }

  static List<String>? selectedContextIdsForTopic(Topic topic) {
    final raw = topic.toJson()['selectedContextIds'];
    if (raw is! List) return null;
    return raw.whereType<String>().toList(growable: false);
  }

  static List<Json> structuredInsights(Analysis analysis) {
    final raw = analysis.toJson()['structuredInsights'];
    if (raw is! List) return const <Json>[];
    return raw
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: false);
  }

  static ReadingPresentation? parseReadingPresentation(Object? raw) {
    if (raw is! Map) return null;
    final value = Map<String, dynamic>.from(raw);
    final brief = value['brief'];
    final sections = value['sections'];
    if (brief is! String || sections is! List) return null;
    final parsedSections = <ReadingSection>[];
    for (final rawSection in sections) {
      if (rawSection is! Map) return null;
      final section = Map<String, dynamic>.from(rawSection);
      final title = section['title'];
      final body = section['body'];
      if (title is! String || body is! String) return null;
      if (title.trim().isNotEmpty || body.trim().isNotEmpty) {
        parsedSections.add(ReadingSection(title: title, body: body));
      }
    }
    if (!parsedSections.any((section) => section.body.trim().isNotEmpty)) {
      return null;
    }
    final presentation = ReadingPresentation(
      brief: brief,
      sections: parsedSections,
    );
    return presentation.isEmpty ? null : presentation;
  }

  static String rawReadingPresentationText(Object? raw) {
    if (raw is! Map) return '';
    final value = Map<String, dynamic>.from(raw);
    final buffer = StringBuffer();
    void add(Object? text) {
      if (text is String && text.trim().isNotEmpty) {
        buffer
          ..writeln(text.trim())
          ..writeln();
      }
    }

    add(value['brief']);
    final sections = value['sections'];
    if (sections is List) {
      for (final rawSection in sections) {
        if (rawSection is! Map) continue;
        final section = Map<String, dynamic>.from(rawSection);
        add(section['title']);
        add(section['body']);
      }
    }
    return buffer.toString().trimRight();
  }

  static void validateStructuredInsights(
    Object? rawInsights,
    Map<String, LibraryItem> sources, {
    List<EvidenceAnchor>? availableEvidence,
  }) {
    if (rawInsights is! List) return;
    for (final raw in rawInsights) {
      if (raw is! Map) {
        throw const FormatException('模型返回了无效的结构化 insight');
      }
      final insight = Map<String, dynamic>.from(raw);
      for (final field in ['finding', 'change', 'impact']) {
        final value = insight[field];
        if (value is! String || value.trim().isEmpty) {
          throw FormatException('模型返回的 insight 缺少$field');
        }
      }
      final evidence = insight['evidence'];
      if (evidence is! List || evidence.isEmpty) {
        throw const FormatException('模型返回的 insight 缺少证据');
      }
      for (final rawAnchor in evidence) {
        if (rawAnchor is! Map) {
          throw const FormatException('模型返回了无效证据锚点');
        }
        final anchor = Map<String, dynamic>.from(rawAnchor);
        if (availableEvidence == null) {
          validateEvidenceAnchor(anchor, sources);
        } else {
          final candidate = EvidenceAnchor.fromJson(anchor);
          if (!sources.containsKey(candidate.sourceId) ||
              !availableEvidence.any(
                (proof) => _sameAvailableEvidence(proof, candidate),
              )) {
            throw const FormatException('综合分析只能复用分段分析已收集的原文证据');
          }
        }
      }
    }
  }

  static void validateEvidenceAnchor(
    Json anchor,
    Map<String, LibraryItem> sources,
  ) {
    final sourceId = anchor['sourceId'];
    if (sourceId is! String || !sources.containsKey(sourceId)) {
      throw const FormatException('模型返回了未提供的证据来源');
    }
    final unresolved = anchor['unresolved'] == true;
    final pdfPage = anchor['pdfPage'] ?? anchor['page'];
    final blockId = anchor['blockId'];
    if (unresolved) {
      final quote = (anchor['quote'] as String? ?? '').trim();
      if (quote.isEmpty) {
        if (_isUnverifiedPdfVisualAnchor(anchor, sources[sourceId]!)) return;
        throw const FormatException('未定位证据必须保留摘录');
      }
      return;
    }
    final source = sources[sourceId]!;
    if (pdfPage is int && pdfPage > 0) {
      if (source.kind != ItemKind.pdf) {
        throw const FormatException('PDF 页证据必须来自 PDF 资料');
      }
      if (source.pdfPageCount == null ||
          pdfPage > source.pdfPageCount! ||
          pdfPage < source.pdfPageStart ||
          pdfPage > (source.pdfPageEnd ?? source.pdfPageCount!)) {
        throw const FormatException('PDF 证据页未核实或超出实际页数');
      }
      return;
    }
    if (blockId is! String || blockId.trim().isEmpty) {
      throw const FormatException('证据必须定位到正文段落或 PDF 页');
    }
    final block = contentBlocksForItem(source)
        .where((candidate) => candidate['id'] == blockId)
        .firstOrNull;
    if (block == null) throw const FormatException('证据锚点不存在');
    final version = anchor['sourceVersion'];
    if (version is int && version != contentVersionForItem(source)) {
      throw const FormatException('证据引用了过期正文版本');
    }
    final quote = (anchor['quote'] as String? ?? '').trim();
    if (quote.isNotEmpty &&
        !normalizeQuote(block['text'] as String)
            .contains(normalizeQuote(quote))) {
      throw const FormatException('证据摘录与正文段落不一致');
    }
  }

  static String normalizeQuote(String text) =>
      text.replaceAll(RegExp(r'[\s\u00a0]+'), ' ').trim();

  static bool _sameAvailableEvidence(
    EvidenceAnchor proof,
    EvidenceAnchor candidate,
  ) =>
      proof.sourceId == candidate.sourceId &&
      proof.sourceVersion == candidate.sourceVersion &&
      proof.blockId == candidate.blockId &&
      proof.windowId == candidate.windowId &&
      proof.assetFingerprint == candidate.assetFingerprint &&
      proof.pdfPage == candidate.pdfPage &&
      proof.start == candidate.start &&
      proof.end == candidate.end &&
      proof.unresolved == candidate.unresolved &&
      normalizeQuote(proof.quote) == normalizeQuote(candidate.quote);

  static bool _isUnverifiedPdfVisualAnchor(Json anchor, LibraryItem source) {
    final assetFingerprint = (anchor['assetFingerprint'] as String? ?? '')
        .trim();
    if (assetFingerprint.isEmpty || source.kind != ItemKind.pdf) return false;
    final pdfPage = anchor['pdfPage'] ?? anchor['page'];
    if (pdfPage is! int || pdfPage <= 0) return false;
    final pageCount = source.pdfPageCount;
    if (pageCount == null) return false;
    return pdfPage >= source.pdfPageStart &&
        pdfPage <= (source.pdfPageEnd ?? pageCount) &&
        pdfPage <= pageCount;
  }

  static String exportItemMarkdown(
    LibraryItem item, {
    String Function(String source)? labelForSource,
  }) {
    final buffer = StringBuffer()
      ..writeln('# ${item.title}')
      ..writeln()
      ..writeln('- 类型：${item.kind.name}')
      ..writeln('- 来源：${item.url.isEmpty ? item.id : item.url}')
      ..writeln();
    if (item.notes.trim().isNotEmpty) {
      buffer
        ..writeln('## 笔记')
        ..writeln()
        ..writeln(item.notes.trim())
        ..writeln();
    }
    final analysis = item.analysis;
    if (analysis != null) {
      buffer
        ..writeln('## Insight')
        ..writeln()
        ..writeln(
          analysis.brief.trim().isEmpty
              ? analysis.summary.trim()
              : analysis.brief.trim(),
        )
        ..writeln();
      if (analysis.brief.trim().isNotEmpty &&
          analysis.summary.trim().isNotEmpty) {
        buffer
          ..writeln('### 完整分析')
          ..writeln()
          ..writeln(analysis.summary.trim())
          ..writeln();
      }
      for (final insight in structuredInsights(analysis)) {
        final heading = (insight['title'] as String? ?? '').trim().isEmpty
            ? (insight['finding'] ?? '发现').toString()
            : insight['title'].toString();
        buffer
          ..writeln('### $heading')
          ..writeln()
          ..writeln('${insight['finding'] ?? '未说明'}')
          ..writeln()
          ..writeln('- 变化：${insight['change'] ?? '未说明'}')
          ..writeln('- 个人影响：${insight['impact'] ?? '未说明'}')
          ..writeln('- 未知：${_listText(insight['unknowns'])}')
          ..writeln(
            '- 证据：${_evidenceText(insight['evidence'], labelForSource)}',
          )
          ..writeln();
      }
      if (analysis.insights.isNotEmpty) {
        for (final line in analysis.insights) {
          buffer.writeln('- $line');
        }
        buffer.writeln();
      }
      if (analysis.sourceIds.isNotEmpty) {
        buffer
          ..writeln('## 来源')
          ..writeln();
        for (final id in analysis.sourceIds) {
          buffer.writeln('- ${labelForSource?.call(id) ?? id} [$id]');
        }
      }
    }
    return buffer.toString().trimRight();
  }

  static String exportTopicMarkdown(
    Topic topic, {
    String Function(String source)? labelForSource,
  }) {
    final buffer = StringBuffer()
      ..writeln('# ${topic.title}')
      ..writeln()
      ..writeln(topic.question)
      ..writeln();
    final context = contextEntriesForTopic(topic);
    if (context.isNotEmpty) {
      buffer
        ..writeln('## Context')
        ..writeln();
      for (final entry in context) {
        final confirmed = entry['confirmed'] == true
            ? 'confirmed'
            : 'suggested';
        buffer.writeln(
          '- ${entry['kind'] ?? 'background'} · $confirmed：${entry['text']}',
        );
      }
      buffer.writeln();
    }
    final presentation = topic.presentation;
    if (presentation != null && !presentation.isEmpty) {
      buffer
        ..writeln('## 综述')
        ..writeln()
        ..writeln(presentation.brief.trim())
        ..writeln();
      for (final section in presentation.sections) {
        if (section.title.trim().isNotEmpty) {
          buffer
            ..writeln('### ${section.title.trim()}')
            ..writeln();
        }
        if (section.body.trim().isNotEmpty) {
          buffer
            ..writeln(section.body.trim())
            ..writeln();
        }
      }
    } else if (topic.overview.trim().isNotEmpty) {
      buffer
        ..writeln('## 综述')
        ..writeln()
        ..writeln(topic.overview.trim())
        ..writeln();
    }
    if (topic.sourceIds.isNotEmpty) {
      buffer
        ..writeln('## 来源')
        ..writeln();
      for (final id in topic.sourceIds) {
        buffer.writeln('- ${labelForSource?.call(id) ?? id} [$id]');
      }
    }
    return buffer.toString().trimRight();
  }

  static String _evidenceText(
    Object? evidence,
    String Function(String source)? labelForSource,
  ) {
    if (evidence is! List || evidence.isEmpty) return '未定位';
    return evidence
        .whereType<Map>()
        .map((raw) {
          final anchor = Map<String, dynamic>.from(raw);
          final source = anchor['sourceId'] as String? ?? 'unknown';
          final label = labelForSource?.call(source) ?? source;
          if (anchor['unresolved'] == true) {
            return '$label：未定位摘录「${anchor['quote'] ?? ''}」';
          }
          final page = anchor['pdfPage'] ?? anchor['page'];
          if (page is int) return '$label：PDF 第 $page 页';
          return '$label：段落 ${anchor['blockId'] ?? '未知'}';
        })
        .join('；');
  }

  static String _listText(Object? value) {
    if (value is! List || value.isEmpty) return '无';
    return value.map((entry) => entry.toString()).join('；');
  }

  static String encodeMarkdownFileName(String title, String fallback) {
    final normalized = title
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '-')
        .replaceAll(RegExp(r'\s+'), '-');
    return '${normalized.isEmpty ? fallback : normalized}.md';
  }

  static String prettyJson(Object value) =>
      const JsonEncoder.withIndent('  ').convert(value);
}
