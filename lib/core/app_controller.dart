import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../platform/native_bridge.dart';
import '../services/content_service.dart';
import '../services/intelligence_service.dart';
import '../services/knowledge_service.dart';
import 'models.dart';
import 'diagnostics.dart';
import 'retrieval.dart';
import 'store.dart';

part 'task_controller.dart';
part 'personal_controller.dart';
part 'web_capture_controller.dart';

abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class DeviceSecrets implements SecretStore {
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  @override
  Future<String?> read(String key) => storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);
}

class AppController extends ChangeNotifier {
  final LocalStore store;
  final DiagnosticStore diagnostics;
  int _lifecycleRevision = 0;
  bool _assetCleanupPending = false;
  final ContentService content;
  final IntelligenceService intelligence;
  final NativeBridge native;
  final SecretStore secrets;
  AppData data = AppData();
  RuntimeState runtime = RuntimeState();
  BackgroundJob? _currentJob;
  Future<void>? _queueFuture;
  Future<void>? _interactiveFuture;
  bool _digestOnly = false;
  bool _foreground = false;
  bool _serviceStarted = false;
  final Map<String, Timer> _refreshTimers = {};
  final Set<String> _openWebCaptures = {};
  Map<String, String>? pendingNavigation;
  bool? notificationsAllowed;
  String? lastError;
  String _apiKey = '', _searchKey = '';
  int _active = 0;
  bool _resuming = false,
      _tracking = false,
      _disposed = false,
      _resumeRequested = false;
  bool get busy => _active > 0;
  bool get modelConfigured =>
      _apiKey.isNotEmpty && data.settings.textModel.isNotEmpty;
  bool get searchConfigured => _searchKey.isNotEmpty;
  AppController({
    required this.store,
    DiagnosticStore? diagnostics,
    ContentService? content,
    IntelligenceService? intelligence,
    NativeBridge? native,
    SecretStore? secrets,
  }) : diagnostics =
           diagnostics ?? DiagnosticStore('${store.root}/diagnostics.sqlite'),
       content = content ?? ContentService(),
       intelligence = intelligence ?? IntelligenceService(),
       native = native ?? const NativeBridge(),
       secrets = secrets ?? DeviceSecrets();
  static Future<AppController> open({
    Uint8List? recoveryBackup,
    bool digestOnly = false,
  }) async {
    final directory = await getApplicationSupportDirectory();
    final controller = AppController(
      store: LocalStore('${directory.path}/library'),
    );
    try {
      if (recoveryBackup != null) {
        AppSettings deviceSettings;
        try {
          deviceSettings = controller.store.load().settings;
        } catch (_) {
          deviceSettings = AppSettings();
        }
        controller.store.restore(
          recoveryBackup,
          serviceSettings: deviceSettings,
        );
      }
      await controller.initialize(digestOnly: digestOnly);
      return controller;
    } catch (_) {
      controller.dispose();
      rethrow;
    }
  }

  Future<void> initialize({bool digestOnly = false}) async {
    _digestOnly = digestOnly;
    data = store.load();
    runtime = store.loadRuntime();
    if (digestOnly) return;
    diagnostics.debugEnabled = data.settings.debugModelLogging;
    diagnostics.prune();
    await cleanupExpiredTrash();
    _recomputeInterests();
    native.setShareListener(() {
      unawaited(resume());
    });
    _apiKey = await secrets.read('modelKey') ?? '';
    _searchKey = await secrets.read('searchKey') ?? '';
    _recoverInterruptedTasks();
    _save();
  }

  void _recoverInterruptedTasks() {
    for (final item in data.items) {
      if (['analyzing', 'pending'].contains(item.status)) {
        item.status = 'interrupted';
        item.error = '上次处理已中断，可重试；已保存资料仍在本地';
      }
    }
    for (final run in data.runs) {
      if (run.status == 'running') {
        run.status = 'interrupted';
        run.error = '应用关闭，研究已中断';
      }
    }
    for (final topic in data.topics) {
      if (['running', 'synthesizing'].contains(topic.status)) {
        topic.status = 'pending';
      }
    }
  }

  void _save() {
    if (!_disposed) {
      store.saveWithRuntime(data, runtime);
      notifyListeners();
    }
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<T> _work<T>(
    Future<T> Function() operation, {
    String type = 'operation',
    String title = '处理任务',
    String? entityId,
    bool Function()? authorized,
  }) async {
    final revision = _lifecycleRevision;
    _active++;
    lastError = null;
    if (!_disposed) notifyListeners();
    try {
      return await diagnostics.runTask<T>(
        type: type,
        title: title,
        entityId: entityId,
        allowed: () => _valid(revision) && (authorized?.call() ?? true),
        excludedUrls: data.items
            .where((i) => !i.isActive && i.url.isNotEmpty)
            .map((i) => i.url)
            .toSet(),
        body: operation,
      );
    } catch (error) {
      lastError = error.toString();
      rethrow;
    } finally {
      _active--;
      if (!_disposed) {
        _assetCleanupPending = true;
        _cleanAssetsIfIdle();
        await _stopServiceIfIdle();
        notifyListeners();
      }
    }
  }

  bool _valid(int revision) => !_disposed && revision == _lifecycleRevision;
  void _guard(int revision) {
    if (!_valid(revision)) throw const DiagnosticCancelled();
  }

  void _requireActive(LibraryItem item) {
    if (!item.isActive) throw StateError('请先恢复或取消归档，再分析或研究此资料');
  }

  String _canonicalUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final port =
        (uri.scheme == 'https' && uri.port == 443) ||
            (uri.scheme == 'http' && uri.port == 80)
        ? null
        : uri.hasPort
        ? uri.port
        : null;
    return Uri(
      scheme: uri.scheme.toLowerCase(),
      host: uri.host.toLowerCase(),
      port: port,
      path: uri.path.isEmpty ? '/' : uri.path,
      query: uri.hasQuery ? uri.query : null,
    ).toString();
  }

  Set<String> _researchUrlInputs(ResearchRun run) {
    final urls = run.sources.map((source) => _canonicalUrl(source.url)).toSet();
    return {
      for (final item in data.items)
        if (item.url.isNotEmpty && urls.contains(_canonicalUrl(item.url)))
          item.id,
    };
  }

  bool _reusableRun(ResearchRun run) =>
      !run.stale &&
      _reusable(run.inputItemIds) &&
      _reusable(_researchUrlInputs(run).toList());
  bool _reusable(List<String>? inputs) =>
      inputs != null &&
      inputs.every((id) => data.items.any((i) => i.id == id && i.isActive));

  bool _analysisReusable(LibraryItem item) =>
      item.analysis?.stale != true && _reusable(item.analysis?.inputItemIds);

  /// Prompts use copies so excluded cached outputs remain readable in history.
  LibraryItem _safeSource(LibraryItem item) {
    final copy = LibraryItem.fromJson(item.toJson());
    if (!_reusable(copy.analysis?.inputItemIds) ||
        copy.analysis?.stale == true) {
      copy.analysis = null;
    }
    return copy;
  }

  Set<String> _sourceInputs(LibraryItem item) {
    if (data.items.any((i) => i.id == item.id)) {
      return {item.id, ...?item.analysis?.inputItemIds};
    }
    final run = data.runs.where((r) => r.id == item.id).firstOrNull;
    return {...?run?.inputItemIds, if (run != null) ..._researchUrlInputs(run)};
  }

