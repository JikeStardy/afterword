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
