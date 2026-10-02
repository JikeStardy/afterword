import 'dart:math';

part 'knowledge_models.dart';

typedef Json = Map<String, dynamic>;
String newId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${Random.secure().nextInt(1 << 32).toRadixString(36)}';
List<String> strings(dynamic value) =>
    (value as List? ?? []).whereType<String>().toList();
DateTime? date(dynamic value) =>
    value is String ? DateTime.tryParse(value) : null;
Json json(dynamic value) => Map<String, dynamic>.from(value as Map);
double doubleValue(dynamic value, double fallback) =>
    value is num ? value.toDouble() : fallback;

T enumValue<T extends Enum>(List<T> values, dynamic value, T fallback) {
  if (value is! String) return fallback;
  for (final item in values) {
    if (item.name == value) return item;
  }
  return fallback;
}

enum ItemKind { web, text, image, pdf }

enum WorkState { pending, reading, done, snoozed }

enum ContentBlockKind { heading, paragraph, list, code, table, image }

enum ReadingPreset { editorial, compact, magazine }

class ReadingSection {
  String title, body;
  ReadingSection({this.title = '', this.body = ''});
  Json toJson() => {'title': title, 'body': body};
  factory ReadingSection.fromJson(Json j) => ReadingSection(
    title: j['title'] as String? ?? '',
    body: j['body'] as String? ?? '',
  );
}

class ReadingPresentation {
  String brief;
  List<ReadingSection> sections;
  ReadingPresentation({this.brief = '', List<ReadingSection>? sections})
    : sections = sections ?? [];
  bool get isEmpty =>
      brief.trim().isEmpty && sections.every((s) => s.body.trim().isEmpty);
  String get fullText {
    final buffer = StringBuffer();
    if (brief.trim().isNotEmpty) {
      buffer
        ..writeln(brief.trim())
        ..writeln();
    }
    for (final section in sections) {
      if (section.title.trim().isNotEmpty) {
        buffer
          ..writeln(section.title.trim())
          ..writeln();
      }
      if (section.body.trim().isNotEmpty) {
        buffer
          ..writeln(section.body.trim())
          ..writeln();
      }
    }
    return buffer.toString().trimRight();
  }

  Json toJson() => {
    'brief': brief,
    'sections': sections.map((section) => section.toJson()).toList(),
  };
  factory ReadingPresentation.fromJson(Json j) => ReadingPresentation(
    brief: j['brief'] as String? ?? '',
    sections: (j['sections'] as List? ?? [])
        .map((section) => ReadingSection.fromJson(json(section)))
        .where(
          (section) =>
              section.title.trim().isNotEmpty || section.body.trim().isNotEmpty,
        )
        .toList(),
  );
}

class ContentBlock {
  String id, text;
  ContentBlockKind kind;
  int level;
  List<String> items;
  List<List<String>> rows;
  String assetId, alt;
  ContentBlock({
    required this.id,
    required this.kind,
    this.text = '',
    this.level = 0,
    List<String>? items,
    List<List<String>>? rows,
    this.assetId = '',
    this.alt = '',
  }) : items = items ?? [],
       rows = rows ?? [];
  Json toJson() => {
    'id': id,
    'kind': kind.name,
    'text': text,
    'level': level,
    'items': items,
    'rows': rows,
    'assetId': assetId,
    'alt': alt,
  };
  factory ContentBlock.fromJson(Json j) => ContentBlock(
    id: j['id'] as String,
    kind: enumValue(
      ContentBlockKind.values,
      j['kind'],
      ContentBlockKind.paragraph,
    ),
    text: j['text'] as String? ?? '',
    level: j['level'] as int? ?? 0,
    items: strings(j['items']),
    rows: (j['rows'] as List? ?? [])
        .map((row) => strings(row))
        .where((row) => row.isNotEmpty)
        .toList(),
    assetId: j['assetId'] as String? ?? '',
    alt: j['alt'] as String? ?? '',
  );
}

class ReadingPosition {
  String blockId;
  int offset;
  int? pdfPage;
  ReadingPosition({this.blockId = '', this.offset = 0, this.pdfPage});
  Json toJson() => {'blockId': blockId, 'offset': offset, 'pdfPage': pdfPage};
  factory ReadingPosition.fromJson(Json j) => ReadingPosition(
    blockId: j['blockId'] as String? ?? '',
    offset: j['offset'] as int? ?? 0,
    pdfPage: j['pdfPage'] as int?,
  );
}

class EvidenceAnchor {
  String sourceId, blockId, quote, note;
  String? windowId, assetFingerprint;
  int? sourceVersion, start, end, pdfPage;
  bool unresolved;
  EvidenceAnchor({
    this.sourceId = '',
    this.sourceVersion,
    this.blockId = '',
    this.windowId,
    this.assetFingerprint,
    this.start,
    this.end,
    this.pdfPage,
    this.quote = '',
    this.note = '',
    this.unresolved = false,
  });
  Json toJson() => {
    'sourceId': sourceId,
    'sourceVersion': sourceVersion,
    'blockId': blockId,
    'windowId': windowId,
    'assetFingerprint': assetFingerprint,
    'start': start,
    'end': end,
    'pdfPage': pdfPage,
    'quote': quote,
    'note': note,
    'unresolved': unresolved,
  };
  factory EvidenceAnchor.fromJson(Json j) => EvidenceAnchor(
    sourceId: j['sourceId'] as String? ?? '',
    sourceVersion: j['sourceVersion'] as int?,
    blockId: j['blockId'] as String? ?? '',
    windowId: j['windowId'] as String?,
    assetFingerprint: j['assetFingerprint'] as String?,
    start: j['start'] as int?,
    end: j['end'] as int?,
    pdfPage: j['pdfPage'] as int?,
    quote: j['quote'] as String? ?? '',
    note: j['note'] as String? ?? '',
    unresolved: j['unresolved'] as bool? ?? false,
  );
}