  Set<String> _preferenceInputs() {
    final inferred = data.settings.inferredInterests.toSet()
      ..removeAll(data.settings.confirmedInterests);
    return {
      for (final item in data.items)
        if (item.isActive &&
            _analysisReusable(item) &&
            item.analysis!.suggestedTopics.any(inferred.contains))
          ...item.analysis!.inputItemIds!,
    };
  }

  AppSettings _promptSettings() {
    _recomputeInterests();
    return AppSettings.fromJson(data.settings.toJson());
  }

  void _recomputeInterests() {
    final settings = data.settings;
    final eligible = data.items
        .where((i) => i.isActive && i.feedback >= 0 && _analysisReusable(i))
        .toList();
    settings.inferredInterests = {
      ...settings.confirmedInterests,
      for (final item in eligible) ...item.analysis!.suggestedTopics,
    }.where((label) => !settings.suppressedInterests.contains(label)).toList();
    for (final topic in data.topics.where((t) => t.automatic)) {
      final supports = eligible.where(
        (i) => i.analysis!.suggestedTopics.contains(topic.title),
      );
      if (supports.isEmpty) {
        topic.tracking = false;
        topic.authorizedScope = '';
        topic.nextRun = null;
        topic.status = 'paused';
        topic.error = '支持该自动主题的有效资料已不足，历史成果仍可阅读';
      }
    }
  }

  bool _topicSupported(Topic topic) =>
      !topic.automatic ||
      data.items.any(
        (i) =>
            i.isActive &&
            i.feedback >= 0 &&
            _analysisReusable(i) &&
            i.analysis!.suggestedTopics.contains(topic.title),
      );
  Set<String> _topicInputs(Topic topic) => topic.automatic
      ? {
          for (final item in data.items)
            if (item.isActive &&
                _analysisReusable(item) &&
                item.analysis!.suggestedTopics.contains(topic.title))
              ...item.analysis!.inputItemIds!,
        }
      : {};

  void _invalidateTasks() {
    _lifecycleRevision++;
    for (final job in runtime.jobs) {
      if (['queued', 'running', 'paused'].contains(job.status)) {
        job.status = 'cancelled';
        job.error = '资料状态或授权已变化，请重新提交';
        _markJobInterrupted(job);
      }
    }
    for (final item in data.items) {
      if (['analyzing', 'pending'].contains(item.status)) {
        item.status = 'interrupted';
        item.error = '资料状态已变化，本次处理已停止；可重新执行';
      }
    }
    for (final topic in data.topics) {
      if (['running', 'synthesizing'].contains(topic.status)) {
        topic.status = 'interrupted';
        topic.error = '资料状态已变化，本次处理已停止';
      }
    }
  }

  void _cleanAssetsIfIdle() {
    if (_assetCleanupPending && _active == 0 && !_disposed) {
      store.cleanUnusedAssets(data);
      _assetCleanupPending = false;
    }
  }

  Future<void> _changeItems(Iterable<String> ids, String action) async {
    final selected = ids.toSet();
    final items = data.items.where((i) => selected.contains(i.id)).toList();
    if (items.isEmpty) return;
    await diagnostics.runTask<void>(
      type: 'management',
      title: action,
      inputItemIds: items.map((i) => i.id).toList(),
      body: () async {
        _invalidateTasks();
        final now = DateTime.now().toUtc();
        for (final item in items) {
          switch (action) {
            case '归档资料':
              if (!item.isTrashed) item.archivedAt ??= now;
            case '取消归档':
              if (!item.isTrashed) item.archivedAt = null;
            case '移入回收站':
              item.trashedAt ??= now;
            case '恢复资料':
              item.trashedAt = null;
          }
        }
        _recomputeInterests();
        _save();
      },
    );
  }

  Future<void> archiveItems(Iterable<String> ids) => _changeItems(ids, '归档资料');
  Future<void> unarchiveItems(Iterable<String> ids) =>
      _changeItems(ids, '取消归档');
  Future<void> trashItems(Iterable<String> ids) => _changeItems(ids, '移入回收站');
  Future<void> restoreItems(Iterable<String> ids) => _changeItems(ids, '恢复资料');
  Future<void> purgeItems(Iterable<String> ids) async {
    final requested = ids.toSet();
    final selected = data.items
        .where((i) => i.isTrashed && requested.contains(i.id))
        .map((i) => i.id)
        .toSet();
    if (selected.isEmpty) return;
    _invalidateTasks();
    data.items.removeWhere((i) => selected.contains(i.id));
    for (final entry in data.entries) {
      if (selected.contains(entry.savedItemId)) entry.savedItemId = null;
    }
    _recomputeInterests();
    _save(); // Commit removal before releasing any managed attachment.
    diagnostics.purgeItemPayloads(selected);
    _assetCleanupPending = true;
    _cleanAssetsIfIdle();
  }

  Future<void> cleanupExpiredTrash() async {
    final now = DateTime.now().toUtc();
    final ids = data.items
        .where(
          (i) =>
              i.trashedAt != null &&
              !i.trashedAt!
                  .toUtc()
                  .add(Duration(days: data.settings.trashRetentionDays))
                  .isAfter(now),
        )
        .map((i) => i.id)
        .toList();
    await purgeItems(ids);
    _assetCleanupPending = true;
    _cleanAssetsIfIdle();
  }

  Future<void> setTrashRetentionDays(int days) async {
    if (![3, 7].contains(days)) throw const FormatException('回收站保留期仅支持3或7天');
    data.settings.trashRetentionDays = days;
    _save();
    await cleanupExpiredTrash();
  }

  Future<void> setDebugModelLogging(bool enabled) async {
    data.settings.debugModelLogging = enabled;
    diagnostics.debugEnabled = enabled;
    _save();
  }

  String sourceLabel(String id) {
    final item = data.items.where((i) => i.id == id).firstOrNull;
    if (item != null) {
      final state = item.isTrashed
          ? '（在回收站）'
          : item.isArchived
          ? '（已归档）'
          : '';
      return '${item.title}$state';
    }
    final topic = data.topics.where((t) => t.id == id).firstOrNull;
    if (topic != null) return topic.title;
    final run = data.runs.where((r) => r.id == id).firstOrNull;
    return run?.goal ?? '来源已删除（$id）';
  }

  LibraryItem _item(String id) => data.items.firstWhere((i) => i.id == id);
  Topic _topic(String id) => data.topics.firstWhere((t) => t.id == id);
  String assetPath(Asset asset) => store.assetPath(asset);

