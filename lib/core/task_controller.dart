part of 'app_controller.dart';

extension TaskController on AppController {
  bool get digestOnly => _digestOnly;
  Future<void> activateInteractive() async {
    if (_interactiveFuture != null) return _interactiveFuture!;
    if (!_digestOnly) return;
    _interactiveFuture = initialize();
    try {
      await _interactiveFuture;
    } finally {
      _interactiveFuture = null;
    }
  }

  void setForeground(bool foreground) {
    if (_foreground != foreground) {
      diagnostics.log(
        DiagnosticLevel.info,
        'lifecycle',
        'foreground.change',
        data: {'foreground': foreground},
      );
    }
    _foreground = foreground;
  }

  void bindNativeRuntime() {
    native.setRuntimeEventListener((event) {
      unawaited(
        _handleRuntimeEvent(event).catchError((Object error) {
          if (!_disposed) {
            lastError = '后台状态更新失败：$error';
            _emit();
          }
        }),
      );
    });
  }

  Future<void> _handleRuntimeEvent(NativeRuntimeEvent event) async {
    logRuntimeEvent(event);
    switch (event.kind) {
      case 'interactive':
        await activateInteractive();
        _foreground = true;
        await resume();
      case 'cancelAll':
        await pauseTasks(cancelled: true);
      case 'timeout':
        await pauseTasks();
      case 'digest':
        await sendDailyDigest();
      case 'openEntity':
        pendingNavigation = {
          'entityType': event.entityType ?? 'today',
          'entityId': event.entityId ?? '',
        };
        _emit();
    }
  }

  List<BackgroundJob> get pendingJobs => runtime.jobs
      .where((job) => ['queued', 'running', 'paused'].contains(job.status))
      .toList();

  Future<void> _startUserWork() async {
    if (_digestOnly) throw StateError('每日汇总不会启动分析任务');
    if (_serviceStarted) return;
    _logDiagnosticEvent(
      DiagnosticLevel.info,
      'background',
      'service.start.request',
    );
    try {
      await native.startBackgroundWork();
      _serviceStarted = true;
      _logDiagnosticEvent(
        DiagnosticLevel.info,
        'background',
        'service.start.success',
      );
    } catch (error) {
      _logDiagnosticEvent(
        DiagnosticLevel.error,
        'background',
        'service.start.failure',
        error: error,
      );
      rethrow;
    }
  }

  String _configurationSignature() => jsonEncode([
    data.settings.endpoint,
    data.settings.textModel,
    data.settings.visionModel,
    data.settings.searchEndpoint,
  ]);

  BackgroundJob _enqueue(
    String type,
    String entityId, {
    Json? checkpoint,
    String lane = 'background',
  }) {
    final existing = runtime.jobs
        .where(
          (job) =>
              job.type == type &&
              job.entityId == entityId &&
              ['queued', 'running'].contains(job.status),
        )
        .firstOrNull;
    if (existing != null) return existing;
    final job = BackgroundJob(
      id: newId(),
      type: type,
      entityId: entityId,
      epoch: runtime.epoch,
      lane: lane,
      checkpoint: {'configuration': _configurationSignature(), ...?checkpoint},
    );
    runtime.jobs.add(job);
    return job;
  }

  void _scheduleQueue() {
    if (_digestOnly || _disposed) return;
    for (final lane in ['background', 'interactive']) {
      final running = lane == 'background'
          ? _queueFuture
          : _conversationQueueFuture;
      if (running != null ||
          !runtime.jobs.any((j) => j.status == 'queued' && j.lane == lane)) {
        continue;
      }
      final future = Zone.root.run(() => Future<void>(() => _drainQueue(lane)));
      if (lane == 'background') {
        _queueFuture = future;
      } else {
        _conversationQueueFuture = future;
      }
      unawaited(
        future.catchError((Object error, StackTrace stack) {
          if (!_disposed) {
            lastError = '任务暂停：${diagnostics.sanitize(error.toString())}';
            _emit();
          }
        }),
      );
    }
  }

  Future<void> waitForIdle() async {
    while (_queueFuture != null || _conversationQueueFuture != null) {
      await Future.wait([?_queueFuture, ?_conversationQueueFuture]);
    }
  }

  bool _jobIsCurrent(BackgroundJob job) =>
      !_disposed &&
      job.epoch == runtime.epoch &&
      job.status == 'running' &&
      identical(_runningJobs[job.id]?.job, job) &&
      !_runningJobs[job.id]!.cancelled.isCompleted;

