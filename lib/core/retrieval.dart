import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../services/knowledge_service.dart';
import 'models.dart';

class SearchHit {
  const SearchHit({
    required this.type,
    required this.id,
    required this.title,
    required this.snippet,
    required this.score,
  });
  final String type, id, title, snippet;
  final int score;
}

Set<String> searchTerms(String text) {
  final normalized = text.toLowerCase();
  final result = RegExp(r'[a-z0-9]+')
      .allMatches(normalized)
      .map((match) => match[0]!)
      .toSet();
  for (final match in RegExp(r'[\u4e00-\u9fff]+').allMatches(normalized)) {
    final chars = match[0]!;
    if (chars.length == 1) result.add(chars);
    for (var i = 0; i < chars.length - 1; i++) {
      result.add(chars.substring(i, i + 2));
    }
  }
  return result;
}

int relevance(String query, String text, {String title = ''}) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return 0;
  final haystack = text.toLowerCase();
  final terms = searchTerms(needle);
  return (haystack.contains(needle) ? 20 : 0) +
      (title.toLowerCase().contains(needle) ? 30 : 0) +
      terms.intersection(searchTerms(haystack)).length * 2 +
      terms.intersection(searchTerms(title)).length * 4;
}

String itemSearchText(LibraryItem item) => [
  item.title,
  item.body,
  item.notes,
  for (final block in item.contentBlocks) ...[
    block.text,
    block.items.join('\n'),
    block.rows.map((row) => row.join('\t')).join('\n'),
    block.alt,
  ],
  for (final annotation in item.annotations) ...[
    annotation.highlightedText,
    annotation.note,
    annotation.anchor.quote,
    annotation.anchor.note,
  ],
  if (item.analysis case final analysis?) ...[
    analysis.summary,
    ...analysis.insights,
    ...analysis.connections,
    ...analysis.questions,
    for (final insight in analysis.structuredInsights) ...[
      insight.finding,
      insight.change,
      insight.impact,
      ...insight.unknowns,
      for (final anchor in insight.evidence) ...[anchor.quote, anchor.note],
    ],
  ],
].join('\n');

String _sha256Text(String value) =>
    sha256.convert(utf8.encode(value)).toString();

String sourceFingerprint(LibraryItem item) {
  final payload = <String, dynamic>{
    'title': item.title,
    'url': item.url,
    'contentVersion': item.contentVersion,
    'body': item.body,
    'bodyOrigin': item.bodyOrigin,
    'notes': item.notes,
    'feedback': item.feedback,
    'assets': item.assets
        .map((asset) => {'name': asset.name, 'mime': asset.mime})
        .toList(),
    'contentBlocks': item.contentBlocks.map(_blockFingerprintJson).toList(),
    'contentHistory': item.contentHistory
        .map(
          (revision) => {
            'version': revision.version,
            'title': revision.title,
            'body': revision.body,
            'bodyOrigin': revision.bodyOrigin,
            'blocks': revision.blocks.map(_blockFingerprintJson).toList(),
          },
        )
        .toList(),
    'annotations': item.annotations.map((a) => a.toJson()).toList(),
    'analysis': item.analysis?.toJson(),
  };
  return _sha256Text(jsonEncode(payload));
}

Json _blockFingerprintJson(ContentBlock block) => {
  'id': block.id,
  'kind': block.kind.name,
  'text': block.text,
  'level': block.level,
  'items': block.items,
  'rows': block.rows,
  'alt': block.alt,
};

class _BlockText {
  _BlockText({required this.id, required this.text});
  final String id, text;
}

class _WindowCandidate {
  _WindowCandidate({
    required this.item,
    required this.block,
    required this.start,
    required this.end,
    required this.score,
  });
  final LibraryItem item;
  final _BlockText block;
  final int start, end, score;
}

List<_BlockText> _sourceBlocks(LibraryItem item) {
  return KnowledgeService.contentBlocksForItem(item)
      .map(
        (block) => _BlockText(
          id: block['id'] as String? ?? '',
          text: block['text'] as String? ?? '',
        ),
      )
      .where((block) => block.id.isNotEmpty && block.text.trim().isNotEmpty)
      .toList(growable: false);
}

