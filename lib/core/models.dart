import 'dart:math';

typedef Json = Map<String, dynamic>;
String newId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${Random.secure().nextInt(1 << 32).toRadixString(36)}';
List<String> strings(dynamic value) =>
    (value as List? ?? []).whereType<String>().toList();
DateTime? date(dynamic value) =>
    value is String ? DateTime.tryParse(value) : null;
Json json(dynamic value) => Map<String, dynamic>.from(value as Map);

enum ItemKind { web, text, image, pdf }

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
  String summary;
  List<String> insights, connections, questions, sourceIds, suggestedTopics;
  List<String>? inputItemIds;
  DateTime createdAt;
  Analysis({
    this.summary = '',
    this.inputItemIds,
    List<String>? insights,
    List<String>? connections,
    List<String>? questions,
    List<String>? sourceIds,
    List<String>? suggestedTopics,
    DateTime? createdAt,
  }) : insights = insights ?? [],
       connections = connections ?? [],
       questions = questions ?? [],
       sourceIds = sourceIds ?? [],
       suggestedTopics = suggestedTopics ?? [],
       createdAt = createdAt ?? DateTime.now();
  Json toJson() => {
    'summary': summary,
    'inputItemIds': inputItemIds,
    'insights': insights,
    'connections': connections,
    'questions': questions,
    'sourceIds': sourceIds,
    'suggestedTopics': suggestedTopics,
    'createdAt': createdAt.toIso8601String(),
  };
  factory Analysis.fromJson(Json j) => Analysis(
    summary: j['summary'] as String? ?? '',
    inputItemIds: j['inputItemIds'] == null ? null : strings(j['inputItemIds']),
    insights: strings(j['insights']),
    connections: strings(j['connections']),
    questions: strings(j['questions']),
    sourceIds: strings(j['sourceIds']),
    suggestedTopics: strings(j['suggestedTopics']),
    createdAt: date(j['createdAt']),
  );
}

class LibraryItem {
  String id, title, url, body, notes, status, error, warning;
  ItemKind kind;
  List<Asset> assets;
  Analysis? analysis;
  DateTime createdAt;
  DateTime? archivedAt, trashedAt;
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
  }) : assets = assets ?? [],
       createdAt = createdAt ?? DateTime.now();
  Json toJson() => {
    'id': id,
    'title': title,
    'url': url,
    'kind': kind.name,
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
  };
  factory LibraryItem.fromJson(Json j) => LibraryItem(
    id: j['id'] as String,
    title: j['title'] as String,
    kind: ItemKind.values.byName(j['kind'] as String),
    url: j['url'] as String? ?? '',
    body: j['body'] as String? ?? '',
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
  );
}

class Topic {
  String id, title, question, overview, reason, status, error, authorizedScope;
  List<String> sourceIds;
  List<String>? inputItemIds;
  bool automatic, tracking;
  int intervalHours, callLimit;
  DateTime? lastRun, nextRun;
  Topic({
    required this.id,
    required this.title,
    required this.question,
    this.overview = '',
    this.reason = '',
    this.status = 'idle',
    this.error = '',
    this.authorizedScope = '',
    List<String>? sourceIds,
    this.inputItemIds,
    this.automatic = false,
    this.tracking = false,
    this.intervalHours = 24,
    this.callLimit = 6,
    this.lastRun,
    this.nextRun,
  }) : sourceIds = sourceIds ?? [];
  Json toJson() => {
    'id': id,
    'title': title,
    'question': question,
    'overview': overview,
    'reason': reason,
    'status': status,
    'error': error,
    'authorizedScope': authorizedScope,
    'sourceIds': sourceIds,
    'inputItemIds': inputItemIds,
    'automatic': automatic,
    'tracking': tracking,
    'intervalHours': intervalHours,
    'callLimit': callLimit,
    'lastRun': lastRun?.toIso8601String(),
    'nextRun': nextRun?.toIso8601String(),
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
    sourceIds: strings(j['sourceIds']),
    inputItemIds: j['inputItemIds'] == null ? null : strings(j['inputItemIds']),
    automatic: j['automatic'] as bool? ?? false,
    tracking: j['tracking'] as bool? ?? false,
    intervalHours: j['intervalHours'] as int? ?? 24,
    callLimit: j['callLimit'] as int? ?? 6,
    lastRun: date(j['lastRun']),
    nextRun: date(j['nextRun']),
  );
}

class Feed {
  String id, title, url, error;
  DateTime? refreshedAt;
  Feed({
    required this.id,
    required this.url,
    this.title = '',
    this.error = '',
    this.refreshedAt,
  });
  Json toJson() => {
    'id': id,
    'url': url,
    'title': title,
    'error': error,
    'refreshedAt': refreshedAt?.toIso8601String(),
  };
  factory Feed.fromJson(Json j) => Feed(
    id: j['id'] as String,
    url: j['url'] as String,
    title: j['title'] as String? ?? '',
    error: j['error'] as String? ?? '',
    refreshedAt: date(j['refreshedAt']),
  );
}