  bool _preflightJob(BackgroundJob job) {
    String? error;
    if (!const {1, 2}.contains(job.version) ||
        !const {
          'capture',
          'fetch',
          'analysis',
          'synthesis',
          'research',
          'conversation',
          'knowledgeProposal',
        }.contains(job.type)) {
      error = '任务版本或类型不受支持，请重新提交';
    } else if (job.checkpoint['sourceReplaced'] == true) {
      error = '正文已补全，请从资料页重新提交';
    } else if (job.checkpoint['configuration'] != _configurationSignature()) {
      error = '服务配置已变化，请手动重试';
    } else if (job.checkpoint['contentVersion'] case final int version) {
      final item = data.items.where((i) => i.id == job.entityId).firstOrNull;
      if (item == null ||
          item.contentVersion != version ||
          item.bodyOrigin != job.checkpoint['bodyOrigin']) {
        error = '正文已更新，请从资料页重新提交';
      }
    }
    if (job.checkpoint['inputIds'] case final List ids) {
      if (!_reusable(ids.whereType<String>().toList())) error = '任务来源已失效，请重新提交';
    }
    if (error == null) return true;
    job.status = 'paused';
    job.error = error;
    job.checkpoint['requiresAttention'] = true;
    _markConversationFailure(job, error);
    _save();
    return false;
  }

  Future<void> _stopServiceIfIdle({bool force = false}) async {
    if (_active != 0 ||
        _queueFuture != null ||
        _conversationQueueFuture != null ||
        (!force && !_serviceStarted) ||
        runtime.jobs.any((job) => ['queued', 'running'].contains(job.status))) {
      return;
    }
    _serviceStarted = false;
    _logDiagnosticEvent(
      DiagnosticLevel.info,
      'background',
      'service.stop.request',
      data: {'force': force},
    );
    try {
      await native.stopBackgroundWork();
      _logDiagnosticEvent(
        DiagnosticLevel.info,
        'background',
        'service.stop.success',
      );
    } catch (error) {
      _logDiagnosticEvent(
        DiagnosticLevel.warn,
        'background',
        'service.stop.failure',
        error: error,
      );
    }
  }

  Future<void> _drainQueue(String lane) async {
    try {
      while (!_disposed && !_digestOnly) {
        final queued = runtime.jobs.where(
          (j) => j.status == 'queued' && j.lane == lane,
        );
        final job =
            queued.where((j) => j.checkpoint['tracking'] != true).firstOrNull ??
            queued.firstOrNull;
        if (job == null) break;
        if (job.epoch != runtime.epoch) {
          job.status = 'cancelled';
          _save();
          continue;
        }
        if (!_preflightJob(job)) continue;
        final context = JobExecutionContext(job);
        _runningJobs[job.id] = context;
        await runZoned(
          () => _executeQueuedJob(job),
          zoneValues: {
            _jobContextKey: context,
            IntelligenceService.requestAbortKey: context.cancelled.future,
          },
        );
      }
    } finally {
      if (!_disposed) {
        if (lane == 'background') {
          _queueFuture = null;
        } else {
          _conversationQueueFuture = null;
        }
        try {
          await _stopServiceIfIdle();
        } finally {
          _emit();
        }
        if (runtime.jobs.any((job) => job.status == 'queued')) _scheduleQueue();
      } else {
        if (lane == 'background') {
          _queueFuture = null;
        } else {
          _conversationQueueFuture = null;
        }
      }
    }
  }

