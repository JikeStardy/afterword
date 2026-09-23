part of 'app_controller.dart';

extension PersonalController on AppController {
  Future<void> completeToday(String entryId) async {
    final entry = todaySnapshot.entries
        .where((entry) => entry.id == entryId)
        .firstOrNull;
    if (entry == null) return;
    if (entry.entityType == 'item') {
      await setWorkState(entry.entityId, WorkState.done);
    } else if (entry.entityType == 'topic') {
      _topic(entry.entityId).reviewAt = null;
    }
    await dismissToday(entryId);
  }

  Future<void> updatePdfPageCount(String itemId, int pages) async {
    final item = _item(itemId);
    if (item.kind != ItemKind.pdf || pages < 1 || item.pdfPageCount == pages) {
      return;
    }
    item.pdfPageCount = pages;
    _save();
  }

  String _localDay(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  TodaySnapshot get todaySnapshot =>
      data.todaySnapshots
          .where((snapshot) => snapshot.day == _localDay(DateTime.now()))
          .firstOrNull ??
      TodaySnapshot(day: _localDay(DateTime.now()));

  bool _todayEligible(TodayEntry entry, DateTime now) {
    switch (entry.entityType) {
      case 'item':
        final item = data.items
            .where((i) => i.id == entry.entityId)
            .firstOrNull;
        return item != null &&
            item.isActive &&
            item.feedback >= 0 &&
            item.workState != WorkState.done &&
            item.snoozedUntil?.isAfter(now) != true;
      case 'topic':
        final topic = data.topics
            .where((t) => t.id == entry.entityId)
            .firstOrNull;
        return topic != null &&
            _topicSupported(topic) &&
            topic.snoozedUntil?.isAfter(now) != true &&
            (topic.inputItemIds == null || _reusable(topic.inputItemIds));
      case 'run':
        final run = data.runs.where((r) => r.id == entry.entityId).firstOrNull;
        return run != null && _reusableRun(run) && run.report.isNotEmpty;
      default:
        return false;
    }
  }

  Future<void> refreshToday({bool refill = false}) async {
    final now = DateTime.now(), day = _localDay(DateTime.now());
    var snapshot = data.todaySnapshots.where((s) => s.day == day).firstOrNull;
    final initial = snapshot == null;
    if (snapshot == null) {
      snapshot = TodaySnapshot(day: day);
      for (final old in data.todaySnapshots) {
        snapshot.deferredUntil.addAll(
          Map.fromEntries(
            old.deferredUntil.entries.where(
              (entry) => entry.value.isAfter(now),
            ),
          ),
        );
      }
      data.todaySnapshots.add(snapshot);
    }
    snapshot.entries.removeWhere(
      (entry) =>
          !_todayEligible(entry, now) ||
          snapshot!.skippedIds.contains(entry.id),
    );
    if (initial || refill) {
      final candidates = <({TodayEntry entry, int score})>[];
      final grouped = <String, TodayEntry>{};
      for (final item in data.items) {
        final entry = TodayEntry(
          id: 'item:${item.id}',
          entityType: 'item',
          entityId: item.id,
        );
        if (!_todayEligible(entry, now)) continue;
        final bodyKey = item.body.trim().replaceAll(RegExp(r'\s+'), ' ');
        final key = bodyKey.length > 80
            ? 'body:$bodyKey'
            : item.url.isNotEmpty
            ? 'url:${normalizedCaptureUrl(item.url)}'
            : 'id:${item.id}';
        final duplicate = grouped[key];
        if (duplicate != null) {
          duplicate.relatedIds.add(item.id);
          continue;
        }
        grouped[key] = entry;
        final interest = [
          ...data.settings.explicitInterests,
          ...data.settings.confirmedInterests,
        ].where((term) => relevance(term, itemSearchText(item)) > 0).toList();
        final insight =
            item.analysis?.stale != true &&
            _reusable(item.analysis?.inputItemIds) &&
            item.analysis!.structuredInsights.any(
              (i) =>
                  !i.stale &&
                  i.change.isNotEmpty &&
                  !['无关', '过时', 'irrelevant', 'outdated'].contains(i.verdict),
            );
        entry.reason = insight
            ? '已有值得核验的新认识，查看变化与证据'
            : item.workState == WorkState.reading
            ? '继续上次阅读，完成一次理解'
            : interest.isNotEmpty
            ? '与你关注的「${interest.first}」有关'
            : '尚待判断，决定精读、保留或跳过';
        final age = now.difference(item.createdAt).inDays.clamp(0, 90);
        candidates.add((
          entry: entry,
          score:
              (insight ? 400 : 0) +
              (item.workState == WorkState.reading ? 250 : 0) +
              interest.length * 80 +
              (item.feedback > 0 ? 30 : 0) +
              90 -
              age,
        ));
      }
      for (final topic in data.topics) {
        if (topic.reviewAt == null || topic.reviewAt!.isAfter(now)) continue;
        final entry = TodayEntry(
          id: 'topic:${topic.id}',
          entityType: 'topic',
          entityId: topic.id,
          reason: '你设置的复查时间已到，核对判断与未解决问题',
        );
        if (_todayEligible(entry, now)) {
          candidates.add((entry: entry, score: 1000));
        }
      }
      for (final run in data.runs) {
        if (!run.meaningful ||
            now.difference(run.completedAt ?? run.startedAt).inDays > 7) {
          continue;
        }
        final entry = TodayEntry(
          id: 'run:${run.id}',
          entityType: 'run',
          entityId: run.id,
          reason: '研究发现了重要变化，查看证据和待决策事项',
        );
        if (_todayEligible(entry, now)) {
          candidates.add((entry: entry, score: 700));
        }
      }
      candidates.sort((a, b) {
        final order = b.score.compareTo(a.score);
        return order != 0 ? order : a.entry.id.compareTo(b.entry.id);
      });
      for (final candidate in candidates) {
        if (snapshot.entries.length >= 5) break;
        final entry = candidate.entry;
        if (snapshot.skippedIds.contains(entry.id) ||
            snapshot.deferredUntil[entry.id]?.isAfter(now) == true ||
            snapshot.entries.any((old) => old.id == entry.id)) {
          continue;
        }
        snapshot.entries.add(entry);
      }
    }
    if (data.todaySnapshots.length > 30) {
      data.todaySnapshots.removeRange(0, data.todaySnapshots.length - 30);
    }
    _save();
  }

  Future<void> dismissToday(String entryId, {bool defer = false}) async {
    final snapshot = todaySnapshot;
    final entry = snapshot.entries.where((e) => e.id == entryId).firstOrNull;
    if (entry == null) return;
    snapshot.skippedIds.add(entry.id);
    snapshot.entries.remove(entry);
    if (defer) {
      final until = DateTime.now().add(const Duration(days: 1));
      snapshot.deferredUntil[entry.id] = until;
      if (entry.entityType == 'item') {
        final item = _item(entry.entityId);
        item.workState = WorkState.snoozed;
        item.snoozedUntil = until;
      } else if (entry.entityType == 'topic') {
        _topic(entry.entityId).snoozedUntil = until;
      }
    }
    _save();
  }

  Future<void> setWorkState(
    String itemId,
    WorkState state, {
    DateTime? until,
  }) async {
    final item = _item(itemId);
    item.workState = state;
    item.snoozedUntil = state == WorkState.snoozed
        ? until ?? DateTime.now().add(const Duration(days: 1))
        : null;
    await refreshToday();
  }

  Future<void> setFeedPaused(String feedId, bool paused) async {
    data.feeds.firstWhere((feed) => feed.id == feedId).paused = paused;
    _save();
  }

  Future<void> removeFeed(String feedId) async {
    data.feeds.removeWhere((feed) => feed.id == feedId);
    data.entries.removeWhere((entry) => entry.feedId == feedId);
    _save();
  }

  Future<void> processEntries(
    Iterable<String> ids, {
    bool skipped = true,
  }) async {
    final selected = ids.toSet();
    for (final entry in data.entries.where((e) => selected.contains(e.id))) {
      entry.processed = true;
      entry.skipped = skipped;
    }
    _save();
  }

  Future<void> updateReadingPosition(
    String itemId, {
    double? scrollOffset,
    String? blockId,
    int? pdfPage,
  }) async {
    final item = _item(itemId);
    final position = item.readingPosition ??= ReadingPosition();
    if (scrollOffset != null && scrollOffset.isFinite) {
      position.offset = scrollOffset.round().clamp(0, 10000000);
    }
    if (blockId != null) position.blockId = blockId;
    if (pdfPage != null && pdfPage > 0) position.pdfPage = pdfPage;
    _save();
  }

  Future<void> updateReaderFontScale(String itemId, double value) async {
    _item(itemId).readerFontScale = value.clamp(0.8, 1.8);
    _save();
  }

  Future<void> addAnnotation(
    String itemId, {
    required String quote,
    String? blockId,
    String note = '',
  }) async {
    final item = _item(itemId);
    if (quote.trim().isEmpty) throw const FormatException('请选择原文片段');
    final block = KnowledgeService.contentBlocksForItem(item)
        .where((block) => block['id'] == blockId)
        .firstOrNull;
    final text = block?['text'] as String? ?? item.body;
    final start = text.indexOf(quote);
    item.annotations.add(
      Annotation(
        id: newId(),
        note: note,
        highlightedText: quote,
        anchor: EvidenceAnchor(
          sourceId: item.id,
          sourceVersion: item.contentVersion,
          blockId: block?['id'] as String? ?? '',
          quote: quote,
          start: start >= 0 ? start : null,
          end: start >= 0 ? start + quote.length : null,
          unresolved: start < 0 || block == null,
        ),
      ),
    );
    _personalKnowledgeChanged(item);
  }

  Future<void> updateAnnotation(
    String itemId,
    String annotationId,
    String note,
  ) async {
    final item = _item(itemId);
    final annotation = item.annotations.firstWhere(
      (annotation) => annotation.id == annotationId,
    );
    if (annotation.note == note) return;
    annotation.note = note;
    annotation.updatedAt = DateTime.now();
    _personalKnowledgeChanged(item);
  }

  Future<void> updatePageNote(String itemId, int page, String note) async {
    final item = _item(itemId);
    if (item.kind != ItemKind.pdf ||
        page < 1 ||
        page > 100 ||
        (item.pdfPageCount != null && page > item.pdfPageCount!)) {
      throw const FormatException('PDF 页码需为 1–100');
    }
    final existing = item.annotations
        .where(
          (annotation) =>
              annotation.anchor.pdfPage == page &&
              annotation.highlightedText.isEmpty,
        )
        .firstOrNull;
    if (existing != null) {
      await updateAnnotation(itemId, existing.id, note);
      return;
    }
    item.annotations.add(
      Annotation(
        id: newId(),
        note: note,
        anchor: EvidenceAnchor(
          sourceId: item.id,
          sourceVersion: item.contentVersion,
          pdfPage: page,
        ),
      ),
    );
    item.readingPosition = ReadingPosition(pdfPage: page);
    _personalKnowledgeChanged(item);
  }

  Future<void> setInsightVerdict(
    String itemId,
    String insightId,
    String verdict,
  ) async {
    final insight = _item(itemId).analysis?.structuredInsights
        .where((i) => i.id == insightId)
        .firstOrNull;
    if (insight == null) throw StateError('观点不存在');
    if (!['认可', '存疑', '过时', '无关', ''].contains(verdict)) {
      throw const FormatException('未知反馈');
    }
    insight.verdict = verdict;
    insight.stale = verdict == '过时';
    _save();
  }

  bool _contextAllowed(ContextEntry entry) =>
      entry.active &&
      entry.confirmed &&
      (entry.sourceId == null ||
          data.items.any(
            (i) =>
                i.id == entry.sourceId &&
                i.isActive &&
                (entry.sourceVersion == null ||
                    i.contentVersion == entry.sourceVersion),
          ));

  Topic _promptTopic(Topic topic) {
    final copy = Topic.fromJson(topic.toJson());
    copy.contextEntries.removeWhere(
      (entry) =>
          !_contextAllowed(entry) ||
          (topic.selectedContextIds != null &&
              !topic.selectedContextIds!.contains(entry.id)),
    );
    return copy;
  }

  Set<String> _contextInputs(Topic topic) => {
    for (final entry in _promptTopic(topic).contextEntries)
      if (entry.sourceId != null) entry.sourceId!,
  };

  Future<void> addTopicContext(
    String topicId, {
    required String kind,
    required String text,
    bool confirmed = true,
    String? sourceId,
  }) async {
    if (text.trim().isEmpty) throw const FormatException('背景内容不能为空');
    final topic = _topic(topicId);
    final source = sourceId == null ? null : _item(sourceId);
    if (source != null) _requireActive(source);
    topic.contextEntries.add(
      ContextEntry(
        id: newId(),
        kind: kind,
        text: text.trim(),
        confirmed: confirmed,
        sourceId: sourceId,
        sourceVersion: source?.contentVersion,
      ),
    );
    _contextChanged(topic);
  }

  Future<void> updateTopicContext(
    String topicId,
    String entryId, {
    String? text,
    String? kind,
    bool? confirmed,
    bool? active,
  }) async {
    final topic = _topic(topicId),
        entry = _topic(topicId).contextEntries
            .firstWhere((e) => e.id == entryId);
    if (text != null && text.trim().isEmpty) {
      throw const FormatException('背景内容不能为空');
    }
    if (text != null) entry.text = text.trim();
    if (kind != null) entry.kind = kind;
    if (confirmed != null) entry.confirmed = confirmed;
    if (active != null) entry.active = active;
    entry.updatedAt = DateTime.now();
    _contextChanged(topic);
  }

  Future<void> updateTopicScope(
    String topicId, {
    List<String>? sourceIds,
    List<String>? contextIds,
  }) async {
    final topic = _topic(topicId);
    if (sourceIds != null &&
        sourceIds.any((id) => !_knowledgeSources.any((i) => i.id == id))) {
      throw StateError('选中的资料已不可用于研究');
    }
    topic.selectedSourceIds = sourceIds?.toSet().toList();
    topic.selectedContextIds = contextIds?.toSet().toList();
    _contextChanged(topic);
  }

  void _contextChanged(Topic topic) {
    topic.overviewStale = true;
    _invalidateTasks();
    _save();
    _scheduleTopicRefresh(topic.id);
  }

  void _scheduleTopicRefresh(String topicId) {
    _refreshTimers.remove(topicId)?.cancel();
    if (_digestOnly || !modelConfigured) return;
    _refreshTimers[topicId] = Timer(const Duration(seconds: 2), () {
      _refreshTimers.remove(topicId);
      if (_disposed || (!_foreground && !_serviceStarted)) return;
      unawaited(
        queueSynthesis(topicId).catchError((Object error) {
          if (!_disposed) {
            lastError = '主题更新待重试：$error';
            _emit();
          }
          return '';
        }),
      );
    });
  }

  Future<void> setTopicReview(String topicId, DateTime? date) async {
    _topic(topicId).reviewAt = date;
    _topic(topicId).snoozedUntil = null;
    await refreshToday(refill: true);
  }

  void _queueResearchNotice(Topic topic, ResearchRun run) {
    if (!data.settings.researchNotifications || !_reusableRun(run)) return;
    final now = DateTime.now();
    if (topic.snoozedUntil?.isAfter(now) == true) return;
    final recent = runtime.outbox.where(
      (n) =>
          n.channel == 'research' &&
          n.entityId == topic.id &&
          now.difference(n.createdAt) < const Duration(hours: 12),
    );
    if (recent.isNotEmpty) return;
    final id = 'research:${run.id}';
    if (runtime.outbox.any((n) => n.id == id)) return;
    final message = '${topic.title}有值得关注的新研究结果';
    _notice(message);
    runtime.outbox.add(
      PendingNotification(
        id: id,
        channel: 'research',
        title: '研究有新发现',
        body: searchSnippet(run.report, '', length: 120),
        entityType: 'topic',
        entityId: topic.id,
      ),
    );
  }

  Future<void> sendDailyDigest() async {
    try {
      if (!data.settings.digestEnabled || !data.settings.digestNotifications) {
        return;
      }
      await refreshToday();
      final snapshot = todaySnapshot,
          id = 'digest:${_localDay(DateTime.now())}';
      if (snapshot.entries.isEmpty ||
          runtime.outbox.any((entry) => entry.id == id)) {
        return;
      }
      runtime.outbox.add(
        PendingNotification(
          id: id,
          channel: 'digest',
          title: '今日关注',
          body: '有 ${snapshot.entries.length} 项资料或问题值得看看，点击查看推荐理由',
          entityType: 'today',
        ),
      );
      _save();
      // A digest-only wake never retries unrelated result/research notifications.
      final entry = runtime.outbox.last;
      final posted = await native.publishNotification(
        id: entry.id,
        channel: entry.channel,
        title: entry.title,
        body: entry.body,
        entityType: 'today',
      );
      if (!posted) {
        notificationsAllowed = false;
        _save();
        return;
      }
      entry.delivered = true;
      _save();
    } catch (error) {
      lastError = '每日汇总未发送：$error';
      _emit();
    } finally {
      await native.finishDigest();
    }
  }

  Future<void> refreshNotificationPermission({bool request = false}) async {
    if (request) await native.requestNotificationPermission();
    notificationsAllowed = await native.notificationStatus();
    if (!_disposed) _emit();
  }

  Future<void> updateNotificationSettings({
    bool? digestEnabled,
    int? hour,
    int? minute,
    bool? results,
    bool? research,
    bool? progress,
  }) async {
    final settings = data.settings;
    if ((hour != null && (hour < 0 || hour > 23)) ||
        (minute != null && (minute < 0 || minute > 59))) {
      throw const FormatException('通知时间无效');
    }
    if (digestEnabled != null) {
      settings.digestEnabled = digestEnabled;
      settings.digestNotifications = digestEnabled;
    }
    if (hour != null) settings.digestHour = hour;
    if (minute != null) settings.digestMinute = minute;
    if (results != null) settings.resultNotifications = results;
    if (research != null) settings.researchNotifications = research;
    if (progress != null) settings.progressNotifications = progress;
    _save();
    await native.configureDigest(
      enabled: settings.digestEnabled && settings.digestNotifications,
      hour: settings.digestHour,
      minute: settings.digestMinute,
    );
  }

  void consumeNavigation() {
    pendingNavigation = null;
  }

  Future<void> retryJob(String jobId) async {
    final job = runtime.jobs.firstWhere((j) => j.id == jobId);
    if (job.status == 'running') return;
    if (['capture', 'analysis', 'fetch'].contains(job.type)) {
      _requireActive(_item(job.entityId));
    }
    await _startUserWork();
    job.status = 'queued';
    job.error = '';
    job.attempts = 0;
    job.epoch = runtime.epoch;
    job.checkpoint['requiresAttention'] = false;
    if (['analysis', 'capture', 'synthesis'].contains(job.type)) {
      job.checkpoint.removeWhere(
        (key, _) => !const {
          'fetched',
          'imageUrls',
          'savedImages',
          'configuration',
        }.contains(key),
      );
    }
    job.checkpoint['configuration'] = _configurationSignature();
    _save();
    _scheduleQueue();
  }
}
