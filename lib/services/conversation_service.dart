import 'dart:convert';

import '../core/models.dart';
import '../core/retrieval.dart';
import 'intelligence_service.dart';
import 'knowledge_service.dart';

class ConversationPrompt {
  const ConversationPrompt({
    required this.prompt,
    required this.windows,
    this.knowledgeRevisionIds = const [],
  });
  final String prompt;
  final List<SourceWindow> windows;
  final List<String> knowledgeRevisionIds;
}

class ConversationReadAction {
  const ConversationReadAction({
    required this.id,
    required this.type,
    this.query = '',
    this.sourceId = '',
    this.sourceVersion,
    this.blockId = '',
    this.start,
    this.end,
    this.page,
  });
  final String id, type, query, sourceId, blockId;
  final int? sourceVersion, start, end, page;
}

class ConversationModelStep {
  const ConversationModelStep.answer(this.answer) : actions = const [];
  const ConversationModelStep.actions(this.actions) : answer = null;
  final ConversationAnswerResult? answer;
  final List<ConversationReadAction> actions;
  bool get isAnswer => answer != null;
}

class ConversationAnswerResult {
  const ConversationAnswerResult({
    required this.answer,
    required this.presentation,
    required this.evidence,
    required this.remainingGaps,
    required this.proposals,
  });
  final String answer;
  final ReadingPresentation? presentation;
  final List<EvidenceAnchor> evidence;
  final List<String> remainingGaps;
  final List<KnowledgeProposal> proposals;
}

class ConversationService {
  const ConversationService();

  static const allowedActionTypes = {
    'search',
    'readText',
    'readPdf',
    'readImage',
  };

  ConversationPrompt buildPrompt(
    ConversationTurn turn,
    List<LibraryItem> sources, {
    List<ConversationTurn> history = const [],
    List<KnowledgeRevision> knowledge = const [],
    List<SourceSegmentSummary> summaries = const [],
    Json extraContext = const {},
    bool answerOnly = false,
    String model = '',
    int imageCount = 0,
  }) {
    final sourceById = {for (final source in sources) source.id: source};
    final availableWindows = turn.windows
        .where((window) => sourceById.containsKey(window.sourceId))
        .toList(growable: false);
    final previousAnswers = history
        .where(
          (entry) =>
              entry.conversationId == turn.conversationId &&
              entry.id != turn.id &&
              entry.answer.trim().isNotEmpty,
        )
        .toList(growable: false);
    final lastAnswer = previousAnswers.isEmpty ? null : previousAnswers.last;
    var sourceCatalog = _sourceCatalog(sources);
    var selectedWindows = availableWindows;
    var selectedKnowledge = knowledge;
    var selectedSummaries = summaries;
    var selectedLastAnswer = lastAnswer;
    var earlierAnswers = previousAnswers.length < 2
        ? <ConversationTurn>[]
        : previousAnswers
              .sublist(0, previousAnswers.length - 1)
              .reversed
              .take(3)
              .toList()
              .reversed
              .toList();

    String render() => _promptText(
      _payload(
        turn,
        windows: selectedWindows,
        sources: sourceCatalog,
        knowledge: selectedKnowledge,
        summaries: selectedSummaries,
        lastAnswer: selectedLastAnswer,
        history: earlierAnswers,
        historyTotal: previousAnswers.length,
        extraContext: extraContext,
        answerOnly: answerOnly,
      ),
    );

    var prompt = render();
    bool overBudget() =>
        IntelligenceService.textualRequestChars(
          prompt,
          model: model,
          imageCount: imageCount,
        ) >
        turn.textBudgetChars;

    while (overBudget() && selectedKnowledge.isNotEmpty) {
      selectedKnowledge = selectedKnowledge.sublist(
        0,
        selectedKnowledge.length - 1,
      );
      prompt = render();
    }
    while (overBudget() && selectedSummaries.isNotEmpty) {
      selectedSummaries = selectedSummaries.sublist(
        0,
        selectedSummaries.length - 1,
      );
      prompt = render();
    }
    while (overBudget() && earlierAnswers.isNotEmpty) {
      earlierAnswers = earlierAnswers.sublist(1);
      prompt = render();
    }
    if (overBudget() && selectedLastAnswer != null) {
      selectedLastAnswer = null;
      prompt = render();
    }
    while (overBudget() && sourceCatalog.length > 8) {
      sourceCatalog = sourceCatalog.sublist(0, sourceCatalog.length - 1);
      prompt = render();
    }
    while (overBudget() && selectedWindows.isNotEmpty) {
      selectedWindows = selectedWindows.sublist(0, selectedWindows.length - 1);
      prompt = render();
    }
    if (overBudget()) throw const FormatException('问题超过当前对话上下文预算');
    return ConversationPrompt(
      prompt: prompt,
      windows: selectedWindows,
      knowledgeRevisionIds: selectedKnowledge.map((r) => r.id).toList(),
    );
  }