  Future<void> _executeQueuedJob(BackgroundJob job) async {
    job.status = 'running';
    job.error = '';
    job.attempts++;
    _save();
    try {
      await _startUserWork();
      await _publishProgress(job);
      await _work(
        () async {
          switch (job.type) {
            case 'capture':
            case 'fetch':
            case 'analysis':
              final item = _item(job.entityId);
              _requireActive(item);
              if (job.type != 'analysis' && job.checkpoint['fetched'] != true) {
                await _fetch(item);
                if (!_jobIsCurrent(job)) throw const DiagnosticCancelled();
                if (item.status == 'failed') throw StateError(item.error);
                job.checkpoint['fetched'] = true;
                _save();
              }
              if (job.type != 'fetch' && job.checkpoint['analyzed'] != true) {
                await analyze(item.id);
                if (!_jobIsCurrent(job)) throw const DiagnosticCancelled();
                if (item.status == 'waiting') {
                  job.status = 'paused';
                  job.error = item.error;
                } else if (item.status != 'ready') {
                  throw StateError(item.error.isEmpty ? '分析尚未完成' : item.error);
                }
              }
              if (job.type != 'fetch' &&
                  job.checkpoint['analyzed'] == true &&
                  job.checkpoint['topicsUpdated'] != true) {
                await _updateInterests(item);
                _saveCheckpoint('主题更新完成', {'topicsUpdated': true});
              }
            case 'conversation':
              await _executeConversationTurn(job.entityId);
            case 'knowledgeProposal':
              await _executeKnowledgeProposal(job.entityId);
            case 'synthesis':
              await synthesizeTopic(job.entityId);
              final topic = _topic(job.entityId);
              if (topic.status != 'ready') throw StateError(topic.error);
            case 'research':
              final run = data.runs.firstWhere((run) => run.id == job.entityId);
              final topic = run.topicId == null ? null : _topic(run.topicId!);
              if (!_reusable(run.inputItemIds)) throw StateError('研究来源已失效');
              await _executeResearch(
                goal: run.goal,
                topic: topic,
                callLimit: run.callLimit,
                originInputs: run.inputItemIds!.toSet(),
                existingRun: run,
                authorized: () =>
                    _jobIsCurrent(job) &&
                    (job.checkpoint['tracking'] != true ||
                        (topic != null &&
                            topic.tracking &&
                            topic.authorizedScope == run.goal)),
              );
              final saved = data.runs.firstWhere((r) => r.id == run.id);
              if (saved.status == 'failed' || saved.status == 'paused') {
                throw StateError(saved.error.isEmpty ? '研究已暂停' : saved.error);
              }
              if (topic != null && job.checkpoint['tracking'] == true) {
                topic.lastRun = DateTime.now();
                topic.nextRun = DateTime.now().add(
                  Duration(hours: topic.intervalHours),
                );
                topic.status = saved.status;
                if (saved.meaningful) _queueResearchNotice(topic, saved);
              }
          }
        },
        type: job.type,
        title: '后台${_jobTitle(job)}',
        entityId: job.entityId,
        authorized: () => _jobIsCurrent(job),
      );
      if (_jobIsCurrent(job)) {
        job.status = 'complete';
        job.stage = '完成';
        _queueTaskNotice(job, success: true);
      }
    } on DiagnosticCancelled {
      if (job.status == 'running') {
        job.status = 'cancelled';
        job.error = '来源或配置已变化，本轮停止';
      }
      _markJobInterrupted(job);
    } catch (error) {
      if (_jobIsCurrent(job)) {
        job.error = diagnostics.sanitize(error.toString()).toString();
        final transient = RegExp(
          r'\b(408|429|500|502|503|504)\b|SocketException|TimeoutException|网络超时',
        ).hasMatch(job.error);
        if (job.type != 'conversation' && transient && job.attempts < 3) {
          await Future<void>.delayed(
            Duration(milliseconds: 400 << (job.attempts - 1)),
          );
          if (_jobIsCurrent(job)) job.status = 'queued';
        } else {
          job.status = 'paused';
          _markConversationFailure(job, job.error);
          job.checkpoint['requiresAttention'] = true;
          _queueTaskNotice(job, success: false);
        }
      }
    } finally {
      if (!_disposed) {
        job.updatedAt = DateTime.now();
        _save();
        await _flushNotifications();
      }
      _runningJobs.remove(job.id);
    }
  }

  String _jobTitle(BackgroundJob job) => switch (job.type) {
    'conversation' => '知识对话',
    'knowledgeProposal' => '知识更新建议',
    'research' => '研究',
    'synthesis' => '主题更新',
    'fetch' => '抓取',
    _ => '分析',
  };

  Future<void> _publishProgress(BackgroundJob job) async {
    await native.updateBackgroundProgress(
      jobId: job.id,
      title: _jobTitle(job),
      stage: data.settings.progressNotifications ? job.stage : '正在处理',
      completed: (job.checkpoint['completed'] as num?)?.toInt() ?? 0,
      total: (job.checkpoint['total'] as num?)?.toInt() ?? 0,
    );
  }

  void _saveCheckpoint(String stage, Json values) {
    final job = _currentJob;
    if (job == null) return;
    if (!_jobIsCurrent(job)) throw const DiagnosticCancelled();
    job.stage = stage;
    job.checkpoint.addAll(values);
    _save();
    unawaited(
      _publishProgress(job).catchError((Object error) {
        if (!_disposed) {
          lastError = '进度通知不可用：$error';
          _emit();
        }
      }),
    );
  }

  Future<String> queueAnalysis(String itemId) async {
    _requireActive(_item(itemId));
    await _startUserWork();
    final job = _enqueue('analysis', itemId);
    _save();
    _scheduleQueue();
    return job.id;
  }