int _safeStart(String text, int value) {
  final index = value.clamp(0, text.length);
  if (index > 0 &&
      index < text.length &&
      _isLowSurrogate(text.codeUnitAt(index)) &&
      _isHighSurrogate(text.codeUnitAt(index - 1))) {
    return index + 1;
  }
  return index;
}

int _safeEnd(String text, int value) {
  final index = value.clamp(0, text.length);
  if (index > 0 &&
      index < text.length &&
      _isLowSurrogate(text.codeUnitAt(index)) &&
      _isHighSurrogate(text.codeUnitAt(index - 1))) {
    return index - 1;
  }
  return index;
}

bool _isHighSurrogate(int codeUnit) => codeUnit >= 0xd800 && codeUnit <= 0xdbff;
bool _isLowSurrogate(int codeUnit) => codeUnit >= 0xdc00 && codeUnit <= 0xdfff;

void _validateRange(String text, int start, int end) {
  if (start < 0 || end < start || end > text.length || start == end) {
    throw RangeError.range(start, 0, text.length, 'start');
  }
  if (start > 0 &&
      start < text.length &&
      _isLowSurrogate(text.codeUnitAt(start)) &&
      _isHighSurrogate(text.codeUnitAt(start - 1))) {
    throw RangeError.value(start, 'start', 'splits a surrogate pair');
  }
  if (end > 0 &&
      end < text.length &&
      _isLowSurrogate(text.codeUnitAt(end)) &&
      _isHighSurrogate(text.codeUnitAt(end - 1))) {
    throw RangeError.value(end, 'end', 'splits a surrogate pair');
  }
}

String _windowId(
  LibraryItem item,
  String blockId,
  int sourceVersion,
  int start,
  int end,
  String fingerprint,
) =>
    '${item.id}:$sourceVersion:$blockId:$start:$end:${fingerprint.substring(0, 12)}';

SourceWindow _windowFor(
  LibraryItem item,
  String blockId,
  String text,
  int start,
  int end, {
  String readActionId = '',
}) {
  _validateRange(text, start, end);
  final selected = text.substring(start, end);
  final fingerprint = _sha256Text(selected);
  final version = KnowledgeService.contentVersionForItem(item);
  return SourceWindow(
    id: _windowId(item, blockId, version, start, end, fingerprint),
    sourceId: item.id,
    sourceVersion: version,
    blockId: blockId,
    start: start,
    end: end,
    text: selected,
    fingerprint: fingerprint,
    readActionId: readActionId,
  );
}

SourceWindow readSourceWindow(
  LibraryItem item,
  String blockId,
  int start,
  int end, {
  String readActionId = '',
}) {
  final block = _sourceBlocks(item).where((b) => b.id == blockId).firstOrNull;
  if (block == null) throw const FormatException('正文段落不存在');
  return _windowFor(
    item,
    block.id,
    block.text,
    start,
    end,
    readActionId: readActionId,
  );
}