  Future<LibraryItem> captureText(
    String text, {
    String title = '',
    String notes = '',
    bool analyzeAutomatically = true,
  }) => _work(
    () async {
      if (text.trim().isEmpty) throw const FormatException('请输入需要保存的内容');
      if (analyzeAutomatically) await _startUserWork();
      DiagnosticScope.ensureAllowed();
      final item = LibraryItem(
        id: newId(),
        title: title.trim().isEmpty
            ? text
                  .trim()
                  .split('\n')
                  .first
                  .substring(
                    0,
                    text.trim().split('\n').first.length.clamp(0, 60),
                  )
            : title.trim(),
        kind: ItemKind.text,
        body: text.trim(),
        notes: notes,
      );
      data.items.insert(0, item);
      diagnostics.addInputIds([item.id]);
      if (analyzeAutomatically) {
        _enqueue('analysis', item.id);
      } else {
        item.status = 'retryable';
      }
      await diagnostics.step('保存原文并加入任务队列', () async => _save());
      _scheduleQueue();
      return item;
    },
    type: 'capture',
    title: '保存文字',
  );
  Future<LibraryItem> captureUrl(
    String url, {
    String notes = '',
    bool analyzeAutomatically = true,
  }) => _work(
    () async {
      final uri = Uri.tryParse(url.trim());
      if (uri == null ||
          !['https', 'http'].contains(uri.scheme) ||
          uri.host.isEmpty) {
        throw const FormatException('请输入有效网页链接');
      }
      final matches = data.items.where(
        (i) =>
            i.url.isNotEmpty &&
            normalizedCaptureUrl(i.url) == normalizedCaptureUrl(uri.toString()),
      );
      if (matches.isNotEmpty) {
        final existing = matches.first;
        _notice('该链接已收藏，打开已有资料');
        if (!existing.isActive) {
          _notice(existing.isTrashed ? '该网页已在回收站，可恢复后使用' : '该网页已归档，可取消归档后使用');
          _save();
        }
        return existing;
      }
      if (analyzeAutomatically) await _startUserWork();
      DiagnosticScope.ensureAllowed();
      final item = LibraryItem(
        id: newId(),
        title: uri.host,
        kind: ItemKind.web,
        url: uri.toString(),
        notes: notes,
        status: 'pending',
      );
      data.items.insert(0, item);
      diagnostics.addInputIds([item.id]);
      if (analyzeAutomatically) {
        _enqueue('capture', item.id);
      } else {
        item.status = 'retryable';
      }
      await diagnostics.step('保存网页链接并加入任务队列', () async => _save());
      _scheduleQueue();
      return item;
    },
    type: 'capture',
    title: '保存网页',
  );
  Future<void> _fetch(LibraryItem item) async {
    final revision = _lifecycleRevision;
    _requireActive(item);
    diagnostics.addInputIds([item.id]);
    item.status = 'pending';
    item.error = '';
    _save();
    try {
      var imageUrls = strings(_currentJob?.checkpoint['imageUrls']);
      if (_currentJob?.checkpoint['articleFetched'] != true) {
        final article = await diagnostics.step(
          '提取网页正文',
          () => content.fetchArticle(item.url),
        );
        _guard(revision);
        _replaceWebBody(item, article, origin: 'http');
        imageUrls = article.imageUrls;
        _saveCheckpoint('正文已保存', {
          'imageUrls': imageUrls,
          'articleFetched': true,
          'contentVersion': item.contentVersion,
          'bodyOrigin': item.bodyOrigin,
        });
        _save();
      }
      var failed = 0;
      for (final url in imageUrls.take(30)) {
        _guard(revision);
        final savedImages = json(_currentJob?.checkpoint['savedImages'] ?? {});
        if (savedImages.containsKey(url)) {
          for (final block in item.contentBlocks.where(
            (b) => b.assetId == url,
          )) {
            block.assetId = savedImages[url] as String;
          }
          continue;
        }
        try {
          final bytes = await diagnostics.step(
            '保存主要图片',
            () => content.downloadImage(url),
          );
          _guard(revision);
          final codec = await ui.instantiateImageCodec(bytes, targetWidth: 64);
          try {
            final frame = await codec.getNextFrame();
            frame.image.dispose();
          } finally {
            codec.dispose();
          }
          final extension = Uri.parse(url).path.toLowerCase().endsWith('.png')
              ? 'png'
              : 'jpg';
          _guard(revision);
          final asset = await store.writeAsset(
            bytes,
            'image.$extension',
            'image/$extension',
          );
          _guard(revision);
          item.assets.add(asset);
          for (final block in item.contentBlocks.where(
            (b) => b.assetId == url,
          )) {
            block.assetId = asset.path;
          }
          savedImages[url] = asset.path;
          _saveCheckpoint('保存图片', {'savedImages': savedImages});
        } on DiagnosticCancelled {
          rethrow;
        } catch (_) {
          failed++;
        }
      }
      _guard(revision);
      item.warning = failed > 0 ? '正文已保存，$failed 张图片未能下载，可重试补图' : '';
      if (imageUrls.length > 30) item.warning += ' 本篇已保存前30张主要图片。';
      _save();
    } on DiagnosticCancelled {
      diagnostics.failCurrent('资料状态已变化，已停止抓取');
    } catch (error) {
      diagnostics.failCurrent(error.toString());
      if (!_valid(revision)) return;
      item.status = 'failed';
      item.error = '正文提取失败：$error';
      _save();
    }
  }

  Future<LibraryItem> importFile(
    String path, {
    String? name,
    bool analyzeAutomatically = true,
  }) => _work(
    () async {
      final fileName = name ?? path.split(Platform.pathSeparator).last;
      final ext = fileName.split('.').last.toLowerCase();
      final pdf = ext == 'pdf';
      if (!pdf && !['png', 'jpg', 'jpeg', 'webp', 'gif'].contains(ext)) {
        throw const FormatException('目前支持 PDF、PNG、JPEG、WebP 和 GIF');
      }
      if (analyzeAutomatically) await _startUserWork();
      DiagnosticScope.ensureAllowed();
      final mime = pdf
          ? 'application/pdf'
          : 'image/${ext == 'jpg' ? 'jpeg' : ext}';
      final asset = await diagnostics.step(
        '保存附件',
        () => store.importAsset(path, fileName, mime),
      );
      DiagnosticScope.ensureAllowed();
      final item = LibraryItem(
        id: newId(),
        title: fileName,
        kind: pdf ? ItemKind.pdf : ItemKind.image,
        assets: [asset],
      );
      data.items.insert(0, item);
      diagnostics.addInputIds([item.id]);
      if (analyzeAutomatically) {
        _enqueue('analysis', item.id);
      } else {
        item.status = 'retryable';
      }
      _save();
      _scheduleQueue();
      return item;
    },
    type: 'import',
    title: '导入文件',
  );
  Iterable<LibraryItem> get _knowledgeSources sync* {
    yield* data.items.where((i) => i.isActive).map(_safeSource);
    for (final run in data.runs) {
      if (run.report.trim().isEmpty || !_reusableRun(run)) continue;
      yield LibraryItem(
        id: run.id,
        title: '研究成果：${run.goal}',
        kind: ItemKind.text,
        body:
            '已保存研究成果，引用资料 id ${run.id}；S 编号仅在本报告内有效。\n'
            '来源摘录（完整来源见研究记录）：\n'
            '${run.sources.take(5).map((s) => '[${s.id}] ${s.title}\n${s.url}\n${s.snippet.length > 250 ? '${s.snippet.substring(0, 250)}…' : s.snippet}').join('\n\n')}'
            '\n\n研究报告：\n${run.report}',
        notes: '这是已保存的模型研究成果，可能仍有待查证问题；引用该成果时使用资料 id ${run.id}，不要沿用报告内部的 S 编号。',
        status: run.status,
      );
    }
  }