  Future<String> queueSynthesis(String topicId) async {
    _topic(topicId);
    await _startUserWork();
    final job = _enqueue('synthesis', topicId);
    _save();
    _scheduleQueue();
    return job.id;
  }

  Future<void> retryCapture(String itemId) async {
    final item = _item(itemId);
    _requireActive(item);
    if (item.kind != ItemKind.web) throw StateError('只有网页支持重新抓取');
    await _startUserWork();
    _enqueue('fetch', itemId);
    _save();
    _scheduleQueue();
  }

  Future<void> retryImages(String itemId) async {
    final item = _item(itemId);
    _requireActive(item);
    final previous = runtime.jobs.reversed
        .where(
          (job) =>
              job.entityId == itemId && job.checkpoint['imageUrls'] is List,
        )
        .firstOrNull;
    if (previous == null) throw StateError('缺少原始图片地址，请重新抓取正文');
    if (previous.checkpoint['contentVersion'] != null &&
        (previous.checkpoint['contentVersion'] != item.contentVersion ||
            previous.checkpoint['bodyOrigin'] != item.bodyOrigin)) {
      throw StateError('图片记录对应旧正文，请重新打开页面保存');
    }
    await _startUserWork();
    _enqueue(
      'fetch',
      itemId,
      checkpoint: {
        'articleFetched': true,
        'imageUrls': previous.checkpoint['imageUrls'],
        'savedImages': previous.checkpoint['savedImages'] ?? {},
        if (previous.checkpoint['contentVersion'] != null) ...{
          'contentVersion': previous.checkpoint['contentVersion'],
          'bodyOrigin': previous.checkpoint['bodyOrigin'],
        },
      },
    );
    _save();
    _scheduleQueue();
  }

  Future<void> cancelJob(String jobId) async {
    final job = runtime.jobs.where((j) => j.id == jobId).firstOrNull;
    if (job == null || !['queued', 'running', 'paused'].contains(job.status)) {
      return;
    }
    job.status = 'cancelled';
    job.error = '用户已取消';
    _markJobInterrupted(job);
    _runningJobs[job.id]?.cancel();
    final item = data.items.where((i) => i.id == job.entityId).firstOrNull;
    if (item != null && ['analyzing', 'pending'].contains(item.status)) {
      item.status = 'interrupted';
      item.error = '用户已取消；原始资料仍保留';
    }
    _save();
  }

  Future<void> pauseTasks({bool cancelled = false}) async {
    diagnostics.log(
      DiagnosticLevel.warn,
      'background',
      'tasks.pause',
      data: {'cancelled': cancelled, 'pending': pendingJobs.length},
    );
    _lifecycleRevision++;
    for (final context in _runningJobs.values) {
      context.cancel();
    }
    for (final job in pendingJobs) {
      job.status = cancelled ? 'cancelled' : 'paused';
      job.error = cancelled ? '用户已取消' : '系统暂停，重新打开后继续';
      _markJobInterrupted(job);
      final item = data.items.where((i) => i.id == job.entityId).firstOrNull;
      if (item != null && ['analyzing', 'pending'].contains(item.status)) {
        item.status = 'interrupted';
        item.error = job.error;
      }
      final topic = data.topics.where((t) => t.id == job.entityId).firstOrNull;
      if (topic != null && topic.status == 'synthesizing') {
        topic.status = 'interrupted';
      }
    }
    _save();
    await native.stopBackgroundWork();
    _serviceStarted = false;
  }

  void _markJobInterrupted(BackgroundJob job) {
    final turn = data.conversationTurns
        .where((t) => t.id == job.entityId)
        .firstOrNull;
    if (turn != null && ['queued', 'running', 'paused'].contains(turn.status)) {
      turn.status = job.status == 'cancelled' ? 'cancelled' : 'interrupted';
      turn.error = job.error;
    }
    final run = data.runs.where((run) => run.id == job.entityId).firstOrNull;
    if (run != null) {
      run.status = 'interrupted';
      run.error = job.error;
    }
    final topic = data.topics
        .where((topic) => topic.id == job.entityId)
        .firstOrNull;
    if (topic != null && ['queued', 'synthesizing'].contains(topic.status)) {
      topic.status = 'interrupted';
      topic.error = job.error;
    }
  }