  List<Json> _sourceCatalog(List<LibraryItem> sources) => sources
      .map(
        (source) => {
          'id': source.id,
          'title': source.title,
          'kind': source.kind.name,
          'sourceVersion': KnowledgeService.contentVersionForItem(source),
          'fingerprint': sourceFingerprint(source),
          if (source.pdfPageCount != null) 'pdfPageCount': source.pdfPageCount,
        },
      )
      .toList(growable: false);

  Json _payload(
    ConversationTurn turn, {
    required List<SourceWindow> windows,
    required List<Json> sources,
    required List<KnowledgeRevision> knowledge,
    required List<SourceSegmentSummary> summaries,
    required ConversationTurn? lastAnswer,
    required List<ConversationTurn> history,
    required int historyTotal,
    required Json extraContext,
    required bool answerOnly,
  }) => {
    'protocol': {
      'responseShape': answerOnly
          ? '{"answer":"...","presentation":{...},"evidence":[...],"remainingGaps":[...],"proposals":[...]}'
          : '{"actions":[...]} 或 {"answer":"...","presentation":{...},"evidence":[...],"remainingGaps":[...],"proposals":[...]}',
      'actions': allowedActionTypes.toList(),
      'maxActions': turn.callLimit,
      'callsUsed': turn.calls,
      'answerOnly': answerOnly,
      'rules': [
        '只能引用sources和windows中提供的本地资料。',
        '证据必须使用已提供window的windowId/sourceId/sourceVersion/blockId/start/end/quote。',
        'PDF或图片证据只能复用visualEvidence，并保持unverified；visualEvidence来自已规范化JPEG观察。',
        '不要输出URL、本地路径或未提供来源。',
        if (answerOnly) '这是最后一轮，必须直接回答，不得再请求actions。',
      ],
    },
    'question': turn.question,
    'sources': sources,
    'windows': windows.map((w) => w.toJson()).toList(),
    'visualEvidence': turn.visualEvidence.map((v) => v.toJson()).toList(),
    if (summaries.isNotEmpty)
      'sourceSegmentSummaries': summaries.map((s) => s.toJson()).toList(),
    if (knowledge.isNotEmpty)
      'knowledgeRevisions': knowledge.map((k) => k.toJson()).toList(),
    if (historyTotal > 0)
      'historyCoverage': {
        'providedTurnIds': [
          ...history.map((t) => t.id),
          if (lastAnswer != null) lastAnswer.id,
        ],
        'omittedTurns':
            historyTotal - history.length - (lastAnswer == null ? 0 : 1),
        'derivedHistoryNotOriginalEvidence': true,
      },
    if (history.isNotEmpty)
      'history': history
          .map(
            (t) => {
              'question': t.question,
              'answer': t.answer,
              'derived': true,
            },
          )
          .toList(),
    if (lastAnswer != null)
      'lastAnswer': {
        'question': lastAnswer.question,
        'answer': lastAnswer.answer,
        'evidence': lastAnswer.evidence.map((e) => e.toJson()).toList(),
      },
    if (extraContext.isNotEmpty) 'extraContext': extraContext,
  };

  String _promptText(Json payload) =>
      '你正在回答一个本地知识库对话。需要更多上下文时先返回actions；信息足够时返回最终answer JSON。'
      '\n输入数据：${jsonEncode(payload)}';

  ConversationModelStep parseStep(
    Json result,
    ConversationTurn turn, {
    bool answerOnly = false,
    int? actionLimit,
  }) {
    if (answerOnly ||
        result['answer'] != null ||
        result['presentation'] != null) {
      return ConversationModelStep.answer(
        parseAnswerResult(result, turn: turn),
      );
    }
    final rawActions = result['actions'];
    if (rawActions is! List) throw const FormatException('模型未返回可执行动作或答案');
    final limit = (actionLimit ?? turn.callLimit).clamp(0, turn.callLimit);
    final actions = rawActions
        .take(limit)
        .map((rawAction) => _parseAction(rawAction))
        .toList(growable: false);
    if (actions.isEmpty) throw const FormatException('模型未返回有效读取动作');
    return ConversationModelStep.actions(actions);
  }

  ConversationModelStep parseModelStep(
    Object? raw, {
    required ConversationTurn turn,
    bool answerOnly = false,
    int actionLimit = 5,
  }) {
    if (raw is! Map) throw const FormatException('模型返回内容必须为 JSON 对象');
    return parseStep(
      Map<String, dynamic>.from(raw),
      turn,
      answerOnly: answerOnly,
      actionLimit: actionLimit,
    );
  }