class FeedEntry {
  String id, feedId, title, url, summary;
  String? savedItemId;
  DateTime? publishedAt;
  FeedEntry({
    required this.id,
    required this.feedId,
    required this.title,
    required this.url,
    this.summary = '',
    this.savedItemId,
    this.publishedAt,
  });
  Json toJson() => {
    'id': id,
    'feedId': feedId,
    'title': title,
    'url': url,
    'summary': summary,
    'savedItemId': savedItemId,
    'publishedAt': publishedAt?.toIso8601String(),
  };
  factory FeedEntry.fromJson(Json j) => FeedEntry(
    id: j['id'] as String,
    feedId: j['feedId'] as String,
    title: j['title'] as String,
    url: j['url'] as String,
    summary: j['summary'] as String? ?? '',
    savedItemId: j['savedItemId'] as String?,
    publishedAt: date(j['publishedAt']),
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
  String id, goal, status, report, error;
  String? topicId;
  List<String>? inputItemIds;
  int calls, callLimit;
  bool meaningful;
  List<String> steps;
  List<ResearchSource> sources;
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
    this.calls = 0,
    this.callLimit = 6,
    this.meaningful = false,
    List<String>? steps,
    List<ResearchSource>? sources,
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
    'calls': calls,
    'callLimit': callLimit,
    'meaningful': meaningful,
    'steps': steps,
    'sources': sources.map((s) => s.toJson()).toList(),
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
    calls: j['calls'] as int? ?? 0,
    callLimit: j['callLimit'] as int? ?? 6,
    meaningful: j['meaningful'] as bool? ?? false,
    steps: strings(j['steps']),
    sources: (j['sources'] as List? ?? [])
        .map((s) => ResearchSource.fromJson(json(s)))
        .toList(),
    startedAt: date(j['startedAt']),
    completedAt: date(j['completedAt']),
  );
}

class AppSettings {
  String endpoint, textModel, visionModel, searchEndpoint, customInstructions;
  List<String> explicitInterests, inferredInterests, suppressedInterests;
  List<String> confirmedInterests;
  bool debugModelLogging;
  int _trashRetentionDays;
  int get trashRetentionDays => _trashRetentionDays;
  set trashRetentionDays(int value) {
    _trashRetentionDays = _validRetention(value);
  }

  static int _validRetention(int value) {
    if (value != 3 && value != 7) {
      throw ArgumentError.value(value, 'trashRetentionDays', 'must be 3 or 7');
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
    int trashRetentionDays = 7,
  }) : explicitInterests = explicitInterests ?? [],
       inferredInterests = inferredInterests ?? [],
       suppressedInterests = suppressedInterests ?? [],
       confirmedInterests = confirmedInterests ?? [],
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
    trashRetentionDays: j['trashRetentionDays'] == 3 ? 3 : 7,
  );
}

class AppData {
  List<LibraryItem> items;
  List<Topic> topics;
  List<Feed> feeds;
  List<FeedEntry> entries;
  List<ResearchRun> runs;
  List<String> notices, acknowledgedShares;
  AppSettings settings;
  AppData({
    List<LibraryItem>? items,
    List<Topic>? topics,
    List<Feed>? feeds,
    List<FeedEntry>? entries,
    List<ResearchRun>? runs,
    List<String>? notices,
    List<String>? acknowledgedShares,
    AppSettings? settings,
  }) : items = items ?? [],
       topics = topics ?? [],
       feeds = feeds ?? [],
       entries = entries ?? [],
       runs = runs ?? [],
       notices = notices ?? [],
       acknowledgedShares = acknowledgedShares ?? [],
       settings = settings ?? AppSettings();
  Json toJson() => {
    'version': 2,
    'items': items.map((i) => i.toJson()).toList(),
    'topics': topics.map((t) => t.toJson()).toList(),
    'feeds': feeds.map((f) => f.toJson()).toList(),
    'entries': entries.map((e) => e.toJson()).toList(),
    'runs': runs.map((r) => r.toJson()).toList(),
    'notices': notices,
    'acknowledgedShares': acknowledgedShares,
    'settings': settings.toJson(),
  };
  factory AppData.fromJson(Json j) {
    if (j['version'] != 1 && j['version'] != 2) {
      throw const FormatException('不支持的数据版本');
    }
    return AppData(
      items: (j['items'] as List? ?? [])
          .map((v) => LibraryItem.fromJson(json(v)))
          .toList(),
      topics: (j['topics'] as List? ?? [])
          .map((v) => Topic.fromJson(json(v)))
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
      notices: strings(j['notices']),
      acknowledgedShares: strings(j['acknowledgedShares']),
      settings: AppSettings.fromJson(json(j['settings'] ?? {})),
    );
  }
}