  List<LibraryItem> _related(LibraryItem item) {
    final terms = _terms('${item.title} ${item.notes} ${item.body}');
    final candidates =
        _knowledgeSources
            .where((i) => i.id != item.id)
            .map(
              (i) => (
                item: i,
                score:
                    _terms('${i.title} ${i.body} ${i.analysis?.summary ?? ''}')
                        .intersection(terms)
                        .length +
                    (i.readCount > 1 ? 1 : 0) +
                    (i.researchAdoptions > 0 ? 1 : 0),
              ),
            )
            .where((v) => v.score > 1)
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));
    return candidates.take(8).map((v) => v.item).toList();
  }

  Set<String> _terms(String text) {
    final result = RegExp(r'[a-zA-Z0-9]{3,}')
        .allMatches(text.toLowerCase())
        .map((m) => m[0]!)
        .toSet();
    for (final match in RegExp(r'[\u4e00-\u9fff]+').allMatches(text)) {
      final chars = match[0]!;
      for (var n = 0; n < chars.length - 1; n++) {
        result.add(chars.substring(n, n + 2));
      }
    }
    return result;
  }

  Future<Analysis> _analyzeWithTrace(
    AppSettings settings,
    String key,
    LibraryItem item,
    List<LibraryItem> related, {
    List<String> imageDataUrls = const [],
    String checkpointKey = 'finalAnalysis',
  }) async {
    final job = _currentJob;
    final cached = job?.checkpoint[checkpointKey];
    if (cached is Map) return Analysis.fromJson(json(cached));
    final label = imageDataUrls.isEmpty ? '调用文本模型' : '调用多模态模型';
    _saveCheckpoint(label, {
      'requestPending': true,
      'modelAttempts':
          ((job?.checkpoint['modelAttempts'] as num?)?.toInt() ?? 0) + 1,
    });
    final result = await diagnostics.step(
      label,
      () => intelligence.analyze(
        settings,
        key,
        item,
        related,
        imageDataUrls: imageDataUrls,
      ),
    );
    DiagnosticScope.ensureAllowed();
    _saveCheckpoint(label, {
      checkpointKey: result.toJson(),
      'requestPending': false,
    });
    return result;
  }

  Future<void> analyze(String itemId) => _work(
    () async {
      final item = _item(itemId);
      _requireActive(item);
      final revision = _lifecycleRevision;
      if (item.status == 'analyzing') return;
      if (item.kind == ItemKind.web && item.body.isEmpty) {
        await _fetch(item);
        _guard(revision);
        if (item.body.isEmpty) return;
      }
      if (!modelConfigured) {
        item.status = 'waiting';
        item.error = '原文已保存，配置模型后可分析';
        _save();
        return;
      }
      item.status = 'analyzing';
      item.error = '';
      final analyzedNotes = item.notes;
      _save();
      try {
        final settings = _promptSettings();
        final related = _related(item);
        final promptItem = LibraryItem.fromJson(item.toJson());
        final signature = jsonEncode([
          promptItem.body,
          analyzedNotes,
          promptItem.contentVersion,
          promptItem.annotations
              .map((annotation) => annotation.toJson())
              .toList(),
          for (final source in related)
            [
              source.id,
              source.body,
              source.notes,
              source.analysis?.toJson(),
              source.annotations
                  .map((annotation) => annotation.toJson())
                  .toList(),
            ],
        ]);
        final oldSignature = _currentJob?.checkpoint['analysisInput'];
        if (oldSignature != null && oldSignature != signature) {
          throw StateError('分析输入已变化，请手动重试以重新分析');
        }
        _saveCheckpoint('准备分析输入', {'analysisInput': signature});
        final inputs = {
          item.id,
          ..._preferenceInputs(),
          for (final source in related) ..._sourceInputs(source),
        };
        diagnostics.addInputIds(inputs);
        _saveCheckpoint('准备分析', {'inputIds': inputs.toList()});
        late Analysis analysis;
        if (item.kind == ItemKind.pdf) {
          final path = assetPath(item.assets.first);
          final summaries = strings(_currentJob?.checkpoint['pdfSummaries']);
          var page = (_currentJob?.checkpoint['pdfPage'] as num?)?.toInt() ?? 0;
          var total =
              (_currentJob?.checkpoint['pdfTotal'] as num?)?.toInt() ?? 1;
          while (page < total) {
            _guard(revision);
            final rendered = await native.renderPdf(
              path,
              startPage: page,
              maxPages: 4,
            );
            _guard(revision);
            total = rendered.pageCount;
            item.pdfPageCount = total;
            if (total == 0 || rendered.images.isEmpty) {
              throw const FormatException('PDF 没有可分析的页面');
            }
            if (total > 100) {
              throw const FormatException('当前支持100页以内PDF，请拆分后导入；原文件已保留');
            }
            final batch = LibraryItem(
              id: item.id,
              title:
                  '${item.title} 第${page + 1}–${(page + 4).clamp(1, total)}页',
              kind: ItemKind.pdf,
              pdfPageCount: total,
              pdfPageStart: page + 1,
              pdfPageEnd: page + rendered.images.length,
              notes: analyzedNotes,
              annotations: promptItem.annotations,
              readCount: item.readCount,
              researchAdoptions: item.researchAdoptions,
              feedback: item.feedback,
            );
            final result = await _analyzeWithTrace(
              settings,
              _apiKey,
              batch,
              related,
              checkpointKey: 'pdf:$page',
              imageDataUrls: rendered.images
                  .map((s) => 'data:image/jpeg;base64,$s')
                  .toList(),
            );
            _guard(revision);
            summaries.add('第${page + 1}页起：${jsonEncode(result.toJson())}');
            page += rendered.images.length;
            _saveCheckpoint('PDF $page / $total 页', {
              'pdfSummaries': summaries.toList(),
              'pdfPage': page,
              'pdfTotal': total,
              'completed': page,
              'total': total,
            });
          }
          final combined = LibraryItem(
            id: item.id,
            title: item.title,
            kind: ItemKind.pdf,
            pdfPageCount: total,
            body: summaries.join('\n'),
            notes: analyzedNotes,
            annotations: promptItem.annotations,
            readCount: item.readCount,
            researchAdoptions: item.researchAdoptions,
            feedback: item.feedback,
          );
          analysis = await _analyzeWithTrace(
            settings,
            _apiKey,
            combined,
            related,
          );
        } else if (item.kind == ItemKind.image) {
          final asset = item.assets.first;
          final bytes = await File(assetPath(asset)).readAsBytes();
          analysis = await _analyzeWithTrace(
            settings,
            _apiKey,
            promptItem,
            related,
            imageDataUrls: ['data:${asset.mime};base64,${base64Encode(bytes)}'],
          );
        } else {
          final text = item.body;
          if (text.length > 24000) {
            final sections = strings(_currentJob?.checkpoint['textSections']);
            for (
              var start = sections.length * 24000;
              start < text.length;
              start += 24000
            ) {
              _guard(revision);
              final part = LibraryItem(
                id: item.id,
                title: item.title,
                kind: item.kind,
                notes: analyzedNotes,
                annotations: promptItem.annotations,
                readCount: item.readCount,
                researchAdoptions: item.researchAdoptions,
                feedback: item.feedback,
                body: text.substring(
                  start,
                  (start + 24000).clamp(0, text.length),
                ),
              );
              sections.add(
                jsonEncode(
                  (await _analyzeWithTrace(
                    settings,
                    _apiKey,
                    part,
                    [],
                    checkpointKey: 'text:$start',
                  )).toJson(),
                ),
              );
              _saveCheckpoint('长文第 ${sections.length} 段', {
                'textSections': sections.toList(),
                'completed': sections.length,
                'total': (text.length / 24000).ceil(),
              });
            }
            analysis = await _analyzeWithTrace(
              settings,
              _apiKey,
              LibraryItem(
                id: item.id,
                title: item.title,
                kind: item.kind,
                body: sections.join('\n'),
                notes: analyzedNotes,
                annotations: promptItem.annotations,
                readCount: item.readCount,
                researchAdoptions: item.researchAdoptions,
                feedback: item.feedback,
              ),
              related,
            );
          } else {
            analysis = await _analyzeWithTrace(
              settings,
              _apiKey,
              promptItem,
              related,
            );
          }
        }
        _guard(revision);
        analysis.inputItemIds = inputs.toList();
        _resolveFinalEvidence(
          analysis,
          {item.id: item, for (final source in related) source.id: source},
          summarySourceId: item.kind == ItemKind.pdf || item.body.length > 24000
              ? item.id
              : null,
        );
        analysis.stale =
            item.notes != analyzedNotes ||
            jsonEncode(item.annotations.map((a) => a.toJson()).toList()) !=
                jsonEncode(
                  promptItem.annotations.map((a) => a.toJson()).toList(),
                ) ||
            related.any(
              (source) => data.items.any(
                (current) =>
                    current.id == source.id &&
                    (current.notes != source.notes ||
                        current.contentVersion != source.contentVersion ||
                        jsonEncode(
                              current.annotations
                                  .map((a) => a.toJson())
                                  .toList(),
                            ) !=
                            jsonEncode(
                              source.annotations
                                  .map((a) => a.toJson())
                                  .toList(),
                            )),
              ),
            );
        await diagnostics.step('保存分析结果', () async {
          _guard(revision);
          item.analysis = analysis;
          item.status = 'ready';
          _currentJob?.checkpoint['analyzed'] = true;
        });
        _save();
        await _updateInterests(item);
        _saveCheckpoint('主题更新完成', {'topicsUpdated': true});
      } on DiagnosticCancelled {
        diagnostics.failCurrent('资料状态已变化，本次分析已停止；历史结果保留');
      } catch (error) {
        diagnostics.failCurrent(error.toString());
        if (!_valid(revision)) return;
        item.status = 'error';
        item.error = '分析未完成：$error';
        _save();
      }
    },
    type: 'analysis',
    title: '分析资料',
    entityId: itemId,
  );
  void _resolveFinalEvidence(
    Analysis analysis,
    Map<String, LibraryItem> sources, {
    String? summarySourceId,
  }) {
    for (final insight in analysis.structuredInsights) {
      for (final anchor in insight.evidence) {
        try {
          if (anchor.sourceId == summarySourceId &&
              anchor.pdfPage == null &&
              anchor.quote.trim().isEmpty) {
            throw const FormatException('综合摘要引用缺少可核验原文摘录');
          }
          KnowledgeService.validateEvidenceAnchor(anchor.toJson(), sources);
        } on FormatException {
          final source = sources[anchor.sourceId];
          final matches = source == null || anchor.quote.trim().isEmpty
              ? <Json>[]
              : KnowledgeService.contentBlocksForItem(source)
                    .where(
                      (block) =>
                          (block['text'] as String).contains(anchor.quote),
                    )
                    .toList();
          if (matches.length == 1 && source?.kind != ItemKind.pdf) {
            anchor.blockId = matches.single['id'] as String;
            anchor.sourceVersion = source!.contentVersion;
            anchor.pdfPage = null;
            anchor.unresolved = false;
          } else {
            anchor.unresolved = true;
            anchor.blockId = '';
            anchor.pdfPage = null;
            anchor.note = '中间摘要中的引用未能在真实原文中定位；摘录尚未核验';
          }
        }
      }
    }
  }

  Future<void> _updateInterests(LibraryItem item) async {
    if (!item.isActive ||
        item.analysis?.stale == true ||
        !_analysisReusable(item)) {
      return;
    }
    _recomputeInterests();
    for (final label in item.analysis?.suggestedTopics ?? <String>[]) {
      if (data.settings.suppressedInterests.contains(label)) continue;
      if (!data.settings.inferredInterests.contains(label)) {
        data.settings.inferredInterests.add(label);
      }
      final related = data.items
          .where(
            (i) =>
                i.isActive &&
                _analysisReusable(i) &&
                (i.analysis?.suggestedTopics.contains(label) ?? false) &&
                i.feedback >= 0,
          )
          .toList();
      if (related.length >= 2 && !data.topics.any((t) => t.title == label)) {
        data.topics.add(
          Topic(
            id: newId(),
            title: label,
            question: '关于$label，目前有什么认识、分歧和待查证问题？',
            automatic: true,
            reason: '${related.length} 条收藏共同涉及该方向；这表示关注，不表示认同',
            sourceIds: related.map((i) => i.id).toList(),
          ),
        );
      }
    }
    _save();
    for (final topic in data.topics.toList()) {
      DiagnosticScope.ensureAllowed();
      if (!_topicSupported(topic)) continue;
      if (strings(_currentJob?.checkpoint['updatedTopics'])
          .contains(topic.id)) {
        continue;
      }
      if (topic.sourceIds.contains(item.id) ||
          _terms('${topic.title} ${topic.question}')
              .intersection(_terms('${item.title} ${item.body}'))
              .isNotEmpty) {
        await synthesizeTopic(topic.id);
        if (topic.status == 'ready') {
          _saveCheckpoint('已更新主题', {
            'updatedTopics': [
              ...strings(_currentJob?.checkpoint['updatedTopics']),
              topic.id,
            ],
          });
        }
      }
    }
  }

  Future<void> markRead(String id) async {
    _item(id).readCount++;
    _save();
  }

  Future<void> setFeedback(String id, int feedback) async {
    _item(id).feedback = feedback.clamp(-1, 1);
    _recomputeInterests();
    await refreshToday();
  }

  Future<void> updateNotes(String id, String notes) async {
    final item = _item(id);
    if (item.notes == notes) return;
    item.notes = notes;
    _personalKnowledgeChanged(item);
  }

  void _personalKnowledgeChanged(LibraryItem item) {
    final id = item.id;
    for (final run in data.runs) {
      if (run.inputItemIds?.contains(id) == true) run.stale = true;
    }
    if (item.analysis != null) item.analysis!.stale = true;
    for (final dependent in data.items) {
      if (dependent.analysis?.inputItemIds?.contains(id) == true) {
        dependent.analysis!.stale = true;
      }
    }
    for (final topic in data.topics) {
      if (topic.inputItemIds?.contains(id) == true ||
          topic.sourceIds.contains(id) ||
          topic.selectedSourceIds?.contains(id) == true) {
        topic.overviewStale = true;
        _scheduleTopicRefresh(topic.id);
      }
    }
    _save();
  }

  Future<void> addFeed(String url) => _work(() async {
    if (data.feeds.any((f) => f.url == url.trim())) return;
    final parsed = await content.fetchFeed(url.trim());
    final feed = Feed(
      id: newId(),
      url: url.trim(),
      title: parsed.title,
      refreshedAt: DateTime.now(),
    );
    data.feeds.add(feed);
    for (final entry in parsed.entries) {
      entry.feedId = feed.id;
      data.entries.add(entry);
    }
    _save();
  });
  Future<void> refreshFeeds() => _work(() async {
    for (final feed in data.feeds.where((feed) => !feed.paused)) {
      try {
        final parsed = await content.fetchFeed(feed.url);
        feed.title = parsed.title;
        feed.error = '';
        feed.refreshedAt = DateTime.now();
        for (final entry in parsed.entries) {
          if (!data.entries.any((e) => e.id == entry.id)) {
            entry.feedId = feed.id;
            data.entries.insert(0, entry);
          }
        }
      } catch (error) {
        feed.error = error.toString();
      }
      _save();
    }
  });
  Future<void> selectEntry(String id) async {
    final entry = data.entries.firstWhere((e) => e.id == id);
    if (entry.savedItemId != null) {
      final existing = data.items
          .where((i) => i.id == entry.savedItemId)
          .firstOrNull;
      if (existing != null) {
        _notice('该链接已收藏，打开已有资料');
        if (!existing.isActive) {
          _notice(existing.isTrashed ? '该资料在回收站，可恢复后使用' : '该资料已归档');
        }
        _save();
        return;
      }
      entry.savedItemId = null;
    }
    final item = await captureUrl(entry.url);
    entry.savedItemId = item.id;
    entry.processed = true;
    _save();
  }

  Future<Topic> addTopic(String title, String question) async {
    if (title.trim().isEmpty || question.trim().isEmpty) {
      throw const FormatException('请填写主题和研究问题');
    }
    final topic = Topic(
      id: newId(),
      title: title.trim(),
      question: question.trim(),
      reason: '你明确关注的主题',
    );
    data.topics.insert(0, topic);
    _save();
    return topic;
  }

  Future<void> updateTopic(String id, String title, String question) async {
    if (title.trim().isEmpty || question.trim().isEmpty) {
      throw const FormatException('主题和研究问题不能为空');
    }
    final topic = _topic(id);
    if (topic.question != question.trim()) {
      _invalidateTasks();
      topic.tracking = false;
      topic.authorizedScope = '';
      topic.nextRun = null;
    }
    topic.automatic =
        false; // Explicit editing makes this a user-owned research question.
    topic.title = title.trim();
    topic.question = question.trim();
    _save();
  }

  Future<void> synthesizeTopic(String id) => _work(
    () async {
      final topic = _topic(id);
      final revision = _lifecycleRevision;
      if (!_topicSupported(topic)) {
        topic.error = '该自动主题暂无有效支持资料';
        _save();
        return;
      }
      if (topic.status == 'synthesizing') return;
      final settings = _promptSettings();
      final query = '${topic.title} ${topic.question}';
      final items =
          _knowledgeSources
              .where(
                (i) => topic.selectedSourceIds != null
                    ? topic.selectedSourceIds!.contains(i.id)
                    : topic.sourceIds.contains(i.id) ||
                          relevance(query, itemSearchText(i)) > 0,
              )
              .toList()
            ..sort(
              (a, b) => relevance(
                query,
                itemSearchText(b),
                title: b.title,
              ).compareTo(relevance(query, itemSearchText(a), title: a.title)),
            );
      final chosen = items.take(16).toList();
      final scopedTopic = _promptTopic(topic);
      if (chosen.isEmpty && scopedTopic.contextEntries.isEmpty) {
        topic.error = '尚无相关本地资料，收藏后即可形成综述';
        _save();
        return;
      }
      if (!modelConfigured) {
        topic.error = '请先配置文本模型';
        _save();
        return;
      }
      topic.status = 'synthesizing';
      topic.error = '';
      _save();
      try {
        final inputs = {
          ..._preferenceInputs(),
          ..._topicInputs(topic),
          ..._contextInputs(topic),
          for (final item in chosen) ..._sourceInputs(item),
        };
        diagnostics.addInputIds(inputs);
        final cacheKey = 'synthesis:$id';
        final fingerprint = jsonEncode([
          scopedTopic.question,
          scopedTopic.selectedSourceIds,
          scopedTopic.contextEntries.map((entry) => entry.toJson()).toList(),
          chosen
              .map(
                (source) => [
                  source.id,
                  source.body,
                  source.notes,
                  source.contentVersion,
                  source.annotations
                      .map((annotation) => annotation.toJson())
                      .toList(),
                  source.analysis?.toJson(),
                ],
              )
              .toList(),
        ]);
        final previousFingerprint = _currentJob?.checkpoint['$cacheKey:input'];
        if (previousFingerprint != null && previousFingerprint != fingerprint) {
          throw StateError('综述输入已变化，请手动重试以重新生成');
        }
        _saveCheckpoint('准备主题输入', {
          '$cacheKey:input': fingerprint,
          'inputIds': inputs.toList(),
        });
        final cached = _currentJob?.checkpoint[cacheKey];
        if (cached == null) _saveCheckpoint('生成主题综述', {'requestPending': true});
        final result = cached is Map
            ? json(cached)
            : await diagnostics.step(
                '生成主题综述',
                () => intelligence.synthesize(
                  settings,
                  _apiKey,
                  scopedTopic,
                  chosen,
                ),
              );
        _guard(revision);
        final overview = result['overview'];
        if (overview is! String || overview.trim().isEmpty) {
          throw const FormatException('综述为空');
        }
        _saveCheckpoint('综述已生成', {cacheKey: result, 'requestPending': false});
        topic.overview = overview;
        topic.inputItemIds = inputs.toList();
        topic.sourceIds = strings(result['sourceIds'])
            .where((id) => chosen.any((i) => i.id == id))
            .toList();
        topic.status = 'ready';
        topic.overviewStale = chosen.any(
          (source) => data.items.any(
            (current) =>
                current.id == source.id &&
                (current.notes != source.notes ||
                    current.contentVersion != source.contentVersion ||
                    jsonEncode(
                          current.annotations.map((a) => a.toJson()).toList(),
                        ) !=
                        jsonEncode(
                          source.annotations.map((a) => a.toJson()).toList(),
                        )),
          ),
        );
      } on DiagnosticCancelled {
        diagnostics.failCurrent('资料状态已变化，本次综述未保存');
      } catch (error) {
        diagnostics.failCurrent(error.toString());
        if (!_valid(revision)) return;
        topic.status = 'error';
        topic.error = error.toString();
      }
      _save();
    },
    type: 'synthesis',
    title: '更新主题综述',
    entityId: id,
  );
  Future<void> setTracking(
    String id, {
    required bool enabled,
    int intervalHours = 24,
    int callLimit = 6,
    required bool confirmed,
  }) async {
    final topic = _topic(id);
    if (enabled) {
      if (!_topicSupported(topic)) throw StateError('该自动主题暂无有效支持资料');
      if (!confirmed) throw StateError('持续研究需要主题授权');
      if (intervalHours < 1 ||
          intervalHours > 720 ||
          callLimit < 2 ||
          callLimit > 30) {
        throw const FormatException('频率需1–720小时，调用上限2–30次');
      }
      topic.authorizedScope = topic.question;
      topic.intervalHours = intervalHours;
      topic.callLimit = callLimit;
      topic.nextRun = DateTime.now();
      await native.requestNotificationPermission();
    }
    topic.tracking = enabled;
    if (!enabled) topic.status = 'paused';
    _save();
  }

  Future<ResearchRun> research({
    required String goal,
    String? topicId,
    String? originItemId,
    required bool confirmed,
    int callLimit = 6,
  }) => _work(
    () async {
      if (!confirmed) throw StateError('外部研究需要你的确认');
      if (goal.trim().isEmpty) throw const FormatException('请输入研究目标');
      if (callLimit < 2 || callLimit > 30) {
        throw const FormatException('研究调用上限需为2–30次');
      }
      if (!modelConfigured || !searchConfigured) {
        throw StateError('请先配置文本模型和搜索服务 Key');
      }
      final topic = topicId == null ? null : _topic(topicId);
      if (topic != null && !_topicSupported(topic)) {
        throw StateError('该自动主题暂无有效支持资料');
      }
      final adopted = <LibraryItem>[];
      if (originItemId != null) {
        final origin = _item(originItemId);
        _requireActive(origin);
        if (!_analysisReusable(origin)) {
          throw StateError('该研究建议依赖已排除或来源不明的资料，请先重新分析');
        }
        if (!origin.analysis!.questions.any((q) => q.trim() == goal.trim())) {
          throw StateError('研究建议已更新，请重新打开资料确认');
        }
        adopted.add(origin);
      } else {
        adopted.addAll(
          data.items.where(
            (item) =>
                item.isActive &&
                _analysisReusable(item) &&
                item.analysis!.questions.any((q) => q.trim() == goal.trim()),
          ),
        );
      }
      for (final item in adopted) {
        item.researchAdoptions++;
      }
      await _startUserWork();
      final run = ResearchRun(
        id: newId(),
        goal: goal.trim(),
        topicId: topicId,
        callLimit: callLimit,
        status: 'queued',
        inputItemIds: {
          ..._preferenceInputs(),
          if (topic != null) ..._topicInputs(topic),
          if (topic != null && _reusable(topic.inputItemIds))
            ...topic.inputItemIds!,
          for (final item in adopted) ...item.analysis!.inputItemIds!,
        }.toList(),
      );
      data.runs.insert(0, run);
      _enqueue('research', run.id);
      _save();
      _scheduleQueue();
      return run;
    },
    type: 'research',
    title: '外部研究',
    entityId: originItemId ?? topicId,
  );

  Future<ResearchRun> _executeResearch({
    required String goal,
    Topic? topic,
    required int callLimit,
    Set<String> originInputs = const {},
    bool Function()? authorized,
    ResearchRun? existingRun,
  }) async {
    final revision = _lifecycleRevision;
    final settings = _promptSettings();
    final previous =
        topic != null && !topic.overviewStale && _reusable(topic.inputItemIds)
        ? topic.overview
        : '';
    final scopedTopic = topic == null ? null : _promptTopic(topic);
    final localCandidates = topic == null
        ? <LibraryItem>[]
        : _knowledgeSources
              .where(
                (source) => topic.selectedSourceIds != null
                    ? topic.selectedSourceIds!.contains(source.id)
                    : topic.sourceIds.contains(source.id) ||
                          relevance(goal, itemSearchText(source)) > 0,
              )
              .toList();
    localCandidates.sort(
      (a, b) => relevance(
        goal,
        itemSearchText(b),
      ).compareTo(relevance(goal, itemSearchText(a))),
    );
    final localSources = localCandidates.take(16).toList();
    final inputs = {
      ...originInputs,
      ..._preferenceInputs(),
      if (topic != null) ..._topicInputs(topic),
      if (topic != null) ..._contextInputs(topic),
      for (final source in localSources) ..._sourceInputs(source),
      if (previous.isNotEmpty) ...topic!.inputItemIds!,
    };
    diagnostics.addInputIds(inputs);
    final run = existingRun == null
        ? ResearchRun(
            id: newId(),
            goal: goal,
            topicId: topic?.id,
            callLimit: callLimit,
            inputItemIds: inputs.toList(),
          )
        : ResearchRun.fromJson(existingRun.toJson());
    final fingerprintIds =
        _currentJob?.checkpoint['researchFingerprintIds'] is List
        ? strings(_currentJob!.checkpoint['researchFingerprintIds']).toSet()
        : inputs.toSet();
    String inputFingerprint() => jsonEncode([
      for (final item in data.items.where(
        (item) => fingerprintIds.contains(item.id),
      ))
        [
          item.id,
          item.body,
          item.notes,
          item.contentVersion,
          item.annotations.map((a) => a.toJson()).toList(),
        ],
    ]);
    final fingerprint = inputFingerprint();
    final previousFingerprint = _currentJob?.checkpoint['researchInput'];
    if (previousFingerprint != null && previousFingerprint != fingerprint) {
      throw StateError('研究输入已变化，请重新提交，旧调用预算保留');
    }
    _saveCheckpoint('准备研究输入', {
      'researchInput': fingerprint,
      'researchFingerprintIds': fingerprintIds.toList(),
      'inputIds': inputs.toList(),
    });
    bool allowed() => _valid(revision) && (authorized?.call() ?? true);
    void persist() {
      run.stale = run.stale || inputFingerprint() != fingerprint;
      _currentJob?.checkpoint['requestPending'] = run.requestPending;
      inputs.addAll(_researchUrlInputs(run));
      run.inputItemIds = inputs.toList();
      diagnostics.addInputIds(inputs);
      final index = data.runs.indexWhere((r) => r.id == run.id);
      final snapshot = ResearchRun.fromJson(run.toJson());
      if (index < 0) {
        data.runs.insert(0, snapshot);
      } else {
        data.runs[index] = snapshot;
      }
      _save();
    }

    persist();
    try {
      await diagnostics.runTask<void>(
        type: 'research',
        title: '研究：$goal',
        entityId: run.id,
        inputItemIds: inputs.toList(),
        body: () async {
          await intelligence.research(
            settings,
            _apiKey,
            _searchKey,
            run,
            authorized: allowed,
            onProgress: () async {
              if (!allowed()) throw const DiagnosticCancelled();
              persist();
            },
            previousReport: previous,
            localContext: {
              if (scopedTopic != null)
                'topic': {
                  'id': scopedTopic.id,
                  'title': scopedTopic.title,
                  'question': scopedTopic.question,
                },
              if (scopedTopic != null)
                'contexts': scopedTopic.contextEntries
                    .map((entry) => entry.toJson())
                    .toList(),
              'sources': localSources
                  .map(KnowledgeService.itemPayload)
                  .toList(),
              'lineage': inputs.toList(),
            },
          );
          if (run.status == 'failed') diagnostics.failCurrent(run.error);
        },
      );
      if (!allowed()) throw const DiagnosticCancelled();
      inputs.addAll(_researchUrlInputs(run));
      run.inputItemIds = inputs.toList();
      if (!_reusable(run.inputItemIds)) throw const DiagnosticCancelled();
      if (run.status == 'failed') diagnostics.failCurrent(run.error);
      if (topic != null && run.report.isNotEmpty) _attachResearch(topic, run);
    } on DiagnosticCancelled {
      // Research mutates a detached working copy. Late content never becomes history.
      run.report = '';
      run.sources.clear();
      run.meaningful = false;
      run.status = 'interrupted';
      run.error = '资料或授权已变化，本次研究结果未保存';
      diagnostics.failCurrent(run.error);
    } catch (error) {
      run.status = 'failed';
      run.error = error.toString();
      diagnostics.failCurrent(run.error);
    }
    run.completedAt ??= DateTime.now();
    if (allowed()) persist();
    return run;
  }

  void _attachResearch(Topic topic, ResearchRun run) {
    topic.overviewStale = run.stale;
    topic.overview = '${run.report}\n\n本次研究及原始来源：[${run.id}]';
    topic.sourceIds = [run.id];
    topic.inputItemIds = run.inputItemIds?.toList();
  }

  Future<void> runDueTracking() async {
    if (_tracking || _disposed || _digestOnly) return;
    _tracking = true;
    try {
      await cleanupExpiredTrash();
      for (final topic in data.topics.toList()) {
        if (!topic.tracking ||
            !_topicSupported(topic) ||
            topic.authorizedScope != topic.question ||
            topic.nextRun?.isAfter(DateTime.now()) == true) {
          continue;
        }
        final alreadyQueued = runtime.jobs.any(
          (job) =>
              ['queued', 'running', 'paused'].contains(job.status) &&
              job.type == 'research' &&
              job.checkpoint['tracking'] == true &&
              data.runs.any(
                (run) => run.id == job.entityId && run.topicId == topic.id,
              ),
        );
        if (alreadyQueued) continue;
        if (!modelConfigured || !searchConfigured) {
          topic.status = 'waiting';
          topic.error = '待配置模型和搜索服务后补查';
          continue;
        }
        await _startUserWork();
        final run = ResearchRun(
          id: newId(),
          goal: topic.question,
          topicId: topic.id,
          callLimit: topic.callLimit,
          status: 'queued',
          inputItemIds: {
            ..._preferenceInputs(),
            ..._topicInputs(topic),
            if (_reusable(topic.inputItemIds)) ...topic.inputItemIds!,
          }.toList(),
        );
        data.runs.insert(0, run);
        _enqueue('research', run.id, checkpoint: {'tracking': true});
        topic.status = 'queued';
        topic.error = '';
      }
      _save();
      _scheduleQueue();
    } finally {
      _tracking = false;
    }
  }

  Future<void> resume() async {
    if (_disposed || _digestOnly) return;
    if (_resuming) {
      _resumeRequested = true;
      return;
    }
    _resuming = true;
    try {
      await resumeTasks();
      await refreshToday();
      await updateNotificationSettings();
      await refreshNotificationPermission();
      await cleanupExpiredTrash();
      diagnostics.prune();
      do {
        _resumeRequested = false;
        final batchRevision = _lifecycleRevision;
        final pendingShares = await native.pendingShares();
        _guard(batchRevision);
        for (final share in pendingShares) {
          _guard(batchRevision);
          final shareRevision = _lifecycleRevision;
          var acknowledge = true;
          if (!data.acknowledgedShares.contains(share.id)) {
            if (share.error.isNotEmpty) _notice('分享导入失败：${share.error}');
            for (final path in share.paths) {
              _guard(shareRevision);
              try {
                await importFile(path, analyzeAutomatically: !share.cancelled);
              } on FormatException catch (error) {
                _notice('分享导入失败：${error.message}');
              } catch (error) {
                acknowledge = false;
                _notice('分享尚未导入，可重试：$error');
              }
            }
            _guard(shareRevision);
            if (share.text.trim().isNotEmpty) {
              try {
                final match = RegExp(r'https?://[^\s<>]+')
                    .firstMatch(share.text);
                if (match != null) {
                  await captureUrl(
                    match[0]!,
                    analyzeAutomatically: !share.cancelled,
                  );
                } else {
                  await captureText(
                    share.text,
                    analyzeAutomatically: !share.cancelled,
                  );
                }
              } catch (error) {
                acknowledge = false;
                _notice('分享文字尚未导入：$error');
              }
            }
            _guard(shareRevision);
            if (acknowledge) data.acknowledgedShares.add(share.id);
            _save();
          }
          if (acknowledge) await native.acknowledgeShare(share.id);
        }
      } while (_resumeRequested && !_disposed);
      await runDueTracking();
      await _stopServiceIfIdle(force: true);
    } catch (error) {
      lastError = error.toString();
      if (!_disposed) notifyListeners();
    } finally {
      _resuming = false;
    }
  }

  void _notice(String message) {
    if (!data.notices.contains(message)) data.notices.insert(0, message);
  }

  Future<void> saveSettings(
    AppSettings settings, {
    String? apiKey,
    String? searchKey,
  }) async {
    for (final endpoint in [settings.endpoint, settings.searchEndpoint]) {
      final uri = Uri.tryParse(endpoint);
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty) {
        throw const FormatException('请输入有效的服务地址');
      }
    }
    if (apiKey != null) {
      await secrets.write('modelKey', apiKey.trim());
      _apiKey = apiKey.trim();
    }
    if (searchKey != null) {
      await secrets.write('searchKey', searchKey.trim());
      _searchKey = searchKey.trim();
    }
    if (!listEquals(
      settings.inferredInterests,
      data.settings.inferredInterests,
    )) {
      settings.confirmedInterests = settings.inferredInterests.toSet().toList();
    }
    settings.suppressedInterests = {
      ...data.settings.suppressedInterests,
      ...settings.suppressedInterests,
      ...data.settings.inferredInterests.where(
        (label) => !settings.inferredInterests.contains(label),
      ),
    }.toList();
    settings.suppressedInterests.removeWhere(
      settings.inferredInterests.contains,
    );
    data.settings = settings;
    diagnostics.debugEnabled = settings.debugModelLogging;
    _recomputeInterests();
    _save();
  }

  Future<void> clearNotices() async {
    data.notices.clear();
    _save();
  }

  Future<void> dismissError() async {
    lastError = null;
    if (!_disposed) notifyListeners();
  }

  Future<Uint8List> backup() async {
    if (busy || _tracking) throw StateError('请等待当前任务结束再备份');
    await cleanupExpiredTrash();
    return store.backup();
  }

  Future<void> restore(Uint8List bytes) async {
    await pauseTasks(cancelled: true);
    _invalidateTasks();
    store.restore(bytes, serviceSettings: data.settings);
    data = store.load();
    runtime = store.loadRuntime();
    diagnostics.debugEnabled = false;
    diagnostics.clear();
    await cleanupExpiredTrash();
    _recomputeInterests();
    _recoverInterruptedTasks();
    _save();
    await refreshToday();
    await updateNotificationSettings();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final timer in _refreshTimers.values) {
      timer.cancel();
    }
    native.setShareListener(null);
    native.setRuntimeEventListener(null);
    intelligence.close();
    diagnostics.close();
    store.close();
    super.dispose();
  }
}