class Annotation {
  String id, note, highlightedText;
  EvidenceAnchor anchor;
  DateTime createdAt, updatedAt;
  Annotation({
    required this.id,
    required this.anchor,
    this.note = '',
    this.highlightedText = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now();
  Json toJson() => {
    'id': id,
    'anchor': anchor.toJson(),
    'note': note,
    'highlightedText': highlightedText,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
  factory Annotation.fromJson(Json j) => Annotation(
    id: j['id'] as String,
    anchor: EvidenceAnchor.fromJson(json(j['anchor'] ?? {})),
    note: j['note'] as String? ?? '',
    highlightedText: j['highlightedText'] as String? ?? '',
    createdAt: date(j['createdAt']),
    updatedAt: date(j['updatedAt']),
  );
}

class Insight {
  String id, title, finding, change, impact, verdict;
  List<EvidenceAnchor> evidence;
  List<String> unknowns;
  bool stale;
  Insight({
    required this.id,
    this.title = '',
    this.finding = '',
    this.change = '',
    this.impact = '',
    List<EvidenceAnchor>? evidence,
    List<String>? unknowns,
    this.verdict = '',
    this.stale = false,
  }) : evidence = evidence ?? [],
       unknowns = unknowns ?? [];
  Json toJson() => {
    'id': id,
    'title': title,
    'finding': finding,
    'change': change,
    'impact': impact,
    'evidence': evidence.map((e) => e.toJson()).toList(),
    'unknowns': unknowns,
    'verdict': verdict,
    'stale': stale,
  };
  factory Insight.fromJson(Json j) => Insight(
    id: j['id'] as String,
    title: j['title'] as String? ?? '',
    finding: j['finding'] as String? ?? '',
    change: j['change'] as String? ?? '',
    impact: j['impact'] as String? ?? '',
    evidence: (j['evidence'] as List? ?? [])
        .map((e) => EvidenceAnchor.fromJson(json(e)))
        .toList(),
    unknowns: strings(j['unknowns']),
    verdict: j['verdict'] as String? ?? '',
    stale: j['stale'] as bool? ?? false,
  );
}

class Asset {
  String path, name, mime;
  Asset({required this.path, required this.name, required this.mime});
  Json toJson() => {'path': path, 'name': name, 'mime': mime};
  factory Asset.fromJson(Json j) => Asset(
    path: j['path'] as String,
    name: j['name'] as String,
    mime: j['mime'] as String,
  );
}

class Analysis {
  String summary, brief;
  bool stale;
  List<String> insights, connections, questions, sourceIds, suggestedTopics;
  List<Insight> structuredInsights;
  List<String>? inputItemIds;
  DateTime createdAt;
  Analysis({
    this.summary = '',
    this.brief = '',
    this.stale = false,
    this.inputItemIds,
    List<String>? insights,
    List<String>? connections,
    List<String>? questions,
    List<String>? sourceIds,
    List<String>? suggestedTopics,
    List<Insight>? structuredInsights,
    DateTime? createdAt,
  }) : insights = insights ?? [],
       connections = connections ?? [],
       questions = questions ?? [],
       sourceIds = sourceIds ?? [],
       suggestedTopics = suggestedTopics ?? [],
       structuredInsights = structuredInsights ?? [],
       createdAt = createdAt ?? DateTime.now();
  Json toJson() => {
    'summary': summary,
    'brief': brief,
    'stale': stale,
    'inputItemIds': inputItemIds,
    'insights': insights,
    'connections': connections,
    'questions': questions,
    'sourceIds': sourceIds,
    'suggestedTopics': suggestedTopics,
    'structuredInsights': structuredInsights.map((i) => i.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
  };
  factory Analysis.fromJson(Json j, {bool migrateLegacyHighlights = true}) {
    final structuredInsights = (j['structuredInsights'] as List? ?? [])
        .map((i) => Insight.fromJson(json(i)))
        .toList();
    return Analysis(
      summary: j['summary'] as String? ?? '',
      brief: j['brief'] as String? ?? '',
      stale: j['stale'] as bool? ?? false,
      inputItemIds: j['inputItemIds'] == null
          ? null
          : strings(j['inputItemIds']),
      insights: strings(j['insights']),
      connections: strings(j['connections']),
      questions: strings(j['questions']),
      sourceIds: strings(j['sourceIds']),
      suggestedTopics: strings(j['suggestedTopics']),
      structuredInsights:
          structuredInsights.isNotEmpty || !migrateLegacyHighlights
          ? structuredInsights
          : _legacyHighlights(j['highlights']),
      createdAt: date(j['createdAt']),
    );
  }
}

List<Insight> _legacyHighlights(dynamic value) {
  final highlights = value is List ? value : const [];
  return [
    for (final (index, highlight) in highlights.indexed)
      if (highlight is Map)
        _legacyHighlight(index, Map<String, dynamic>.from(highlight)),
  ];
}

Insight _legacyHighlight(int index, Json highlight) {
  return Insight(
    id: 'legacy-highlight-$index',
    title: highlight['title'] as String? ?? '',
    finding: highlight['explanation'] as String? ?? '',
    evidence: _legacyEvidence(highlight['evidence']),
  );
}

List<EvidenceAnchor> _legacyEvidence(dynamic value) {
  final evidence = value is List ? value : const [];
  return [
    for (final item in evidence)
      if (item is Map) _legacyEvidenceAnchor(Map<String, dynamic>.from(item)),
  ];
}

EvidenceAnchor _legacyEvidenceAnchor(Json evidence) {
  final sourceVersion = evidence['sourceVersion'] as int?;
  final blockId = evidence['blockId'] as String? ?? '';
  final unresolved = sourceVersion == null || blockId.isEmpty;
  return EvidenceAnchor(
    sourceId: evidence['sourceId'] as String? ?? '',
    sourceVersion: sourceVersion,
    blockId: blockId,
    pdfPage: evidence['pdfPage'] as int? ?? evidence['page'] as int?,
    quote: evidence['quote'] as String? ?? '',
    note: unresolved ? '旧版观点摘录缺少来源版本或段落定位，需核对。' : '',
    unresolved: unresolved,
  );
}

class ContentRevision {
  final int version;
  final String title, body, bodyOrigin;
  final List<ContentBlock> blocks;
  final DateTime savedAt;
  ContentRevision({
    required this.version,
    required this.title,
    required this.body,
    required this.blocks,
    this.bodyOrigin = '',
    DateTime? savedAt,
  }) : savedAt = savedAt ?? DateTime.now();
  Json toJson() => {
    'version': version,
    'title': title,
    'body': body,
    'blocks': blocks.map((block) => block.toJson()).toList(),
    'bodyOrigin': bodyOrigin,
    'savedAt': savedAt.toIso8601String(),
  };
  factory ContentRevision.fromJson(Json j) => ContentRevision(
    version: j['version'] as int,
    title: j['title'] as String,
    body: j['body'] as String,
    bodyOrigin: j['bodyOrigin'] as String? ?? '',
    blocks: (j['blocks'] as List? ?? [])
        .map((block) => ContentBlock.fromJson(json(block)))
        .toList(),
    savedAt: date(j['savedAt']),
  );
}

class LibraryItem {
  String id, title, url, body, notes, status, error, warning, bodyOrigin;
  ItemKind kind;
  List<Asset> assets;
  Analysis? analysis;
  DateTime createdAt;
  DateTime? archivedAt, trashedAt;
  WorkState workState;
  DateTime? snoozedUntil;
  int contentVersion;
  int? pdfPageCount, pdfPageEnd;
  int pdfPageStart;
  List<ContentBlock> contentBlocks;
  List<ContentRevision> contentHistory;
  ReadingPosition? readingPosition;
  double readerFontScale;
  List<Annotation> annotations;
  bool get isArchived => archivedAt != null;
  bool get isTrashed => trashedAt != null;
  bool get isActive => !isArchived && !isTrashed;
  int readCount, feedback, researchAdoptions;
  LibraryItem({
    required this.id,
    required this.title,
    required this.kind,
    this.url = '',
    this.body = '',
    this.bodyOrigin = '',
    this.notes = '',
    this.status = 'saved',
    this.error = '',
    this.warning = '',
    List<Asset>? assets,
    this.analysis,
    this.archivedAt,
    this.trashedAt,
    DateTime? createdAt,
    this.readCount = 0,
    this.feedback = 0,
    this.researchAdoptions = 0,
    this.workState = WorkState.pending,
    this.snoozedUntil,
    this.contentVersion = 1,
    this.pdfPageCount,
    this.pdfPageStart = 1,
    this.pdfPageEnd,
    List<ContentBlock>? contentBlocks,
    List<ContentRevision>? contentHistory,
    this.readingPosition,
    this.readerFontScale = 1.0,
    List<Annotation>? annotations,
  }) : assets = assets ?? [],
       contentBlocks = contentBlocks ?? [],
       contentHistory = contentHistory ?? [],
       annotations = annotations ?? [],
       createdAt = createdAt ?? DateTime.now();
  Json toJson() => {
    'id': id,
    'title': title,
    'url': url,
    'kind': kind.name,
    'bodyOrigin': bodyOrigin,
    'body': body,
    'notes': notes,
    'status': status,
    'error': error,
    'warning': warning,
    'assets': assets.map((a) => a.toJson()).toList(),
    'analysis': analysis?.toJson(),
    'archivedAt': archivedAt?.toIso8601String(),
    'trashedAt': trashedAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'readCount': readCount,
    'feedback': feedback,
    'researchAdoptions': researchAdoptions,
    'workState': workState.name,
    'snoozedUntil': snoozedUntil?.toIso8601String(),
    'contentVersion': contentVersion,
    'pdfPageCount': pdfPageCount,
    'pdfPageStart': pdfPageStart,
    'pdfPageEnd': pdfPageEnd,
    'contentBlocks': contentBlocks.map((b) => b.toJson()).toList(),
    'contentHistory': contentHistory
        .map((revision) => revision.toJson())
        .toList(),
    'readingPosition': readingPosition?.toJson(),
    'readerFontScale': readerFontScale,
    'annotations': annotations.map((a) => a.toJson()).toList(),
  };
  factory LibraryItem.fromJson(Json j) => LibraryItem(
    id: j['id'] as String,
    title: j['title'] as String,
    kind: ItemKind.values.byName(j['kind'] as String),
    url: j['url'] as String? ?? '',
    body: j['body'] as String? ?? '',
    bodyOrigin: j['bodyOrigin'] as String? ?? '',
    notes: j['notes'] as String? ?? '',
    status: j['status'] as String? ?? 'saved',
    error: j['error'] as String? ?? '',
    warning: j['warning'] as String? ?? '',
    assets: (j['assets'] as List? ?? [])
        .map((a) => Asset.fromJson(json(a)))
        .toList(),
    analysis: j['analysis'] == null
        ? null
        : Analysis.fromJson(json(j['analysis'])),
    createdAt: date(j['createdAt']),
    archivedAt: date(j['archivedAt']),
    trashedAt: date(j['trashedAt']),
    readCount: j['readCount'] as int? ?? 0,
    feedback: j['feedback'] as int? ?? 0,
    researchAdoptions: j['researchAdoptions'] as int? ?? 0,
    workState: enumValue(WorkState.values, j['workState'], WorkState.pending),
    snoozedUntil: date(j['snoozedUntil']),
    contentVersion: j['contentVersion'] as int? ?? 1,
    pdfPageCount: j['pdfPageCount'] as int?,
    pdfPageStart: j['pdfPageStart'] as int? ?? 1,
    pdfPageEnd: j['pdfPageEnd'] as int?,
    contentBlocks: (j['contentBlocks'] as List? ?? [])
        .map((b) => ContentBlock.fromJson(json(b)))
        .toList(),
    contentHistory: (j['contentHistory'] as List? ?? [])
        .map((revision) => ContentRevision.fromJson(json(revision)))
        .toList(),
    readingPosition: j['readingPosition'] == null
        ? null
        : ReadingPosition.fromJson(json(j['readingPosition'])),
    readerFontScale: doubleValue(j['readerFontScale'], 1.0),
    annotations: (j['annotations'] as List? ?? [])
        .map((a) => Annotation.fromJson(json(a)))
        .toList(),
  );
}

class ContextEntry {
  String id, kind, text;
  bool confirmed, active;
  String? sourceId;
  int? sourceVersion;
  DateTime updatedAt;
  ContextEntry({
    required this.id,
    required this.kind,
    required this.text,
    this.confirmed = false,
    this.sourceId,
    this.sourceVersion,
    DateTime? updatedAt,
    this.active = true,
  }) : updatedAt = updatedAt ?? DateTime.now();
  Json toJson() => {
    'id': id,
    'kind': kind,
    'text': text,
    'confirmed': confirmed,
    'sourceId': sourceId,
    'sourceVersion': sourceVersion,
    'updatedAt': updatedAt.toIso8601String(),
    'active': active,
  };
  factory ContextEntry.fromJson(Json j) => ContextEntry(
    id: j['id'] as String,
    kind: j['kind'] as String? ?? '',
    text: j['text'] as String? ?? '',
    confirmed: j['confirmed'] as bool? ?? false,
    sourceId: j['sourceId'] as String?,
    sourceVersion: j['sourceVersion'] as int?,
    updatedAt: date(j['updatedAt']),
    active: j['active'] as bool? ?? true,
  );
}

class Topic {
  String id, title, question, overview, reason, status, error, authorizedScope;
  String? currentKnowledgeRevisionId;
  List<String> sourceIds;
  List<String>? inputItemIds;
  List<String>? selectedSourceIds, selectedContextIds;
  List<ContextEntry> contextEntries;
  ReadingPresentation? presentation;
  bool automatic, tracking;
  int intervalHours, callLimit;
  DateTime? lastRun, nextRun, reviewAt, snoozedUntil;
  bool overviewStale;
  Topic({
    required this.id,
    required this.title,
    required this.question,
    this.overview = '',
    this.reason = '',
    this.status = 'idle',
    this.error = '',
    this.authorizedScope = '',
    this.currentKnowledgeRevisionId,
    List<String>? sourceIds,
    this.inputItemIds,
    this.selectedSourceIds,
    this.selectedContextIds,
    List<ContextEntry>? contextEntries,
    this.presentation,
    this.automatic = false,
    this.tracking = false,
    this.intervalHours = 24,
    this.callLimit = 6,
    this.lastRun,
    this.nextRun,
    this.reviewAt,
    this.snoozedUntil,
    this.overviewStale = false,
  }) : sourceIds = sourceIds ?? [],
       contextEntries = contextEntries ?? [];
  Json toJson() => {
    'id': id,
    'title': title,
    'question': question,
    'overview': overview,
    'reason': reason,
    'status': status,
    'error': error,
    'authorizedScope': authorizedScope,
    'currentKnowledgeRevisionId': currentKnowledgeRevisionId,
    'sourceIds': sourceIds,
    'inputItemIds': inputItemIds,
    'selectedSourceIds': selectedSourceIds,
    'selectedContextIds': selectedContextIds,
    'contextEntries': contextEntries.map((e) => e.toJson()).toList(),
    'presentation': presentation?.toJson(),
    'automatic': automatic,
    'tracking': tracking,
    'intervalHours': intervalHours,
    'callLimit': callLimit,
    'lastRun': lastRun?.toIso8601String(),
    'nextRun': nextRun?.toIso8601String(),
    'reviewAt': reviewAt?.toIso8601String(),
    'snoozedUntil': snoozedUntil?.toIso8601String(),
    'overviewStale': overviewStale,
  };
  factory Topic.fromJson(Json j) => Topic(
    id: j['id'] as String,
    title: j['title'] as String,
    question: j['question'] as String,
    overview: j['overview'] as String? ?? '',
    reason: j['reason'] as String? ?? '',
    status: j['status'] as String? ?? 'idle',
    error: j['error'] as String? ?? '',
    authorizedScope: j['authorizedScope'] as String? ?? '',
    currentKnowledgeRevisionId: j['currentKnowledgeRevisionId'] as String?,
    sourceIds: strings(j['sourceIds']),
    inputItemIds: j['inputItemIds'] == null ? null : strings(j['inputItemIds']),
    selectedSourceIds: j['selectedSourceIds'] != null
        ? strings(j['selectedSourceIds'])
        : null,
    selectedContextIds: j['selectedContextIds'] != null
        ? strings(j['selectedContextIds'])
        : null,
    contextEntries: (j['contextEntries'] as List? ?? [])
        .map((e) => ContextEntry.fromJson(json(e)))
        .toList(),
    presentation: j['presentation'] == null
        ? null
        : ReadingPresentation.fromJson(json(j['presentation'])),
    automatic: j['automatic'] as bool? ?? false,
    tracking: j['tracking'] as bool? ?? false,
    intervalHours: j['intervalHours'] as int? ?? 24,
    callLimit: j['callLimit'] as int? ?? 6,
    lastRun: date(j['lastRun']),
    nextRun: date(j['nextRun']),
    reviewAt: date(j['reviewAt']),
    snoozedUntil: date(j['snoozedUntil']),
    overviewStale: j['overviewStale'] as bool? ?? false,
  );
}

class Feed {
  String id, title, url, error;
  DateTime? refreshedAt;
  bool paused;
  Feed({
    required this.id,
    required this.url,
    this.title = '',
    this.error = '',
    this.refreshedAt,
    this.paused = false,
  });
  Json toJson() => {
    'id': id,
    'url': url,
    'title': title,
    'error': error,
    'refreshedAt': refreshedAt?.toIso8601String(),
    'paused': paused,
  };
  factory Feed.fromJson(Json j) => Feed(
    id: j['id'] as String,
    url: j['url'] as String,
    title: j['title'] as String? ?? '',
    error: j['error'] as String? ?? '',
    refreshedAt: date(j['refreshedAt']),
    paused: j['paused'] as bool? ?? false,
  );
}

class FeedEntry {
  String id, feedId, title, url, summary;
  String? savedItemId;
  DateTime? publishedAt;
  bool processed, skipped;
  FeedEntry({
    required this.id,
    required this.feedId,
    required this.title,
    required this.url,
    this.summary = '',
    this.savedItemId,
    this.publishedAt,
    this.processed = false,
    this.skipped = false,
  });
  Json toJson() => {
    'id': id,
    'feedId': feedId,
    'title': title,
    'url': url,
    'summary': summary,
    'savedItemId': savedItemId,
    'publishedAt': publishedAt?.toIso8601String(),
    'processed': processed,
    'skipped': skipped,
  };
  factory FeedEntry.fromJson(Json j) => FeedEntry(
    id: j['id'] as String,
    feedId: j['feedId'] as String,
    title: j['title'] as String,
    url: j['url'] as String,
    summary: j['summary'] as String? ?? '',
    savedItemId: j['savedItemId'] as String?,
    publishedAt: date(j['publishedAt']),
    processed: j['processed'] as bool? ?? false,
    skipped: j['skipped'] as bool? ?? false,
  );
}

class ResearchSource {
  String id, title, url, snippet;
  ResearchSource({
    required this.id,
    required this.title,
    required this.url,
    required this.snippet,
  });
  Json toJson() => {'id': id, 'title': title, 'url': url, 'snippet': snippet};
  factory ResearchSource.fromJson(Json j) => ResearchSource(
    id: j['id'] as String,
    title: j['title'] as String,
    url: j['url'] as String,
    snippet: j['snippet'] as String,
  );
}

class ResearchRun {
  String id, goal, status, report, error, pendingStage, pendingQuery;
  String? topicId;
  List<String>? inputItemIds;
  int calls, callLimit;
  bool meaningful, requestPending, stale;
  List<String> steps;
  List<ResearchSource> sources;
  ReadingPresentation? presentation;
  DateTime startedAt;
  DateTime? completedAt;
  ResearchRun({
    required this.id,
    required this.goal,
    this.topicId,
    this.inputItemIds,
    this.status = 'running',
    this.report = '',
    this.error = '',
    this.pendingStage = '',
    this.pendingQuery = '',
    this.calls = 0,
    this.callLimit = 6,
    this.meaningful = false,
    this.requestPending = false,
    this.stale = false,
    List<String>? steps,
    List<ResearchSource>? sources,
    this.presentation,
    DateTime? startedAt,
    this.completedAt,
  }) : steps = steps ?? [],
       sources = sources ?? [],
       startedAt = startedAt ?? DateTime.now();
  Json toJson() => {
    'id': id,
    'goal': goal,
    'topicId': topicId,
    'inputItemIds': inputItemIds,
    'status': status,
    'report': report,
    'error': error,
    'pendingStage': pendingStage,
    'pendingQuery': pendingQuery,
    'calls': calls,
    'callLimit': callLimit,
    'meaningful': meaningful,
    'requestPending': requestPending,
    'stale': stale,
    'steps': steps,
    'sources': sources.map((s) => s.toJson()).toList(),
    'presentation': presentation?.toJson(),
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
  };
  factory ResearchRun.fromJson(Json j) => ResearchRun(
    id: j['id'] as String,
    goal: j['goal'] as String,
    topicId: j['topicId'] as String?,
    inputItemIds: j['inputItemIds'] == null ? null : strings(j['inputItemIds']),
    status: j['status'] as String? ?? 'running',
    report: j['report'] as String? ?? '',
    error: j['error'] as String? ?? '',
    pendingStage: j['pendingStage'] as String? ?? '',
    pendingQuery: j['pendingQuery'] as String? ?? '',
    calls: j['calls'] as int? ?? 0,
    callLimit: j['callLimit'] as int? ?? 6,
    meaningful: j['meaningful'] as bool? ?? false,
    requestPending: j['requestPending'] as bool? ?? false,
    stale: j['stale'] as bool? ?? false,
    steps: strings(j['steps']),
    sources: (j['sources'] as List? ?? [])
        .map((s) => ResearchSource.fromJson(json(s)))
        .toList(),
    presentation: j['presentation'] == null
        ? null
        : ReadingPresentation.fromJson(json(j['presentation'])),
    startedAt: date(j['startedAt']),
    completedAt: date(j['completedAt']),
  );
}

class TodayEntry {
  String id, entityType, entityId, reason;
  List<String> relatedIds;
  TodayEntry({
    required this.id,
    required this.entityType,
    required this.entityId,
    this.reason = '',
    List<String>? relatedIds,
  }) : relatedIds = relatedIds ?? [];
  Json toJson() => {
    'id': id,
    'entityType': entityType,
    'entityId': entityId,
    'reason': reason,
    'relatedIds': relatedIds,
  };
  factory TodayEntry.fromJson(Json j) => TodayEntry(
    id: j['id'] as String,
    entityType: j['entityType'] as String? ?? '',
    entityId: j['entityId'] as String? ?? '',
    reason: j['reason'] as String? ?? '',
    relatedIds: strings(j['relatedIds']),
  );
}

class TodaySnapshot {
  String day;
  List<TodayEntry> entries;
  List<String> skippedIds;
  Map<String, DateTime> deferredUntil;
  TodaySnapshot({
    required this.day,
    List<TodayEntry>? entries,
    List<String>? skippedIds,
    Map<String, DateTime>? deferredUntil,
  }) : entries = entries ?? [],
       skippedIds = skippedIds ?? [],
       deferredUntil = deferredUntil ?? {};
  Json toJson() => {
    'day': day,
    'entries': entries.map((e) => e.toJson()).toList(),
    'skippedIds': skippedIds,
    'deferredUntil': deferredUntil.map(
      (key, value) => MapEntry(key, value.toIso8601String()),
    ),
  };
  factory TodaySnapshot.fromJson(Json j) => TodaySnapshot(
    day: j['day'] as String,
    entries: (j['entries'] as List? ?? [])
        .map((e) => TodayEntry.fromJson(json(e)))
        .toList(),
    skippedIds: strings(j['skippedIds']),
    deferredUntil: (j['deferredUntil'] as Map? ?? {}).map(
      (key, value) => MapEntry(key as String, date(value) ?? DateTime.now()),
    ),
  );
}

class BackgroundJob {
  String id, type, entityId, status, stage, error;
  String lane;
  Json checkpoint;
  int epoch, attempts, version;
  DateTime createdAt, updatedAt;
  BackgroundJob({
    required this.id,
    required this.type,
    required this.entityId,
    this.status = 'queued',
    this.stage = 'queued',
    this.lane = 'background',
    Json? checkpoint,
    this.epoch = 0,
    this.version = 2,
    this.attempts = 0,
    this.error = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : checkpoint = checkpoint ?? {},
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now();
  Json toJson() => {
    'id': id,
    'type': type,
    'entityId': entityId,
    'status': status,
    'stage': stage,
    'lane': lane,
    'checkpoint': checkpoint,
    'epoch': epoch,
    'version': version,
    'attempts': attempts,
    'error': error,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
  factory BackgroundJob.fromJson(Json j) => BackgroundJob(
    id: j['id'] as String,
    type: j['type'] as String? ?? '',
    entityId: j['entityId'] as String? ?? '',
    status: j['status'] as String? ?? 'queued',
    stage: j['stage'] as String? ?? 'queued',
    lane: j['lane'] as String? ?? 'background',
    checkpoint: json(j['checkpoint'] ?? {}),
    epoch: j['epoch'] as int? ?? 0,
    version: j['version'] as int? ?? 1,
    attempts: j['attempts'] as int? ?? 0,
    error: j['error'] as String? ?? '',
    createdAt: date(j['createdAt']),
    updatedAt: date(j['updatedAt']),
  );
}

class PendingNotification {
  String id, channel, title, body, entityType, entityId;
  bool delivered;
  DateTime createdAt;
  PendingNotification({
    required this.id,
    required this.channel,
    required this.title,
    required this.body,
    this.entityType = '',
    this.entityId = '',
    this.delivered = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
  Json toJson() => {
    'id': id,
    'channel': channel,
    'title': title,
    'body': body,
    'entityType': entityType,
    'entityId': entityId,
    'delivered': delivered,
    'createdAt': createdAt.toIso8601String(),
  };
  factory PendingNotification.fromJson(Json j) => PendingNotification(
    id: j['id'] as String,
    channel: j['channel'] as String? ?? '',
    title: j['title'] as String? ?? '',
    body: j['body'] as String? ?? '',
    entityType: j['entityType'] as String? ?? '',
    entityId: j['entityId'] as String? ?? '',
    delivered: j['delivered'] as bool? ?? false,
    createdAt: date(j['createdAt']),
  );
}

class RuntimeState {
  int epoch;
  List<BackgroundJob> jobs;
  List<PendingNotification> outbox;
  RuntimeState({
    this.epoch = 0,
    List<BackgroundJob>? jobs,
    List<PendingNotification>? outbox,
  }) : jobs = jobs ?? [],
       outbox = outbox ?? [];
  Json toJson() => {
    'version': 2,
    'epoch': epoch,
    'jobs': jobs.map((j) => j.toJson()).toList(),
    'outbox': outbox.map((n) => n.toJson()).toList(),
  };
  factory RuntimeState.fromJson(Json j) {
    if (j['version'] != 1 && j['version'] != 2) {
      throw const FormatException('不支持的后台任务数据版本');
    }
    return RuntimeState(
      epoch: j['epoch'] as int? ?? 0,
      jobs: (j['jobs'] as List? ?? [])
          .map((v) => BackgroundJob.fromJson(json(v)))
          .toList(),
      outbox: (j['outbox'] as List? ?? [])
          .map((v) => PendingNotification.fromJson(json(v)))
          .toList(),
    );
  }
}

class AppSettings {
  String endpoint, textModel, visionModel, searchEndpoint, customInstructions;
  List<String> explicitInterests, inferredInterests, suppressedInterests;
  List<String> confirmedInterests;
  bool debugModelLogging, digestEnabled;
  bool progressNotifications, resultNotifications, digestNotifications;
  bool researchNotifications;
  ReadingPreset readingPreset;
  int digestHour, digestMinute;
  double _readerFontScale;
  int conversationCallLimit, modelTextContextChars;
  int _trashRetentionDays;
  double get readerFontScale => _readerFontScale;
  set readerFontScale(double value) {
    _readerFontScale = _validReaderFontScale(value);
  }

  int get trashRetentionDays => _trashRetentionDays;
  set trashRetentionDays(int value) {
    _trashRetentionDays = _validRetention(value);
  }

  static double _validReaderFontScale(double value) {
    if (!value.isFinite) return 1.0;
    return value.clamp(0.85, 1.6).toDouble();
  }

  static int _validRetention(int value) {
    if (value != 3 && value != 7) {
      throw ArgumentError.value(value, 'trashRetentionDays', 'must be 3 or 7');
    }
    return value;
  }

  static int _validConversationCallLimit(int value) {
    if (value < 1 || value > 20) {
      throw ArgumentError.value(
        value,
        'conversationCallLimit',
        'must be between 1 and 20',
      );
    }
    return value;
  }

  static int _validModelTextContextChars(int value) {
    if (value < 8000 || value > 64000) {
      throw ArgumentError.value(
        value,
        'modelTextContextChars',
        'must be between 8000 and 64000',
      );
    }
    return value;
  }

  AppSettings({
    this.endpoint = 'https://api.openai.com/v1',
    this.textModel = '',
    this.visionModel = '',
    this.searchEndpoint = 'https://api.tavily.com/search',
    this.customInstructions = '',
    List<String>? explicitInterests,
    List<String>? inferredInterests,
    List<String>? suppressedInterests,
    List<String>? confirmedInterests,
    this.debugModelLogging = false,
    this.digestEnabled = true,
    this.digestHour = 20,
    this.digestMinute = 0,
    int conversationCallLimit = 5,
    int modelTextContextChars = 24000,
    this.progressNotifications = true,
    this.resultNotifications = true,
    this.digestNotifications = true,
    this.researchNotifications = true,
    this.readingPreset = ReadingPreset.editorial,
    double readerFontScale = 1.0,
    int trashRetentionDays = 7,
  }) : explicitInterests = explicitInterests ?? [],
       inferredInterests = inferredInterests ?? [],
       suppressedInterests = suppressedInterests ?? [],
       confirmedInterests = confirmedInterests ?? [],
       _readerFontScale = _validReaderFontScale(readerFontScale),
       conversationCallLimit = _validConversationCallLimit(
         conversationCallLimit,
       ),
       modelTextContextChars = _validModelTextContextChars(
         modelTextContextChars,
       ),
       _trashRetentionDays = _validRetention(trashRetentionDays);
  Json toJson() => {
    'endpoint': endpoint,
    'textModel': textModel,
    'visionModel': visionModel,
    'searchEndpoint': searchEndpoint,
    'customInstructions': customInstructions,
    'explicitInterests': explicitInterests,
    'inferredInterests': inferredInterests,
    'suppressedInterests': suppressedInterests,
    'confirmedInterests': confirmedInterests,
    'debugModelLogging': debugModelLogging,
    'digestEnabled': digestEnabled,
    'digestHour': digestHour,
    'digestMinute': digestMinute,
    'conversationCallLimit': conversationCallLimit,
    'modelTextContextChars': modelTextContextChars,
    'progressNotifications': progressNotifications,
    'resultNotifications': resultNotifications,
    'digestNotifications': digestNotifications,
    'researchNotifications': researchNotifications,
    'readingPreset': readingPreset.name,
    'readerFontScale': readerFontScale,
    'trashRetentionDays': trashRetentionDays,
  };
  factory AppSettings.fromJson(Json j) => AppSettings(
    endpoint: j['endpoint'] as String? ?? 'https://api.openai.com/v1',
    textModel: j['textModel'] as String? ?? '',
    visionModel: j['visionModel'] as String? ?? '',
    searchEndpoint:
        j['searchEndpoint'] as String? ?? 'https://api.tavily.com/search',
    customInstructions: j['customInstructions'] as String? ?? '',
    explicitInterests: strings(j['explicitInterests']),
    inferredInterests: strings(j['inferredInterests']),
    suppressedInterests: strings(j['suppressedInterests']),
    confirmedInterests: strings(j['confirmedInterests']),
    debugModelLogging: j['debugModelLogging'] as bool? ?? false,
    digestEnabled: j['digestEnabled'] as bool? ?? true,
    digestHour: j['digestHour'] as int? ?? 20,
    digestMinute: j['digestMinute'] as int? ?? 0,
    conversationCallLimit: j['conversationCallLimit'] as int? ?? 5,
    modelTextContextChars: j['modelTextContextChars'] as int? ?? 24000,
    progressNotifications: j['progressNotifications'] as bool? ?? true,
    resultNotifications: j['resultNotifications'] as bool? ?? true,
    digestNotifications: j['digestNotifications'] as bool? ?? true,
    researchNotifications: j['researchNotifications'] as bool? ?? true,
    readingPreset: enumValue(
      ReadingPreset.values,
      j['readingPreset'],
      ReadingPreset.editorial,
    ),
    readerFontScale: _validReaderFontScale(
      doubleValue(j['readerFontScale'], 1.0),
    ),
    trashRetentionDays: j['trashRetentionDays'] == 3 ? 3 : 7,
  );
}

class AppData {
  List<LibraryItem> items;
  List<Topic> topics;
  List<Conversation> conversations;
  List<ConversationTurn> conversationTurns;
  List<SourceSegmentSummary> segmentSummaries;
  List<KnowledgeProposal> knowledgeProposals;
  List<KnowledgeRevision> knowledgeRevisions;
  List<Feed> feeds;
  List<FeedEntry> entries;
  List<ResearchRun> runs;
  List<TodaySnapshot> todaySnapshots;
  List<String> notices, acknowledgedShares;
  AppSettings settings;
  AppData({
    List<LibraryItem>? items,
    List<Topic>? topics,
    List<Conversation>? conversations,
    List<ConversationTurn>? conversationTurns,
    List<SourceSegmentSummary>? segmentSummaries,
    List<KnowledgeProposal>? knowledgeProposals,
    List<KnowledgeRevision>? knowledgeRevisions,
    List<Feed>? feeds,
    List<FeedEntry>? entries,
    List<ResearchRun>? runs,
    List<TodaySnapshot>? todaySnapshots,
    List<String>? notices,
    List<String>? acknowledgedShares,
    AppSettings? settings,
  }) : items = items ?? [],
       topics = topics ?? [],
       conversations = conversations ?? [],
       conversationTurns = conversationTurns ?? [],
       segmentSummaries = segmentSummaries ?? [],
       knowledgeProposals = knowledgeProposals ?? [],
       knowledgeRevisions = knowledgeRevisions ?? [],
       feeds = feeds ?? [],
       entries = entries ?? [],
       runs = runs ?? [],
       todaySnapshots = todaySnapshots ?? [],
       notices = notices ?? [],
       acknowledgedShares = acknowledgedShares ?? [],
       settings = settings ?? AppSettings();
  Json toJson() => {
    'version': 4,
    'items': items.map((i) => i.toJson()).toList(),
    'topics': topics.map((t) => t.toJson()).toList(),
    'conversations': conversations.map((c) => c.toJson()).toList(),
    'conversationTurns': conversationTurns.map((t) => t.toJson()).toList(),
    'segmentSummaries': segmentSummaries.map((s) => s.toJson()).toList(),
    'knowledgeProposals': knowledgeProposals.map((p) => p.toJson()).toList(),
    'knowledgeRevisions': knowledgeRevisions.map((r) => r.toJson()).toList(),
    'feeds': feeds.map((f) => f.toJson()).toList(),
    'entries': entries.map((e) => e.toJson()).toList(),
    'runs': runs.map((r) => r.toJson()).toList(),
    'todaySnapshots': todaySnapshots.map((s) => s.toJson()).toList(),
    'notices': notices,
    'acknowledgedShares': acknowledgedShares,
    'settings': settings.toJson(),
  };
  factory AppData.fromJson(Json j) {
    if (j['version'] != 1 &&
        j['version'] != 2 &&
        j['version'] != 3 &&
        j['version'] != 4) {
      throw const FormatException('不支持的数据版本');
    }
    return AppData(
      items: (j['items'] as List? ?? [])
          .map((v) => LibraryItem.fromJson(json(v)))
          .toList(),
      topics: (j['topics'] as List? ?? [])
          .map((v) => Topic.fromJson(json(v)))
          .toList(),
      conversations: (j['conversations'] as List? ?? [])
          .map((v) => Conversation.fromJson(json(v)))
          .toList(),
      conversationTurns: (j['conversationTurns'] as List? ?? [])
          .map((v) => ConversationTurn.fromJson(json(v)))
          .toList(),
      segmentSummaries: (j['segmentSummaries'] as List? ?? [])
          .map((v) => SourceSegmentSummary.fromJson(json(v)))
          .toList(),
      knowledgeProposals: (j['knowledgeProposals'] as List? ?? [])
          .map((v) => KnowledgeProposal.fromJson(json(v)))
          .toList(),
      knowledgeRevisions: (j['knowledgeRevisions'] as List? ?? [])
          .map((v) => KnowledgeRevision.fromJson(json(v)))
          .toList(),
      feeds: (j['feeds'] as List? ?? [])
          .map((v) => Feed.fromJson(json(v)))
          .toList(),
      entries: (j['entries'] as List? ?? [])
          .map((v) => FeedEntry.fromJson(json(v)))
          .toList(),
      runs: (j['runs'] as List? ?? [])
          .map((v) => ResearchRun.fromJson(json(v)))
          .toList(),
      todaySnapshots: (j['todaySnapshots'] as List? ?? [])
          .map((v) => TodaySnapshot.fromJson(json(v)))
          .toList(),
      notices: strings(j['notices']),
      acknowledgedShares: strings(j['acknowledgedShares']),
      settings: AppSettings.fromJson(json(j['settings'] ?? {})),
    );
  }
}
