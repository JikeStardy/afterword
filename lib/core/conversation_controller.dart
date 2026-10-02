part of 'app_controller.dart';

extension ConversationController on AppController {
  Conversation _conversation(String id) =>
      data.conversations.firstWhere((c) => c.id == id);
  ConversationTurn _turn(String id) =>
      data.conversationTurns.firstWhere((t) => t.id == id);

  // Persist a detached snapshot before publishing. Keep shared item/topic identities.
  void _commitBusiness(
    void Function(AppData) apply, {
    RuntimeState? nextRuntime,
  }) {
    final draft = AppData.fromJson(data.toJson());
    apply(draft);
    store.saveWithRuntime(draft, nextRuntime ?? runtime);
    apply(data);
    if (nextRuntime != null) {
      final existingIds = runtime.jobs.map((j) => j.id).toSet();
      runtime.jobs.addAll(
        nextRuntime.jobs.where((j) => !existingIds.contains(j.id)),
      );
    }
    _emit();
  }

  bool _dependenciesCurrent(
    List<String> ids,
    Map<String, int> versions,
    Map<String, String> fingerprints,
  ) {
    if (ids.isEmpty || !_reusable(ids)) return false;
    if (fingerprints['settings'] != null &&
        fingerprints['settings'] != _dialogueSettingsFingerprint()) {
      return false;
    }
    for (final entry in fingerprints.entries.where(
      (e) => e.key.startsWith('knowledge:'),
    )) {
      final topicId = entry.key.substring('knowledge:'.length);
      final topic = data.topics.where((t) => t.id == topicId).firstOrNull;
      final revision = data.knowledgeRevisions
          .where((r) => r.id == topic?.currentKnowledgeRevisionId)
          .firstOrNull;
      if (revision == null || _revisionFingerprint(revision) != entry.value) {
        return false;
      }
    }
    for (final id in ids) {
      final item = data.items.where((i) => i.id == id).firstOrNull;
      if (item == null ||
          versions[id] != item.contentVersion ||
          fingerprints[id] != sourceFingerprint(item)) {
        return false;
      }
      final assetProof = fingerprints['asset:$id'];
      if (assetProof != null) {
        if (item.assets.isEmpty) return false;
        final file = File(assetPath(item.assets.first));
        if (!file.existsSync() ||
            sha256.convert(file.readAsBytesSync()).toString() != assetProof) {
          return false;
        }
      }
    }
    return true;
  }

  String _revisionFingerprint(KnowledgeRevision revision) =>
      sha256.convert(utf8.encode(jsonEncode(revision.toJson()))).toString();