  Future<void> resumeTasks() async {
    if (_digestOnly || _disposed) return;
    diagnostics.log(
      DiagnosticLevel.info,
      'background',
      'tasks.resume.start',
      data: {'jobs': runtime.jobs.length},
    );
    for (final job in runtime.jobs) {
      if (job.type == 'conversation' &&
          ['running', 'paused'].contains(job.status) &&
          !_runningJobs.containsKey(job.id)) {
        job.status = 'paused';
        job.checkpoint['requiresAttention'] = true;
        _markJobInterrupted(job);
        continue;
      }
      if (job.epoch != runtime.epoch ||
          job.checkpoint['requiresAttention'] == true) {
        continue;
      }
      if (['running', 'paused'].contains(job.status) &&
          !_runningJobs.containsKey(job.id)) {
        if (job.checkpoint['inputIds'] case final List inputs) {
          if (!_reusable(inputs.whereType<String>().toList())) {
            job.status = 'cancelled';
            job.error = '研究来源已失效，请重新提交';
            continue;
          }
        }
        if (job.checkpoint['configuration'] != _configurationSignature()) {
          job.status = 'paused';
          job.error = '服务配置已变化，请重新提交';
          job.checkpoint['requiresAttention'] = true;
          continue;
        }
        job.status = 'queued';
        if (job.checkpoint['requestPending'] == true) {
          _notice('上次请求结果未保存，恢复可能再次调用服务并产生费用');
        }
        if (job.type == 'research' &&
            data.runs.any(
              (run) => run.id == job.entityId && run.requestPending,
            )) {
          _notice('上次研究请求结果未保存，恢复可能重复计费；原调用预算继续累计');
        }
      }
    }
    _save();
    if (runtime.jobs.any((j) => j.status == 'queued')) {
      await _startUserWork();
      _scheduleQueue();
    }
    await _flushNotifications();
    diagnostics.log(
      DiagnosticLevel.info,
      'background',
      'tasks.resume.complete',
      data: {'queued': runtime.jobs.where((j) => j.status == 'queued').length},
    );
  }

  void _queueTaskNotice(BackgroundJob job, {required bool success}) {
    if (job.checkpoint['tracking'] == true && success) return;
    if (!data.settings.resultNotifications) return;
    final id = '${job.id}:${job.status}:${job.attempts}';
    if (runtime.outbox.any((entry) => entry.id == id)) return;
    runtime.outbox.add(
      PendingNotification(
        id: id,
        channel: 'results',
        title: success ? '${_jobTitle(job)}已完成' : '${_jobTitle(job)}需要处理',
        body: success ? '点击查看结果' : job.error,
        entityType: job.type == 'conversation'
            ? 'conversation'
            : job.type == 'knowledgeProposal'
            ? 'knowledge'
            : job.type == 'research'
            ? 'run'
            : job.type == 'synthesis'
            ? 'topic'
            : 'item',
        entityId: job.entityId,
      ),
    );
  }

  Future<void> _flushNotifications() async {
    for (final entry
        in runtime.outbox.where((entry) => !entry.delivered).toList()) {
      if (_disposed) return;
      final enabled = switch (entry.channel) {
        'results' => data.settings.resultNotifications,
        'research' => data.settings.researchNotifications,
        'digest' =>
          data.settings.digestEnabled && data.settings.digestNotifications,
        _ => false,
      };
      final expiredDigest =
          entry.channel == 'digest' &&
          entry.id != 'digest:${_localDay(DateTime.now())}';
      final sourceExcluded = switch (entry.entityType) {
        'conversation' => !data.conversationTurns.any(
          (t) => t.id == entry.entityId && _reusable(t.inputItemIds),
        ),
        'knowledge' => !data.topics.any((t) => t.id == entry.entityId),
        'item' => !data.items.any(
          (item) => item.id == entry.entityId && item.isActive,
        ),
        'run' => !data.runs.any(
          (run) => run.id == entry.entityId && _reusableRun(run),
        ),
        'topic' => !data.topics.any(
          (topic) =>
              topic.id == entry.entityId &&
              _topicSupported(topic) &&
              _reusable(topic.inputItemIds) &&
              topic.snoozedUntil?.isAfter(DateTime.now()) != true,
        ),
        _ => false,
      };
      if (!enabled || expiredDigest || sourceExcluded) {
        runtime.outbox.remove(entry);
        _save();
        continue;
      }
      try {
        final posted = await native.publishNotification(
          id: entry.id,
          channel: entry.channel,
          title: entry.title,
          body: entry.body,
          entityType: entry.entityType,
          entityId: entry.entityId,
        );
        if (!posted) {
          notificationsAllowed = await native.notificationStatus();
          _save();
          continue;
        }
        entry.delivered = true;
        _save();
      } catch (error) {
        lastError = '通知发送失败：$error';
        _emit();
        return;
      }
    }
  }
}