List<SourceWindow> retrieveSourceWindows(
  List<LibraryItem> sources,
  String query, {
  int charBudget = 12000,
  Set<String> excludeWindowIds = const {},
}) {
  if (charBudget <= 0 || sources.isEmpty) return const [];
  final trimmedQuery = query.trim();
  final queryTerms = searchTerms(trimmedQuery);
  final candidates = <_WindowCandidate>[];
  const targetWindow = 900;
  const contextRadius = 420;

  for (final item in sources) {
    for (final block in _sourceBlocks(item)) {
      final text = block.text;
      final lowered = text.toLowerCase();
      final exact = trimmedQuery.isEmpty
          ? -1
          : lowered.indexOf(trimmedQuery.toLowerCase());
      final termPositions = queryTerms
          .map(lowered.indexOf)
          .where((position) => position >= 0)
          .toList();
      final anchors = <int>{
        if (exact >= 0) exact,
        ...termPositions,
        if (exact < 0 && termPositions.isEmpty) 0,
      }.toList()..sort();
      for (final anchor in anchors.take(3)) {
        final rawStart = text.length <= targetWindow
            ? 0
            : anchor - contextRadius;
        final start = _safeStart(text, rawStart);
        final end = _safeEnd(
          text,
          text.length <= targetWindow ? text.length : start + targetWindow,
        );
        if (end <= start) continue;
        final score =
            relevance(
              trimmedQuery,
              text.substring(start, end),
              title: item.title,
            ) +
            relevance(trimmedQuery, item.title, title: item.title);
        candidates.add(
          _WindowCandidate(
            item: item,
            block: block,
            start: start,
            end: end,
            score: score,
          ),
        );
      }
    }
  }

  candidates.sort((a, b) {
    final score = b.score.compareTo(a.score);
    if (score != 0) return score;
    final source = a.item.id.compareTo(b.item.id);
    if (source != 0) return source;
    final block = a.block.id.compareTo(b.block.id);
    if (block != 0) return block;
    return a.start.compareTo(b.start);
  });

  final windows = <SourceWindow>[];
  final usedRanges = <String, List<(int, int)>>{};
  var remaining = charBudget;
  for (final candidate in candidates) {
    if (remaining <= 0) break;
    var start = candidate.start;
    var end = candidate.end;
    final key = '${candidate.item.id}:${candidate.block.id}';
    final ranges = usedRanges.putIfAbsent(key, () => []);
    final overlaps = ranges.any((range) => start < range.$2 && end > range.$1);
    if (overlaps) continue;
    if (end - start > remaining) {
      end = _safeEnd(candidate.block.text, start + remaining);
      if (end <= start) continue;
    }
    final window = _windowFor(
      candidate.item,
      candidate.block.id,
      candidate.block.text,
      start,
      end,
    );
    if (excludeWindowIds.contains(window.id)) continue;
    windows.add(window);
    ranges.add((start, end));
    remaining -= window.text.length;
  }
  return windows;
}

String searchSnippet(String text, String query, {int length = 150}) {
  final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final lowered = compact.toLowerCase();
  var position = lowered.indexOf(query.trim().toLowerCase());
  if (position < 0) {
    final matches = searchTerms(query)
        .map(lowered.indexOf)
        .where((index) => index >= 0);
    position = matches.isEmpty ? 0 : matches.reduce((a, b) => a < b ? a : b);
  }
  final start = (position - 35).clamp(0, compact.length);
  final end = (start + length).clamp(start, compact.length);
  return '${start > 0 ? '…' : ''}${compact.substring(start, end)}${end < compact.length ? '…' : ''}';
}

List<SearchHit> searchLibrary(
  AppData data,
  String query, {
  bool Function(LibraryItem)? includeItem,
}) {
  if (query.trim().isEmpty) return [];
  final hits = <SearchHit>[];
  void add(String type, String id, String title, String text) {
    final score = relevance(query, text, title: title);
    if (score > 0) {
      hits.add(
        SearchHit(
          type: type,
          id: id,
          title: title,
          snippet: searchSnippet(text, query),
          score: score,
        ),
      );
    }
  }

  for (final item in data.items) {
    if (includeItem?.call(item) ?? !item.isTrashed) {
      add('item', item.id, item.title, itemSearchText(item));
    }
  }
  for (final topic in data.topics) {
    add(
      'topic',
      topic.id,
      topic.title,
      [
        topic.question,
        topic.overview,
        topic.reason,
        for (final context in topic.contextEntries)
          if (context.active) context.text,
      ].join('\n'),
    );
  }
  for (final run in data.runs) {
    add('run', run.id, run.goal, run.report);
  }
  hits.sort((a, b) {
    final score = b.score.compareTo(a.score);
    return score != 0 ? score : a.id.compareTo(b.id);
  });
  return hits;
}

/// Strip known marketing parameters only; meaningful query values are retained.
String normalizedCaptureUrl(String value) {
  final uri = Uri.parse(value.trim());
  final query = <String, dynamic>{};
  for (final key in uri.queryParametersAll.keys.toList()..sort()) {
    final lower = key.toLowerCase();
    if (lower.startsWith('utm_') ||
        const {'fbclid', 'gclid', 'dclid', 'msclkid'}.contains(lower)) {
      continue;
    }
    query[key] = uri.queryParametersAll[key]!;
  }
  return uri
      .replace(
        scheme: uri.scheme.toLowerCase(),
        host: uri.host.toLowerCase(),
        path: uri.path.isEmpty ? '/' : uri.path,
        queryParameters: query.isEmpty ? null : query,
        query: query.isEmpty ? '' : null,
        fragment: '',
      )
      .toString();
}