  String _dialogueSettingsFingerprint() => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            data.settings.customInstructions,
            data.settings.explicitInterests,
            data.settings.confirmedInterests,
            data.topics
                .expand((t) => t.contextEntries)
                .map((c) => c.toJson())
                .toList(),
          ]),
        ),
      )
      .toString();

  bool isConversationTurnReusable(ConversationTurn turn) =>
      !turn.stale &&
      turn.status == 'completed' &&
      _dependenciesCurrent(
        turn.inputItemIds,
        turn.sourceVersions,
        turn.sourceFingerprints,
      );
  bool isKnowledgeRevisionReusable(KnowledgeRevision revision) =>
      !revision.stale &&
      _dependenciesCurrent(
        revision.inputItemIds,
        revision.sourceVersions,
        revision.sourceFingerprints,
      );

  List<LibraryItem> _conversationSources(
    Conversation conversation,
    String question,
  ) {
    Iterable<LibraryItem> sources = data.items.where((i) => i.isActive);
    final selected = conversation.sourceIds;
    if (selected != null && selected.isNotEmpty) {
      sources = sources.where((i) => selected.contains(i.id));
      if (sources.length != selected.toSet().length) {
        throw StateError('会话选择的来源已不可用，请新建会话');
      }
    } else if (conversation.scope == ConversationScope.item) {
      final item = _item(conversation.scopeId!);
      _requireActive(item);
      sources = [item];
    } else if (conversation.scope == ConversationScope.topic) {
      final topic = _topic(conversation.scopeId!);
      sources = sources.where(
        (i) =>
            topic.sourceIds.contains(i.id) ||
            relevance(
                  '${topic.title} ${topic.question}',
                  '${i.title} ${i.body}',
                ) >
                0,
      );
    }
    final ordered = sources.toList()
      ..sort(
        (a, b) => relevance(
          question,
          '${b.title} ${b.body}',
        ).compareTo(relevance(question, '${a.title} ${a.body}')),
      );
    // Explicit source selection is never silently dropped. The prompt rejects overflow.
    return (selected?.isNotEmpty ?? false) ||
            conversation.scope == ConversationScope.item
        ? ordered
        : ordered.take(16).toList();
  }

  Future<String> startConversation(
    ConversationScope scope, {
    String? scopeId,
    List<String>? sourceIds,
  }) async {
    if (scope == ConversationScope.item) _requireActive(_item(scopeId!));
    if (scope == ConversationScope.topic) _topic(scopeId!);
    for (final id in sourceIds ?? <String>[]) {
      _requireActive(_item(id));
    }
    final conversation = Conversation(
      id: newId(),
      scope: scope,
      scopeId: scopeId,
      sourceIds: sourceIds == null ? null : List.of(sourceIds),
      title: switch (scope) {
        ConversationScope.item => _item(scopeId!).title,
        ConversationScope.topic => _topic(scopeId!).title,
        ConversationScope.library => '知识库对话',
      },
    );
    _commitBusiness(
      (draft) =>
          draft.conversations.add(Conversation.fromJson(conversation.toJson())),
    );
    return conversation.id;
  }

  Future<String> submitQuestion(String conversationId, String question) async {
    final conversation = _conversation(conversationId);
    if (question.trim().isEmpty) throw const FormatException('请输入问题');
    if (data.conversationTurns.any(
      (t) =>
          t.conversationId == conversationId &&
          ['queued', 'running'].contains(t.status),
    )) {
      throw StateError('请等待当前回答完成，或先停止当前轮次');
    }
    if (!modelConfigured) throw StateError('请先配置文本模型和 API Key');
    final turn = ConversationTurn(
      id: newId(),
      conversationId: conversationId,
      question: question.trim(),
      callLimit: data.settings.conversationCallLimit,
      textBudgetChars: data.settings.modelTextContextChars,
    );
    final sources = _conversationSources(conversation, question);
    if (sources.isEmpty) throw StateError('当前范围没有可用资料');
    const ConversationService().buildPrompt(turn, sources);
    final nextRuntime = RuntimeState.fromJson(runtime.toJson());
    nextRuntime.jobs.add(
      BackgroundJob(
        id: newId(),
        type: 'conversation',
        entityId: turn.id,
        lane: 'interactive',
        epoch: runtime.epoch,
        checkpoint: {'configuration': _configurationSignature()},
      ),
    );
    _commitBusiness((draft) {
      draft.conversationTurns.add(ConversationTurn.fromJson(turn.toJson()));
      draft.conversations.firstWhere((c) => c.id == conversationId).updatedAt =
          turn.createdAt;
    }, nextRuntime: nextRuntime);
    _scheduleQueue();
    return turn.id;
  }

  Future<void> cancelTurn(String turnId) async {
    final job = runtime.jobs
        .where(
          (j) =>
              j.type == 'conversation' &&
              j.entityId == turnId &&
              ['queued', 'running', 'paused'].contains(j.status),
        )
        .firstOrNull;
    if (job != null) await cancelJob(job.id);
  }

  Future<void> retryTurn(String turnId) async {
    final turn = _turn(turnId);
    if (['queued', 'running', 'completed'].contains(turn.status)) return;
    if (turn.calls >= turn.callLimit) throw StateError('本轮调用预算已用完，请提交新问题');
    if (turn.inputItemIds.isNotEmpty &&
        !_dependenciesCurrent(
          turn.inputItemIds,
          turn.sourceVersions,
          turn.sourceFingerprints,
        )) {
      throw StateError('来源已变化，请提交新问题');
    }
    if (data.conversationTurns.any(
      (t) =>
          t.conversationId == turn.conversationId &&
          ['queued', 'running'].contains(t.status),
    )) {
      throw StateError('同一会话已有在途问题');
    }
    final oldJob = runtime.jobs
        .where((j) => j.type == 'conversation' && j.entityId == turnId)
        .lastOrNull;
    if (oldJob != null &&
        oldJob.checkpoint['configuration'] != _configurationSignature()) {
      throw StateError('模型配置已变化，请提交新问题');
    }
    final nextRuntime = RuntimeState.fromJson(runtime.toJson());
    nextRuntime.jobs.add(
      BackgroundJob(
        id: newId(),
        type: 'conversation',
        entityId: turnId,
        lane: 'interactive',
        epoch: runtime.epoch,
        checkpoint: {'configuration': _configurationSignature()},
      ),
    );
    _commitBusiness((draft) {
      final saved = draft.conversationTurns.firstWhere((t) => t.id == turnId);
      saved.status = 'queued';
      saved.error = '';
      // requestPending is retained until the explicitly requested next call completes.
    }, nextRuntime: nextRuntime);
    _scheduleQueue();
  }

  void _commitTurn(
    ConversationTurn turn, {
    List<KnowledgeProposal> proposals = const [],
  }) {
    DiagnosticScope.ensureAllowed();
    _commitBusiness((draft) {
      final index = draft.conversationTurns.indexWhere((t) => t.id == turn.id);
      draft.conversationTurns[index] = ConversationTurn.fromJson(turn.toJson());
      for (final proposal in proposals) {
        if (!draft.knowledgeProposals.any((p) => p.id == proposal.id)) {
          draft.knowledgeProposals.add(
            KnowledgeProposal.fromJson(proposal.toJson()),
          );
        }
      }
    });
  }

  void _markConversationFailure(BackgroundJob job, String error) {
    if (job.type != 'conversation') return;
    final turn = data.conversationTurns
        .where((t) => t.id == job.entityId)
        .firstOrNull;
    if (turn != null && turn.status != 'completed') {
      turn.status = 'paused';
      turn.error = error;
    }
  }

  void _recordInputs(ConversationTurn turn, Iterable<String> ids) {
    for (final id in ids.toSet()) {
      final item = _item(id);
      _requireActive(item);
      if (!turn.inputItemIds.contains(id)) turn.inputItemIds.add(id);
      final fingerprint = sourceFingerprint(item);
      if (turn.sourceFingerprints[id] != null &&
          turn.sourceFingerprints[id] != fingerprint) {
        throw const DiagnosticCancelled();
      }
      turn.sourceVersions[id] = item.contentVersion;
      turn.sourceFingerprints[id] = fingerprint;
    }
    diagnostics.addInputIds(turn.inputItemIds);
  }

  bool _segmentReusable(SourceSegmentSummary summary) {
    final source = data.items
        .where(
          (i) =>
              i.id == summary.sourceId &&
              i.isActive &&
              i.contentVersion == summary.sourceVersion,
        )
        .firstOrNull;
    if (source == null ||
        summary.promptVersion != SourceUnderstandingService.promptVersion) {
      return false;
    }
    if (summary.pdf) {
      final proof = summary.evidence.firstOrNull?.assetFingerprint;
      if (proof == null || source.assets.isEmpty) return false;
      final file = File(assetPath(source.assets.first));
      return file.existsSync() &&
          sha256.convert(file.readAsBytesSync()).toString() == proof;
    }
    // The exact original windows determine the neutral cache identity, never notes/persona.
    if (summary.evidence.isEmpty ||
        summary.evidence.any((e) => e.start == null || e.end == null)) {
      return false;
    }
    try {
      final windows = summary.evidence
          .map((e) => readSourceWindow(source, e.blockId, e.start!, e.end!))
          .toList();
      return SourceUnderstandingService(intelligence)
              .textFingerprint(source, windows) ==
          summary.fingerprint;
    } on FormatException {
      return false;
    }
  }

  void _inheritProofs(ConversationTurn turn, Map<String, String> proofs) {
    for (final entry in proofs.entries.where(
      (e) => e.key.startsWith('asset:') || e.key.startsWith('knowledge:'),
    )) {
      if (turn.sourceFingerprints[entry.key] != null &&
          turn.sourceFingerprints[entry.key] != entry.value) {
        throw const DiagnosticCancelled();
      }
      turn.sourceFingerprints[entry.key] = entry.value;
    }
  }

  ({
    List<KnowledgeRevision> knowledge,
    List<SourceSegmentSummary> summaries,
    Json context,
  })
  _dialogueKnowledge(ConversationTurn turn, Conversation conversation) {
    final allowedSources = turn.inputItemIds.toSet();
    final revisions =
        data.knowledgeRevisions
            .where(
              (r) =>
                  (conversation.scope != ConversationScope.topic ||
                      r.topicId == conversation.scopeId) &&
                  data.topics.any(
                    (t) => t.currentKnowledgeRevisionId == r.id,
                  ) &&
                  r.inputItemIds.every(allowedSources.contains) &&
                  isKnowledgeRevisionReusable(r),
            )
            .toList()
          ..sort(
            (a, b) => relevance(
              turn.question,
              b.presentation.fullText,
            ).compareTo(relevance(turn.question, a.presentation.fullText)),
          );
    final summaries = data.segmentSummaries
        .where(
          (s) =>
              turn.inputItemIds.contains(s.sourceId) &&
              turn.sourceVersions[s.sourceId] == s.sourceVersion &&
              _segmentReusable(s),
        )
        .take(8)
        .toList();
    for (final summary in summaries.where((s) => s.pdf)) {
      final proof = summary.evidence.firstOrNull?.assetFingerprint;
      if (proof != null) {
        _inheritProofs(turn, {'asset:${summary.sourceId}': proof});
      }
    }
    final selected = revisions.take(3).toList();
    for (final revision in selected) {
      _recordInputs(turn, revision.inputItemIds);
      _inheritProofs(turn, revision.sourceFingerprints);
      turn.sourceFingerprints['knowledge:${revision.topicId}'] =
          _revisionFingerprint(revision);
    }
    final contexts = data.topics
        .where(
          (t) => conversation.scope == ConversationScope.topic
              ? t.id == conversation.scopeId
              : true,
        )
        .expand((t) => t.contextEntries)
        .where(
          (c) =>
              _contextAllowed(c) &&
              c.confirmed &&
              c.active &&
              (c.sourceId != null
                  ? allowedSources.contains(c.sourceId)
                  : conversation.scope == ConversationScope.topic),
        )
        .take(5)
        .toList();
    _recordInputs(
      turn,
      contexts.where((c) => c.sourceId != null).map((c) => c.sourceId!),
    );
    return (
      knowledge: selected,
      summaries: summaries,
      context: {
        'userContext': contexts.map((c) => c.toJson()).toList(),
        'preferences': intelligence.preferences(data.settings),
      },
    );
  }

  Future<void> _executeConversationTurn(String turnId) async {
    var turn = ConversationTurn.fromJson(_turn(turnId).toJson());
    final conversation = _conversation(turn.conversationId);
    final sources = _conversationSources(conversation, turn.question);
    final lifecycle = _lifecycleRevision;
    final configuration = _configurationSignature();
    final baseRevisions = {
      for (final topic in data.topics)
        topic.id: topic.currentKnowledgeRevisionId,
    };
    void guard() {
      _guard(lifecycle);
      if (configuration != _configurationSignature() ||
          (turn.inputItemIds.isNotEmpty &&
              !_dependenciesCurrent(
                turn.inputItemIds,
                turn.sourceVersions,
                turn.sourceFingerprints,
              ))) {
        throw const DiagnosticCancelled();
      }
    }

    guard();
    _recordInputs(turn, sources.map((s) => s.id));
    turn.sourceFingerprints['settings'] = _dialogueSettingsFingerprint();
    final history = data.conversationTurns
        .where(
          (t) =>
              t.conversationId == conversation.id &&
              t.id != turn.id &&
              isConversationTurnReusable(t),
        )
        .toList();
    // Every history dependency is recorded even when the bounded prompt chooses only the latest answer.
    for (final old in history) {
      _recordInputs(turn, old.inputItemIds);
      _inheritProofs(turn, old.sourceFingerprints);
    }
    final knowledge = _dialogueKnowledge(turn, conversation);
    var candidates = retrieveSourceWindows(
      sources,
      turn.question,
      charBudget: (turn.textBudgetChars ~/ 3).clamp(1000, 14000),
    );
    final images = <String>[];
    const service = ConversationService();
    turn.status = 'running';
    turn.stage = '检索相关原文';
    _commitTurn(turn);
    Future<void> readVisual(LibraryItem item, {int? page}) async {
      guard();
      _requireActive(item);
      if (item.assets.isEmpty) throw StateError('来源附件不可用');
      if (images.length >= 4) throw StateError('本轮最多提供 4 张图片或 PDF 页，请缩小范围');
      final path = assetPath(item.assets.first);
      final bytes = await File(path).readAsBytes();
      guard();
      final fingerprint = sha256.convert(bytes).toString();
      if (turn.sourceFingerprints['asset:${item.id}'] != null &&
          turn.sourceFingerprints['asset:${item.id}'] != fingerprint) {
        throw const DiagnosticCancelled();
      }
      turn.sourceFingerprints['asset:${item.id}'] = fingerprint;
      if (page != null) {
        if (item.kind != ItemKind.pdf || page < 1) {
          throw const FormatException('PDF 页码无效');
        }
        final rendered = await native.renderPdf(
          path,
          startPage: page - 1,
          maxPages: 1,
        );
        guard();
        if (rendered.images.isEmpty || page > rendered.pageCount) {
          throw const FormatException('PDF 页码超出范围');
        }
        images.add('data:image/jpeg;base64,${rendered.images.first}');
      } else {
        if (item.kind != ItemKind.image) throw const FormatException('来源不是图片');
        images.add(
          'data:image/jpeg;base64,${await native.normalizeImage(path)}',
        );
        guard();
      }
      turn.visualEvidence.add(
        VisualEvidence(
          sourceId: item.id,
          sourceVersion: item.contentVersion,
          assetFingerprint: fingerprint,
          page: page,
          observation: page == null
              ? '已提供图片；GIF 仅首帧；视觉内容未经精确文字核验'
              : '已提供 PDF 第 $page 页；视觉内容未经精确文字核验',
        ),
      );
    }

    if (turn.visualEvidence.isNotEmpty) {
      final oldProofs = List.of(turn.visualEvidence);
      turn.visualEvidence = [];
      for (final proof in oldProofs) {
        await readVisual(_item(proof.sourceId), page: proof.page);
      }
    }
    if (turn.calls == 0 &&
        turn.visualEvidence.isEmpty &&
        conversation.scope == ConversationScope.item) {
      final item = sources.first;
      if (item.kind == ItemKind.image) await readVisual(item);
      if (item.kind == ItemKind.pdf) await readVisual(item, page: 1);
    }
    while (turn.calls < turn.callLimit) {
      guard();
      final promptTurn = ConversationTurn.fromJson(turn.toJson())
        ..windows = candidates;
      final prompt = service.buildPrompt(
        promptTurn,
        sources,
        history: history,
        knowledge: knowledge.knowledge,
        summaries: knowledge.summaries,
        extraContext: knowledge.context,
        imageCount: images.length,
        model: images.isEmpty
            ? data.settings.textModel
            : data.settings.visionModel,
        answerOnly: turn.calls == turn.callLimit - 1,
      );
      final provided = {
        for (final w in turn.windows) w.id: w,
        for (final w in prompt.windows) w.id: w,
      };
      turn.windows = provided.values.toList();
      turn.calls++;
      turn.requestPending = true;
      turn.stage = '模型思考 ${turn.calls} / ${turn.callLimit}';
      _commitTurn(turn);
      _saveCheckpoint(turn.stage, {
        'requestPending': true,
        'calls': turn.calls,
        'inputIds': turn.inputItemIds,
      });
      final settings = AppSettings.fromJson(data.settings.toJson())
        ..modelTextContextChars = turn.textBudgetChars;
      final raw = await intelligence.complete(
        settings,
        _apiKey,
        prompt.prompt,
        imageDataUrls: images,
      );
      guard();
      turn.requestPending = false;
      final step = service.parseModelStep(
        raw,
        turn: turn,
        answerOnly: turn.calls == turn.callLimit,
      );
      if (step.isAnswer) {
        final answer = step.answer!;
        turn.answer = [
          answer.answer,
          if (answer.remainingGaps.isNotEmpty)
            '尚缺证据：${answer.remainingGaps.join('；')}',
        ].join('\n\n');
        turn.evidence = answer.evidence;
        turn.status = 'completed';
        turn.stage = '回答完成';
        turn.completedAt = DateTime.now();
        turn.error = '';
        final proposals = <KnowledgeProposal>[];
        for (final draft in answer.proposals) {
          final topic = draft.topicId == null
              ? null
              : data.topics.where((t) => t.id == draft.topicId).firstOrNull;
          if (draft.topicId != null && topic == null) {
            throw const FormatException('提案引用了不存在的主题');
          }
          proposals.add(
            KnowledgeProposal(
              id: newId(),
              topicId: topic?.id,
              baseRevisionId: baseRevisions[topic?.id],
              title: draft.title,
              question: draft.question,
              presentation: draft.presentation,
              inputItemIds: List.of(turn.inputItemIds),
              sourceVersions: Map.of(turn.sourceVersions),
              sourceFingerprints: Map.of(turn.sourceFingerprints),
              evidence: turn.evidence,
              relatedTopicIds: draft.relatedTopicIds
                  .where((id) => data.topics.any((t) => t.id == id))
                  .toList(),
              reason: draft.reason,
              originTurnId: turn.id,
            ),
          );
        }
        guard();
        _commitTurn(turn, proposals: proposals);
        _saveCheckpoint('回答完成', {'requestPending': false});
        return;
      }
      _commitTurn(turn);
      for (final action in step.actions) {
        guard();
        turn.stage = '补读本地资料';
        _commitTurn(turn);
        if (action.type == 'search') {
          candidates = retrieveSourceWindows(
            sources,
            action.query,
            charBudget: (turn.textBudgetChars ~/ 3).clamp(1000, 14000),
            excludeWindowIds: turn.windows.map((w) => w.id).toSet(),
          );
          continue;
        }
        final item = sources.where((i) => i.id == action.sourceId).firstOrNull;
        if (item == null) throw const FormatException('读取动作超出会话来源范围');
        _requireActive(item);
        if (action.sourceVersion != null &&
            action.sourceVersion != item.contentVersion) {
          throw const FormatException('读取动作来源版本已变化');
        }
        if (action.type == 'readText') {
          if (action.start == null ||
              action.end == null ||
              action.end! - action.start! > turn.textBudgetChars ~/ 2) {
            throw const FormatException('读取文字范围无效或超出预算');
          }
          candidates = [
            readSourceWindow(
              item,
              action.blockId,
              action.start!,
              action.end!,
              readActionId: action.id,
            ),
          ];
        } else if (action.type == 'readPdf') {
          if (action.page == null) throw const FormatException('请指定 PDF 页码');
          await readVisual(item, page: action.page);
        } else if (action.type == 'readImage') {
          await readVisual(item);
        }
      }
    }
    throw StateError('本轮调用预算已用完，请提交新问题');
  }

  Future<String> proposeKnowledgeFromTurn(
    String turnId, {
    String? topicId,
  }) async {
    final turn = _turn(turnId);
    if (!isConversationTurnReusable(turn)) throw StateError('这条回答的来源已失效，请重新提问');
    final topic = topicId == null ? null : _topic(topicId);
    final proposal = KnowledgeProposal(
      id: newId(),
      topicId: topicId,
      baseRevisionId: topic?.currentKnowledgeRevisionId,
      title: topic?.title ?? _conversation(turn.conversationId).title,
      question: turn.question,
      presentation: ReadingPresentation(brief: turn.answer),
      inputItemIds: List.of(turn.inputItemIds),
      sourceVersions: Map.of(turn.sourceVersions),
      sourceFingerprints: Map.of(turn.sourceFingerprints),
      evidence: turn.evidence,
      originTurnId: turn.id,
      reason: '从对话回答提出知识更新，等待确认',
    );
    _commitBusiness(
      (draft) => draft.knowledgeProposals.add(
        KnowledgeProposal.fromJson(proposal.toJson()),
      ),
    );
    return proposal.id;
  }

  Future<String> acceptKnowledgeProposal(
    String proposalId, {
    ReadingPresentation? editedPresentation,
  }) async {
    final proposal = data.knowledgeProposals.firstWhere(
      (p) => p.id == proposalId,
    );
    if (proposal.status == 'accepted' && proposal.acceptedRevisionId != null) {
      return proposal.acceptedRevisionId!;
    }
    if (proposal.status != 'pending') throw StateError('该提案已处理或失效');
    final topic = proposal.topicId == null ? null : _topic(proposal.topicId!);
    if (topic?.currentKnowledgeRevisionId != proposal.baseRevisionId ||
        !_dependenciesCurrent(
          proposal.inputItemIds,
          proposal.sourceVersions,
          proposal.sourceFingerprints,
        )) {
      throw StateError('基础知识或来源已变化，请重新生成提案');
    }
    final revision = KnowledgeRevision(
      id: newId(),
      topicId: topic?.id ?? newId(),
      parentId: topic?.currentKnowledgeRevisionId,
      presentation: ReadingPresentation.fromJson(
        (editedPresentation ?? proposal.presentation).toJson(),
      ),
      inputItemIds: List.of(proposal.inputItemIds),
      sourceVersions: Map.of(proposal.sourceVersions),
      sourceFingerprints: Map.of(proposal.sourceFingerprints)
        ..remove('knowledge:${topic?.id}'),
      evidence: proposal.evidence,
      relatedTopicIds: proposal.relatedTopicIds,
      reason: proposal.reason,
      originTurnId: proposal.originTurnId,
      humanEdited: editedPresentation != null,
    );
    if (revision.presentation.isEmpty) throw const FormatException('知识正文不能为空');
    _commitBusiness((draft) {
      var target = draft.topics
          .where((t) => t.id == revision.topicId)
          .firstOrNull;
      if (target == null) {
        target = Topic(
          id: revision.topicId,
          title: proposal.title,
          question: proposal.question,
          sourceIds: proposal.inputItemIds,
        );
        draft.topics.add(target);
      }
      draft.knowledgeRevisions.add(
        KnowledgeRevision.fromJson(revision.toJson()),
      );
      target.currentKnowledgeRevisionId = revision.id;
      final p = draft.knowledgeProposals.firstWhere((p) => p.id == proposalId);
      p.status = 'accepted';
      p.acceptedRevisionId = revision.id;
    });
    return revision.id;
  }

  Future<void> rejectKnowledgeProposal(String proposalId) async {
    final proposal = data.knowledgeProposals.firstWhere(
      (p) => p.id == proposalId,
    );
    if (proposal.status != 'pending') return;
    _commitBusiness(
      (draft) =>
          draft.knowledgeProposals
                  .firstWhere((p) => p.id == proposalId)
                  .status =
              'rejected',
    );
  }

  Future<String> restoreKnowledgeRevision(String revisionId) async {
    final previous = data.knowledgeRevisions.firstWhere(
      (r) => r.id == revisionId,
    );
    final topic = _topic(previous.topicId);
    final restored = KnowledgeRevision.fromJson(previous.toJson())
      ..id = newId()
      ..parentId = topic.currentKnowledgeRevisionId
      ..createdAt = DateTime.now()
      ..reason = '恢复历史知识版本 $revisionId';
    restored.sourceFingerprints.remove('knowledge:${topic.id}');
    restored.stale = !_dependenciesCurrent(
      restored.inputItemIds,
      restored.sourceVersions,
      restored.sourceFingerprints,
    );
    _commitBusiness((draft) {
      draft.knowledgeRevisions.add(
        KnowledgeRevision.fromJson(restored.toJson()),
      );
      draft.topics
              .firstWhere((t) => t.id == topic.id)
              .currentKnowledgeRevisionId =
          restored.id;
    });
    return restored.id;
  }

  Future<void> _executeKnowledgeProposal(String topicId) async {
    final topic = _topic(topicId);
    final ids = strings(_currentJob?.checkpoint['newSourceIds']);
    final sources = data.items
        .where((i) => ids.contains(i.id) && i.isActive && _analysisReusable(i))
        .toList();
    if (sources.isEmpty) return;
    final turn = ConversationTurn(
      id: newId(),
      conversationId: 'proposal',
      question:
          '为主题“${topic.title}”提出增量知识修订。${topic.question}。区分新认识、分歧和待查证。只返回 answer、presentation、evidence，不直接写入。',
      callLimit: 1,
      textBudgetChars: data.settings.modelTextContextChars,
    );
    _recordInputs(turn, sources.expand(_sourceInputs));
    final currentRevision = data.knowledgeRevisions
        .where((r) => r.id == topic.currentKnowledgeRevisionId)
        .firstOrNull;
    if (currentRevision != null &&
        isKnowledgeRevisionReusable(currentRevision)) {
      _recordInputs(turn, currentRevision.inputItemIds);
      _inheritProofs(turn, currentRevision.sourceFingerprints);
    }
    turn.sourceFingerprints['settings'] = _dialogueSettingsFingerprint();
    final base = topic.currentKnowledgeRevisionId;
    final knowledge = _dialogueKnowledge(
      turn,
      Conversation(
        id: 'proposal',
        title: topic.title,
        scope: ConversationScope.topic,
        scopeId: topic.id,
      ),
    );
    turn.windows = retrieveSourceWindows(
      sources,
      '${topic.title} ${topic.question}',
      charBudget: turn.textBudgetChars ~/ 3,
    );
    final built = const ConversationService().buildPrompt(
      turn,
      sources,
      knowledge: knowledge.knowledge,
      summaries: knowledge.summaries,
      extraContext: {
        ...knowledge.context,
        'newAnalysis': sources
            .map(
              (i) => {
                'sourceId': i.id,
                'summary': i.analysis!.summary,
                'derived': true,
              },
            )
            .toList(),
      },
      answerOnly: true,
    );
    if (currentRevision != null &&
        isKnowledgeRevisionReusable(currentRevision) &&
        !built.knowledgeRevisionIds.contains(currentRevision.id)) {
      throw const FormatException('当前已确认知识超出上下文预算，无法安全生成替换提案；请提高预算或缩短知识页');
    }
    turn.windows = built.windows;
    final result = await intelligence.complete(
      data.settings,
      _apiKey,
      built.prompt,
    );
    DiagnosticScope.ensureAllowed();
    if (base != topic.currentKnowledgeRevisionId ||
        !_dependenciesCurrent(
          turn.inputItemIds,
          turn.sourceVersions,
          turn.sourceFingerprints,
        )) {
      throw const DiagnosticCancelled();
    }
    final answer = const ConversationService().parseAnswerResult(
      result,
      turn: turn,
    );
    final proposal = KnowledgeProposal(
      id: newId(),
      topicId: topic.id,
      baseRevisionId: base,
      title: topic.title,
      question: topic.question,
      presentation:
          answer.presentation ?? ReadingPresentation(brief: answer.answer),
      inputItemIds: turn.inputItemIds,
      sourceVersions: turn.sourceVersions,
      sourceFingerprints: turn.sourceFingerprints,
      evidence: answer.evidence,
      originSourceId: sources.last.id,
      reason: '新资料形成增量建议，确认后才更新知识',
    );
    _commitBusiness(
      (draft) => draft.knowledgeProposals.add(
        KnowledgeProposal.fromJson(proposal.toJson()),
      ),
    );
  }
}
