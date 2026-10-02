part of 'models.dart';

enum ConversationScope { item, topic, library }

Map<String, int> _intMap(dynamic value) {
  final map = value is Map ? value : const {};
  return {
    for (final entry in map.entries)
      if (entry.key is String && entry.value is int)
        entry.key as String: entry.value as int,
  };
}

Map<String, String> _stringMap(dynamic value) {
  final map = value is Map ? value : const {};
  return {
    for (final entry in map.entries)
      if (entry.key is String && entry.value is String)
        entry.key as String: entry.value as String,
  };
}

class Conversation {
  String id, title;
  ConversationScope scope;
  String? scopeId;
  List<String>? sourceIds;
  DateTime createdAt, updatedAt;
  Conversation({
    required this.id,
    required this.title,
    required this.scope,
    this.scopeId,
    this.sourceIds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now();
  Json toJson() => {
    'id': id,
    'title': title,
    'scope': scope.name,
    'scopeId': scopeId,
    'sourceIds': sourceIds,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
  factory Conversation.fromJson(Json j) => Conversation(
    id: j['id'] as String,
    title: j['title'] as String? ?? '',
    scope: enumValue(
      ConversationScope.values,
      j['scope'],
      ConversationScope.library,
    ),
    scopeId: j['scopeId'] as String?,
    sourceIds: j['sourceIds'] == null ? null : strings(j['sourceIds']),
    createdAt: date(j['createdAt']),
    updatedAt: date(j['updatedAt']),
  );
}

class SourceWindow {
  final String id, sourceId, blockId, text, fingerprint, readActionId;
  final int sourceVersion, start, end;
  SourceWindow({
    required this.id,
    required this.sourceId,
    required this.sourceVersion,
    required this.blockId,
    required this.start,
    required this.end,
    required this.text,
    required this.fingerprint,
    this.readActionId = '',
  });
  Json toJson() => {
    'id': id,
    'sourceId': sourceId,
    'sourceVersion': sourceVersion,
    'blockId': blockId,
    'start': start,
    'end': end,
    'text': text,
    'fingerprint': fingerprint,
    'readActionId': readActionId,
  };
  factory SourceWindow.fromJson(Json j) => SourceWindow(
    id: j['id'] as String,
    sourceId: j['sourceId'] as String,
    sourceVersion: j['sourceVersion'] as int? ?? 0,
    blockId: j['blockId'] as String? ?? '',
    start: j['start'] as int? ?? 0,
    end: j['end'] as int? ?? 0,
    text: j['text'] as String? ?? '',
    fingerprint: j['fingerprint'] as String? ?? '',
    readActionId: j['readActionId'] as String? ?? '',
  );
}

class VisualEvidence {
  final String sourceId, assetFingerprint, observation;
  final int sourceVersion;
  final int? page;
  final bool unverified;
  VisualEvidence({
    required this.sourceId,
    required this.sourceVersion,
    required this.assetFingerprint,
    this.page,
    this.observation = '',
    this.unverified = true,
  });
  Json toJson() => {
    'sourceId': sourceId,
    'sourceVersion': sourceVersion,
    'assetFingerprint': assetFingerprint,
    'page': page,
    'observation': observation,
    'unverified': unverified,
  };
  factory VisualEvidence.fromJson(Json j) => VisualEvidence(
    sourceId: j['sourceId'] as String? ?? '',
    sourceVersion: j['sourceVersion'] as int? ?? 0,
    assetFingerprint: j['assetFingerprint'] as String? ?? '',
    page: j['page'] as int?,
    observation: j['observation'] as String? ?? '',
    unverified: j['unverified'] as bool? ?? true,
  );
}

class ConversationTurn {
  String id, conversationId, question, status, stage, error, answer;
  List<EvidenceAnchor> evidence;
  List<SourceWindow> windows;
  List<VisualEvidence> visualEvidence;
  List<String> inputItemIds;
  Map<String, int> sourceVersions;
  Map<String, String> sourceFingerprints;
  int calls, callLimit, textBudgetChars;
  bool requestPending, stale;
  DateTime createdAt;
  DateTime? completedAt;
  ConversationTurn({
    required this.id,
    required this.conversationId,
    required this.question,
    this.status = 'queued',
    this.stage = '',
    this.error = '',
    this.answer = '',
    List<EvidenceAnchor>? evidence,
    List<SourceWindow>? windows,
    List<VisualEvidence>? visualEvidence,
    List<String>? inputItemIds,
    Map<String, int>? sourceVersions,
    Map<String, String>? sourceFingerprints,
    this.calls = 0,
    this.callLimit = 5,
    this.textBudgetChars = 24000,
    this.requestPending = false,
    this.stale = false,
    DateTime? createdAt,
    this.completedAt,
  }) : evidence = evidence ?? [],
       windows = windows ?? [],
       visualEvidence = visualEvidence ?? [],
       inputItemIds = inputItemIds ?? [],
       sourceVersions = sourceVersions ?? {},
       sourceFingerprints = sourceFingerprints ?? {},
       createdAt = createdAt ?? DateTime.now();
  Json toJson() => {
    'id': id,
    'conversationId': conversationId,
    'question': question,
    'status': status,
    'stage': stage,
    'error': error,
    'answer': answer,
    'evidence': evidence.map((e) => e.toJson()).toList(),
    'windows': windows.map((w) => w.toJson()).toList(),
    'visualEvidence': visualEvidence.map((v) => v.toJson()).toList(),
    'inputItemIds': inputItemIds,
    'sourceVersions': sourceVersions,
    'sourceFingerprints': sourceFingerprints,
    'calls': calls,
    'callLimit': callLimit,
    'textBudgetChars': textBudgetChars,
    'requestPending': requestPending,
    'stale': stale,
    'createdAt': createdAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
  };
  factory ConversationTurn.fromJson(Json j) {
    final turn = ConversationTurn(
      id: j['id'] as String,
      conversationId: j['conversationId'] as String,
      question: j['question'] as String? ?? '',
      status: j['status'] as String? ?? 'queued',
      stage: j['stage'] as String? ?? '',
      error: j['error'] as String? ?? '',
      answer: j['answer'] as String? ?? '',
      evidence: (j['evidence'] as List? ?? [])
          .map((e) => EvidenceAnchor.fromJson(json(e)))
          .toList(),
      windows: (j['windows'] as List? ?? [])
          .map((w) => SourceWindow.fromJson(json(w)))
          .toList(),
      visualEvidence: (j['visualEvidence'] as List? ?? [])
          .map((v) => VisualEvidence.fromJson(json(v)))
          .toList(),
      inputItemIds: strings(j['inputItemIds']),
      sourceVersions: _intMap(j['sourceVersions']),
      sourceFingerprints: _stringMap(j['sourceFingerprints']),
      calls: j['calls'] as int? ?? 0,
      callLimit: j['callLimit'] as int? ?? 5,
      textBudgetChars: j['textBudgetChars'] as int? ?? 24000,
      requestPending: j['requestPending'] as bool? ?? false,
      stale: j['stale'] as bool? ?? false,
      createdAt: date(j['createdAt']),
      completedAt: date(j['completedAt']),
    );
    if (turn.callLimit < 1 ||
        turn.callLimit > 20 ||
        turn.textBudgetChars < 8000 ||
        turn.textBudgetChars > 64000 ||
        turn.calls < 0 ||
        turn.calls > turn.callLimit) {
      throw const FormatException('会话调用次数或文字预算超出支持范围');
    }
    return turn;
  }
}

class SourceSegmentSummary {
  String id, sourceId, fingerprint, promptVersion, summary;
  int sourceVersion, rangeStart, rangeEnd;
  bool pdf;
  List<EvidenceAnchor> evidence;
  DateTime createdAt;
  SourceSegmentSummary({
    required this.id,
    required this.sourceId,
    required this.sourceVersion,
    required this.rangeStart,
    required this.rangeEnd,
    this.pdf = false,
    required this.fingerprint,
    this.promptVersion = 'source-v1',
    required this.summary,
    List<EvidenceAnchor>? evidence,
    DateTime? createdAt,
  }) : evidence = evidence ?? [],
       createdAt = createdAt ?? DateTime.now();
  Json toJson() => {
    'id': id,
    'sourceId': sourceId,
    'sourceVersion': sourceVersion,
    'rangeStart': rangeStart,
    'rangeEnd': rangeEnd,
    'pdf': pdf,
    'fingerprint': fingerprint,
    'promptVersion': promptVersion,
    'summary': summary,
    'evidence': evidence.map((e) => e.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
  };
  factory SourceSegmentSummary.fromJson(Json j) => SourceSegmentSummary(
    id: j['id'] as String,
    sourceId: j['sourceId'] as String,
    sourceVersion: j['sourceVersion'] as int? ?? 0,
    rangeStart: j['rangeStart'] as int? ?? 0,
    rangeEnd: j['rangeEnd'] as int? ?? 0,
    pdf: j['pdf'] as bool? ?? false,
    fingerprint: j['fingerprint'] as String? ?? '',
    promptVersion: j['promptVersion'] as String? ?? 'source-v1',
    summary: j['summary'] as String? ?? '',
    evidence: (j['evidence'] as List? ?? [])
        .map((e) => EvidenceAnchor.fromJson(json(e)))
        .toList(),
    createdAt: date(j['createdAt']),
  );
}

class KnowledgeProposal {
  String id, title, question, reason, status;
  String? topicId, baseRevisionId, originTurnId, originSourceId;
  String? acceptedRevisionId;
  ReadingPresentation presentation;
  List<String> inputItemIds, relatedTopicIds;
  Map<String, int> sourceVersions;
  Map<String, String> sourceFingerprints;
  List<EvidenceAnchor> evidence;
  DateTime createdAt;
  KnowledgeProposal({
    required this.id,
    this.topicId,
    this.baseRevisionId,
    required this.title,
    required this.question,
    ReadingPresentation? presentation,
    List<String>? inputItemIds,
    Map<String, int>? sourceVersions,
    Map<String, String>? sourceFingerprints,
    List<EvidenceAnchor>? evidence,
    List<String>? relatedTopicIds,
    this.reason = '',
    this.originTurnId,
    this.originSourceId,
    this.status = 'pending',
    this.acceptedRevisionId,
    DateTime? createdAt,
  }) : presentation = presentation ?? ReadingPresentation(),
       inputItemIds = inputItemIds ?? [],
       sourceVersions = sourceVersions ?? {},
       sourceFingerprints = sourceFingerprints ?? {},
       evidence = evidence ?? [],
       relatedTopicIds = relatedTopicIds ?? [],
       createdAt = createdAt ?? DateTime.now();
  Json toJson() => {
    'id': id,
    'topicId': topicId,
    'baseRevisionId': baseRevisionId,
    'title': title,
    'question': question,
    'presentation': presentation.toJson(),
    'inputItemIds': inputItemIds,
    'sourceVersions': sourceVersions,
    'sourceFingerprints': sourceFingerprints,
    'evidence': evidence.map((e) => e.toJson()).toList(),
    'relatedTopicIds': relatedTopicIds,
    'reason': reason,
    'originTurnId': originTurnId,
    'originSourceId': originSourceId,
    'status': status,
    'acceptedRevisionId': acceptedRevisionId,
    'createdAt': createdAt.toIso8601String(),
  };
  factory KnowledgeProposal.fromJson(Json j) => KnowledgeProposal(
    id: j['id'] as String,
    topicId: j['topicId'] as String?,
    baseRevisionId: j['baseRevisionId'] as String?,
    title: j['title'] as String? ?? '',
    question: j['question'] as String? ?? '',
    presentation: ReadingPresentation.fromJson(json(j['presentation'] ?? {})),
    inputItemIds: strings(j['inputItemIds']),
    sourceVersions: _intMap(j['sourceVersions']),
    sourceFingerprints: _stringMap(j['sourceFingerprints']),
    evidence: (j['evidence'] as List? ?? [])
        .map((e) => EvidenceAnchor.fromJson(json(e)))
        .toList(),
    relatedTopicIds: strings(j['relatedTopicIds']),
    reason: j['reason'] as String? ?? '',
    originTurnId: j['originTurnId'] as String?,
    originSourceId: j['originSourceId'] as String?,
    status: j['status'] as String? ?? 'pending',
    acceptedRevisionId: j['acceptedRevisionId'] as String?,
    createdAt: date(j['createdAt']),
  );
}

class KnowledgeRevision {
  String id, topicId, reason;
  String? parentId, originTurnId;
  ReadingPresentation presentation;
  List<String> inputItemIds, relatedTopicIds;
  Map<String, int> sourceVersions;
  Map<String, String> sourceFingerprints;
  List<EvidenceAnchor> evidence;
  bool humanEdited, stale;
  DateTime createdAt;
  KnowledgeRevision({
    required this.id,
    required this.topicId,
    this.parentId,
    ReadingPresentation? presentation,
    List<String>? inputItemIds,
    Map<String, int>? sourceVersions,
    Map<String, String>? sourceFingerprints,
    List<EvidenceAnchor>? evidence,
    List<String>? relatedTopicIds,
    this.reason = '',
    this.originTurnId,
    this.humanEdited = false,
    DateTime? createdAt,
    this.stale = false,
  }) : presentation = presentation ?? ReadingPresentation(),
       inputItemIds = inputItemIds ?? [],
       sourceVersions = sourceVersions ?? {},
       sourceFingerprints = sourceFingerprints ?? {},
       evidence = evidence ?? [],
       relatedTopicIds = relatedTopicIds ?? [],
       createdAt = createdAt ?? DateTime.now();
  Json toJson() => {
    'id': id,
    'topicId': topicId,
    'parentId': parentId,
    'presentation': presentation.toJson(),
    'inputItemIds': inputItemIds,
    'sourceVersions': sourceVersions,
    'sourceFingerprints': sourceFingerprints,
    'evidence': evidence.map((e) => e.toJson()).toList(),
    'relatedTopicIds': relatedTopicIds,
    'reason': reason,
    'originTurnId': originTurnId,
    'humanEdited': humanEdited,
    'createdAt': createdAt.toIso8601String(),
    'stale': stale,
  };
  factory KnowledgeRevision.fromJson(Json j) => KnowledgeRevision(
    id: j['id'] as String,
    topicId: j['topicId'] as String? ?? '',
    parentId: j['parentId'] as String?,
    presentation: ReadingPresentation.fromJson(json(j['presentation'] ?? {})),
    inputItemIds: strings(j['inputItemIds']),
    sourceVersions: _intMap(j['sourceVersions']),
    sourceFingerprints: _stringMap(j['sourceFingerprints']),
    evidence: (j['evidence'] as List? ?? [])
        .map((e) => EvidenceAnchor.fromJson(json(e)))
        .toList(),
    relatedTopicIds: strings(j['relatedTopicIds']),
    reason: j['reason'] as String? ?? '',
    originTurnId: j['originTurnId'] as String?,
    humanEdited: j['humanEdited'] as bool? ?? false,
    createdAt: date(j['createdAt']),
    stale: j['stale'] as bool? ?? false,
  );
}