  ConversationReadAction _parseAction(Object? raw) {
    if (raw is! Map) throw const FormatException('读取动作必须是 JSON 对象');
    final action = Map<String, dynamic>.from(raw);
    final type = action['type'];
    if (type is! String || !allowedActionTypes.contains(type)) {
      throw const FormatException('模型返回了不支持的读取动作');
    }
    final id = action['id'] as String? ?? '';
    final sourceId = action['sourceId'] as String? ?? '';
    final blockId = action['blockId'] as String? ?? '';
    final query = action['query'] as String? ?? '';
    if ((type == 'search' && query.trim().isEmpty) ||
        (type != 'search' && sourceId.trim().isEmpty)) {
      throw const FormatException('读取动作缺少必要参数');
    }
    return ConversationReadAction(
      id: id.trim().isEmpty
          ? '$type-${sourceId.isEmpty ? query.hashCode : sourceId}'
          : id,
      type: type,
      query: query,
      sourceId: sourceId,
      sourceVersion: action['sourceVersion'] as int?,
      blockId: blockId,
      start: action['start'] as int?,
      end: action['end'] as int?,
      page: action['page'] as int?,
    );
  }

  ConversationAnswerResult parseAnswerResult(
    Object? raw, {
    required ConversationTurn turn,
  }) {
    if (raw is! Map) throw const FormatException('模型返回内容必须为 JSON 对象');
    final result = Map<String, dynamic>.from(raw);
    final answer = result['answer'];
    if (answer is! String || answer.trim().isEmpty) {
      throw const FormatException('模型未返回有效回答');
    }
    final presentation = KnowledgeService.parseReadingPresentation(
      result['presentation'],
    );
    final evidence = _parseEvidence(result['evidence'], turn);
    return ConversationAnswerResult(
      answer: answer,
      presentation: presentation,
      evidence: evidence,
      remainingGaps: strings(result['remainingGaps']),
      proposals: _parseProposals(result['proposals'], turn, evidence),
    );
  }

  List<EvidenceAnchor> _parseEvidence(Object? raw, ConversationTurn turn) {
    if (raw == null) return const [];
    if (raw is! List) throw const FormatException('证据必须是数组');
    return raw
        .map((entry) {
          if (entry is! Map) throw const FormatException('证据锚点必须是 JSON 对象');
          final anchor = EvidenceAnchor.fromJson(
            Map<String, dynamic>.from(entry),
          );
          _validateEvidence(anchor, turn);
          return anchor;
        })
        .toList(growable: false);
  }

  void _validateEvidence(EvidenceAnchor anchor, ConversationTurn turn) {
    final visual = anchor.assetFingerprint == null
        ? null
        : turn.visualEvidence.where((candidate) {
            return candidate.sourceId == anchor.sourceId &&
                candidate.sourceVersion == anchor.sourceVersion &&
                candidate.assetFingerprint == anchor.assetFingerprint &&
                candidate.page == anchor.pdfPage;
          }).firstOrNull;
    if (visual != null) {
      anchor.unresolved = true;
      return;
    }
    final window = turn.windows.where((candidate) {
      final quoteMatches =
          anchor.quote.trim().isEmpty ||
          KnowledgeService.normalizeQuote(candidate.text)
              .contains(KnowledgeService.normalizeQuote(anchor.quote));
      return candidate.id == anchor.windowId &&
          candidate.sourceId == anchor.sourceId &&
          candidate.sourceVersion == anchor.sourceVersion &&
          candidate.blockId == anchor.blockId &&
          candidate.start == anchor.start &&
          candidate.end == anchor.end &&
          quoteMatches;
    }).firstOrNull;
    if (window == null) {
      throw const FormatException('回答引用了未提供或无法核实的证据窗口');
    }
  }

  List<KnowledgeProposal> _parseProposals(
    Object? raw,
    ConversationTurn turn,
    List<EvidenceAnchor> evidence,
  ) {
    if (raw == null) return const [];
    if (raw is! List) throw const FormatException('知识提案必须是数组');
    return raw
        .map((entry) {
          if (entry is! Map) throw const FormatException('知识提案必须是 JSON 对象');
          final value = Map<String, dynamic>.from(entry);
          final proposal = KnowledgeProposal(
            id: value['id'] as String? ?? newId(),
            topicId: value['topicId'] as String?,
            baseRevisionId: value['baseRevisionId'] as String?,
            title: value['title'] as String? ?? '',
            question: value['question'] as String? ?? turn.question,
            presentation: KnowledgeService.parseReadingPresentation(
              value['presentation'],
            ),
            inputItemIds: turn.inputItemIds,
            sourceVersions: turn.sourceVersions,
            sourceFingerprints: turn.sourceFingerprints,
            evidence: evidence,
            relatedTopicIds: strings(value['relatedTopicIds']),
            reason: value['reason'] as String? ?? '',
            originTurnId: turn.id,
            originSourceId: value['originSourceId'] as String?,
          );
          if (proposal.title.trim().isEmpty || proposal.presentation.isEmpty) {
            throw const FormatException('知识提案缺少标题或正文');
          }
          return proposal;
        })
        .toList(growable: false);
  }
}
