import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

class DiagnosticCancelled implements Exception {
  const DiagnosticCancelled();
  @override
  String toString() => '资料或授权已变更，本次任务已停止；已发送的请求无法撤回';
}

DateTime _date(dynamic value) => DateTime.parse(value as String);

enum DiagnosticLevel {
  debug,
  info,
  warn,
  error;

  static DiagnosticLevel parse(Object? value) {
    final text = value?.toString().toLowerCase();
    return DiagnosticLevel.values.firstWhere(
      (level) => level.name == text,
      orElse: () => DiagnosticLevel.info,
    );
  }
}

class DiagnosticEvent {
  final String id, sessionId, module, name;
  final DiagnosticLevel level;
  final String? taskId, entityId;
  final DateTime time;
  final Map<String, Object?> data;

  DiagnosticEvent({
    required this.id,
    required this.sessionId,
    required this.level,
    required this.module,
    required this.name,
    required this.time,
    this.taskId,
    this.entityId,
    Map<String, Object?> data = const {},
  }) : data = Map.unmodifiable(data);

  DiagnosticEvent.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      sessionId = json['sessionId'] as String? ?? '',
      level = DiagnosticLevel.parse(json['level']),
      module = json['module'] as String? ?? 'unknown',
      name = json['name'] as String? ?? 'event',
      taskId = json['taskId'] as String?,
      entityId = json['entityId'] as String?,
      time = _date(json['time']),
      data = Map.unmodifiable(
        (json['data'] as Map? ?? const {}).cast<String, Object?>(),
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'level': level.name,
    'module': module,
    'name': name,
    'taskId': taskId,
    'entityId': entityId,
    'time': time.toIso8601String(),
    'data': data,
  };
}

class DiagnosticStep {
  final String id, label;
  final DateTime startedAt;
  DateTime? endedAt;
  String status = 'running';
  String? error;
  DiagnosticStep(this.id, this.label, this.startedAt);
  DiagnosticStep.fromJson(Map<String, dynamic> j)
    : id = j['id'],
      label = j['label'],
      startedAt = _date(j['startedAt']),
      endedAt = j['endedAt'] == null ? null : _date(j['endedAt']),
      status = j['status'],
      error = j['error'];
  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
    'status': status,
    'error': error,
  };
}

class DiagnosticCall {
  final String id, endpoint;
  final String? stepId, model;
  final DateTime startedAt;
  DateTime? endedAt;
  int? statusCode;
  String? requestId, error, request, response;
  Map<String, dynamic>? usage;
  bool requestTruncated = false, responseTruncated = false;
  final bool capture;
  DiagnosticCall(
    this.id,
    this.endpoint,
    this.startedAt, {
    this.stepId,
    this.model,
    this.capture = false,
  });
  DiagnosticCall.fromJson(Map<String, dynamic> j)
    : id = j['id'],
      endpoint = j['endpoint'],
      stepId = j['stepId'],
      model = j['model'],
      startedAt = _date(j['startedAt']),
      endedAt = j['endedAt'] == null ? null : _date(j['endedAt']),
      statusCode = j['statusCode'],
      requestId = j['requestId'],
      error = j['error'],
      request = j['request'],
      response = j['response'],
      usage = (j['usage'] as Map?)?.cast<String, dynamic>(),
      requestTruncated = j['requestTruncated'] == true,
      responseTruncated = j['responseTruncated'] == true,
      capture = false;
  Map<String, dynamic> toJson() => {
    'id': id,
    'endpoint': endpoint,
    'stepId': stepId,
    'model': model,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
    'statusCode': statusCode,
    'requestId': requestId,
    'usage': usage,
    'error': error,
    'request': request,
    'response': response,
    'requestTruncated': requestTruncated,
    'responseTruncated': responseTruncated,
  };
}

class DiagnosticTask {
  final String id, type, title;
  final String? sessionId, entityId, parentId;
  final List<String> inputItemIds;
  final DateTime startedAt;
  DateTime? endedAt;
  String status = 'running';
  String? error;
  final List<DiagnosticStep> steps;
  final List<DiagnosticCall> calls;
  DiagnosticTask(
    this.id,
    this.type,
    this.title,
    this.startedAt, {
    this.sessionId,
    this.entityId,
    this.parentId,
    List<String> inputItemIds = const [],
  }) : inputItemIds = [...inputItemIds],
       steps = [],
       calls = [];
  DiagnosticTask.fromJson(Map<String, dynamic> j)
    : id = j['id'],
      type = j['type'],
      title = j['title'],
      sessionId = j['sessionId'] as String?,
      entityId = j['entityId'],
      parentId = j['parentId'],
      inputItemIds = List<String>.from(j['inputItemIds'] ?? []),
      startedAt = _date(j['startedAt']),
      endedAt = j['endedAt'] == null ? null : _date(j['endedAt']),
      status = j['status'],
      error = j['error'],
      steps = (j['steps'] as List)
          .map((e) => DiagnosticStep.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      calls = (j['calls'] as List)
          .map((e) => DiagnosticCall.fromJson(Map<String, dynamic>.from(e)))
          .toList();
  Map<String, dynamic> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'type': type,
    'title': title,
    'entityId': entityId,
    'parentId': parentId,
    'inputItemIds': inputItemIds,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
    'status': status,
    'error': error,
    'steps': steps.map((s) => s.toJson()).toList(),
    'calls': calls.map((c) => c.toJson()).toList(),
  };
}

class _Context {
  final DiagnosticStore store;
  final DiagnosticTask task;
  final bool Function()? allowed;
  final Set<String> excludedUrls;
  final int generation;
  _Context(
    this.store,
    this.task,
    this.allowed,
    this.excludedUrls,
    this.generation,
  );
}

/// Zone-local context prevents concurrent tasks from sharing calls or guards.
class DiagnosticScope {
  static final _key = Object(), _stepKey = Object();
  static _Context? get _context => Zone.current[_key] as _Context?;
  static bool get hasContext => _context != null;
  static Set<String> get excludedUrls => _context?.excludedUrls ?? const {};
  static void registerCredentials(Iterable<String> credentials) {
    _context?.store._credentials.addAll(
      credentials.where((key) => key.isNotEmpty),
    );
  }

  static void log(
    DiagnosticLevel level,
    String module,
    String name, {
    Map<String, Object?> data = const {},
    Object? error,
    StackTrace? stackTrace,
    String? taskId,
    String? entityId,
  }) {
    final context = _context;
    if (context == null) return;
    context.store.log(
      level,
      module,
      name,
      data: data,
      error: error,
      stackTrace: stackTrace,
      taskId: taskId ?? context.task.id,
      entityId: entityId ?? context.task.entityId,
      contextGeneration: context.generation,
    );
  }

  static void ensureAllowed() {
    if (_context?.allowed?.call() == false) throw const DiagnosticCancelled();
  }

  static void failCurrent(String message) =>
      _context?.store.failCurrent(message);

  static Object? sanitizeEvent(Object? value) =>
      _context?.store.sanitizeEvent(value) ?? value;

  static String sanitizeError(Object error) {
    final store = _context?.store;
    if (store == null) return error.toString();
    return store.sanitize(store._errorText(error)).toString();
  }

  static Future<T> step<T>(String label, Future<T> Function() body) {
    final context = _context;
    if (context == null) return body();
    return context.store.step(label, body);
  }

  static DiagnosticCall? beginCall({
    required String endpoint,
    required Object request,
    required String credential,
    String? model,
  }) {
    final context = _context;
    if (context == null) return null;
    final store = context.store;
    DiagnosticCall? call;
    store._safe(() {
      store._credentials.add(credential);
      final record = DiagnosticCall(
        store._id(),
        store.sanitize(endpoint).toString(),
        store.clock(),
        stepId: Zone.current[_stepKey] as String?,
        model: model,
        capture: store.debugEnabled,
      );
      if (record.capture) {
        final payload = store._payload(request);
        record.request = payload.$1;
        record.requestTruncated = payload.$2;
      }
      context.task.calls.add(record);
      call = record;
    });
    store._saveContext(context);
    return call;
  }

  static void finishCall(
    DiagnosticCall? call, {
    String? response,
    int? statusCode,
    String? requestId,
    Map<String, dynamic>? usage,
    Object? error,
    bool responseTruncated = false,
  }) {
    final context = _context;
    if (call == null || context == null) return;
    final store = context.store;
    store._safe(() {
      call.endedAt = store.clock();
      call.statusCode = statusCode;
      call.requestId = requestId;
      call.usage = usage;
      call.error = error == null
          ? null
          : store.sanitizeEvent(store._errorText(error)).toString();
      if (call.capture && store.debugEnabled && response != null) {
        final payload = store._payload(response);
        call.response = payload.$1;
        call.responseTruncated = payload.$2 || responseTruncated;
      } else if (!store.debugEnabled) {
        call.request = null;
        call.response = null;
      }
      if (error != null) {
        context.task.status = error is DiagnosticCancelled
            ? 'cancelled'
            : 'failed';
        context.task.error = call.error;
      }
    });
    store._saveContext(context);
  }
}

/// Diagnostics are a separate, best-effort database and never block business work.
class DiagnosticStore extends ChangeNotifier {
  final DateTime Function() clock;
  final int maxBytes, payloadLimitBytes, maxQueuedEvents;
  Database? _database;
  late final String sessionId;
  DiagnosticLevel _level = DiagnosticLevel.info;
  bool debugEnabled = false;
  String? lastError;
  bool _closed = false;
  int _sequence = 0, _generation = 0, _droppedEvents = 0;
  final Set<String> _credentials = {}, _purgedIds = {};
  final Map<String, _Context> _active = {};
  final List<DiagnosticEvent> _pendingEvents = [];
  Timer? _flushTimer;
  DiagnosticStore(
    String path, {
    DateTime Function()? clock,
    this.maxBytes = 50 * 1024 * 1024,
    this.payloadLimitBytes = 256 * 1024,
    this.maxQueuedEvents = 256,
  }) : clock = clock ?? DateTime.now {
    sessionId = _id();
    _safe(() {
      if (path != ':memory:') File(path).parent.createSync(recursive: true);
      _database = sqlite3.open(path);
      _database!.execute('PRAGMA secure_delete=ON');
      _database!.execute('PRAGMA busy_timeout=1000');
      _database!.execute(
        'CREATE TABLE IF NOT EXISTS tasks (id TEXT PRIMARY KEY, started TEXT NOT NULL, data TEXT NOT NULL)',
      );
      _database!.execute(
        'CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, session TEXT NOT NULL, time TEXT NOT NULL, level TEXT NOT NULL, data TEXT NOT NULL)',
      );
      for (final task in _read()) {
        if (task.status == 'running') {
          task.status = 'interrupted';
          task.endedAt = this.clock();
          task.error = '应用中断，任务未完成';
          for (final step in task.steps.where((s) => s.status == 'running')) {
            step.status = 'interrupted';
            step.endedAt = this.clock();
          }
          for (final call in task.calls.where((c) => c.endedAt == null)) {
            call.endedAt = this.clock();
            call.error = '应用中断，未收到完整响应';
          }
          _write(task);
        }
      }
      _prune();
    });
  }
  String _id() => '${clock().microsecondsSinceEpoch}-${_sequence++}';
  DiagnosticLevel get level => _level;
  int get generation => _generation;
  void setLevel(DiagnosticLevel value) {
    final previous = _level;
    _level = value;
    if (value == DiagnosticLevel.debug && previous != DiagnosticLevel.debug) {
      log(
        DiagnosticLevel.debug,
        'diagnostics.session',
        'session.enabled',
        data: {'level': value.name},
      );
    }
    _notify();
  }

  void _safe(void Function() body) {
    try {
      if (_closed) throw StateError('诊断日志已关闭');
      body();
    } catch (_) {
      lastError = '诊断日志无法读写；业务操作仍可继续';
    }
  }

  void _notify() {
    if (!_closed) notifyListeners();
  }

  List<DiagnosticTask> _read() => _database!
      .select('SELECT data FROM tasks ORDER BY started DESC, rowid DESC')
      .map(
        (r) => DiagnosticTask.fromJson(
          jsonDecode(r['data'] as String) as Map<String, dynamic>,
        ),
      )
      .toList();

  List<DiagnosticEvent> _readEvents() => _database!
      .select('SELECT data FROM events ORDER BY time DESC, rowid DESC')
      .map(
        (r) => DiagnosticEvent.fromJson(
          jsonDecode(r['data'] as String) as Map<String, dynamic>,
        ),
      )
      .toList();

  List<DiagnosticTask> get tasks {
    var result = <DiagnosticTask>[];
    _safe(() {
      _prune();
      result = _read();
    });
    return result;
  }

  List<DiagnosticEvent> get events {
    var result = <DiagnosticEvent>[];
    _safe(() {
      _flushEvents();
      _prune();
      result = _readEvents();
    });
    return result;
  }

  String? get latestDebugSessionId {
    String? result;
    _safe(() {
      _flushEvents();
      final rows = _database!.select(
        "SELECT session FROM events WHERE level='debug' ORDER BY time DESC, rowid DESC LIMIT 1",
      );
      result = rows.isEmpty ? null : rows.first['session'] as String;
    });
    return result;
  }

  DiagnosticTask? task(String id) {
    for (final entry in tasks) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  int get logicalBytes {
    var bytes = 0;
    _safe(() {
      bytes =
          (_database!
                  .select(
                    'SELECT COALESCE(SUM(length(CAST(data AS BLOB))),0) AS size FROM tasks',
                  )
                  .single['size']
              as int) +
          (_database!
                  .select(
                    'SELECT COALESCE(SUM(length(CAST(data AS BLOB))),0) AS size FROM events',
                  )
                  .single['size']
              as int);
    });
    return bytes;
  }

  void registerCredentials(Iterable<String> credentials) {
    _credentials.addAll(credentials.where((key) => key.isNotEmpty));
  }

  void log(
    DiagnosticLevel level,
    String module,
    String name, {
    Map<String, Object?> data = const {},
    Object? error,
    StackTrace? stackTrace,
    String? taskId,
    String? entityId,
    int? contextGeneration,
  }) {
    try {
      if (_closed) throw StateError('诊断日志已关闭');
      if (contextGeneration != null && contextGeneration != _generation) {
        return;
      }
      if (level.index < _level.index) return;
      final cleanData = Map<String, Object?>.from(sanitizeEvent(data) as Map);
      if (error != null) {
        cleanData['errorType'] = error.runtimeType.toString();
        cleanData['error'] = sanitizeEvent(_errorText(error));
      }
      if (stackTrace != null && level == DiagnosticLevel.error) {
        cleanData['stackTrace'] = sanitizeEvent(_stackSummary(stackTrace));
      }
      if (_droppedEvents > 0) {
        cleanData['droppedBefore'] = _droppedEvents;
        _droppedEvents = 0;
      }
      final event = DiagnosticEvent(
        id: _id(),
        sessionId: sessionId,
        level: level,
        module: module,
        name: name,
        taskId: taskId,
        entityId: entityId,
        time: clock(),
        data: cleanData,
      );
      _enqueueEvent(event);
      if (level == DiagnosticLevel.error || _pendingEvents.length >= 16) {
        flush();
      } else {
        _scheduleFlush();
      }
      _notify();
    } catch (_) {
      lastError = '诊断日志无法读写；业务操作仍可继续';
    }
  }

  void _enqueueEvent(DiagnosticEvent event) {
    if (_pendingEvents.length < maxQueuedEvents) {
      _pendingEvents.add(event);
      return;
    }
    if (event.level == DiagnosticLevel.error) {
      final index = _pendingEvents.indexWhere(
        (item) => item.level != DiagnosticLevel.error,
      );
      if (index >= 0) {
        _pendingEvents.removeAt(index);
        _pendingEvents.add(event);
        _droppedEvents++;
        return;
      }
    }
    _droppedEvents++;
  }

  void flush() {
    _safe(_flushEvents);
  }

  void _scheduleFlush() {
    if (_flushTimer != null || _closed) return;
    _flushTimer = Timer(const Duration(milliseconds: 250), () {
      _flushTimer = null;
      flush();
    });
  }

  void _flushEvents() {
    if (_pendingEvents.isEmpty) return;
    _flushTimer?.cancel();
    _flushTimer = null;
    final batch = List<DiagnosticEvent>.from(_pendingEvents);
    _pendingEvents.clear();
    try {
      _database!.execute('BEGIN IMMEDIATE');
      for (final event in batch) {
        _writeEvent(event);
      }
      _database!.execute('COMMIT');
      _prune();
    } catch (_) {
      try {
        _database!.execute('ROLLBACK');
      } catch (_) {
        /* Database may already be closed or outside a transaction. */
      }
      for (final event in batch) {
        _enqueueEvent(event);
      }
      rethrow;
    }
  }

  void _writeEvent(DiagnosticEvent event) {
    final payload = jsonEncode(event.toJson());
    _database!.execute(
      'INSERT INTO events(id,session,time,level,data) VALUES(?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data',
      [
        event.id,
        event.sessionId,
        event.time.toIso8601String(),
        event.level.name,
        payload,
      ],
    );
  }

  Future<T> runTask<T>({
    required String type,
    required String title,
    String? entityId,
    List<String> inputItemIds = const [],
    bool Function()? allowed,
    Set<String> excludedUrls = const {},
    required Future<T> Function() body,
  }) async {
    final parent = DiagnosticScope._context;
    final task = DiagnosticTask(
      _id(),
      type,
      title,
      clock(),
      sessionId: sessionId,
      entityId: entityId,
      parentId: parent?.task.id,
      inputItemIds: inputItemIds,
    );
    final context = _Context(
      this,
      task,
      () => (parent?.allowed?.call() ?? true) && (allowed?.call() ?? true),
      {...?parent?.excludedUrls, ...excludedUrls},
      _generation,
    );
    _active[task.id] = context;
    _saveContext(context);
    log(
      DiagnosticLevel.info,
      'diagnostics.task',
      'task.start',
      taskId: task.id,
      entityId: task.entityId,
      data: {
        'type': type,
        'parentId': task.parentId,
        'inputCount': inputItemIds.length,
      },
      contextGeneration: context.generation,
    );
    return runZoned(
      () async {
        try {
          DiagnosticScope.ensureAllowed();
          final value = await body();
          DiagnosticScope.ensureAllowed();
          if (task.status == 'running') task.status = 'succeeded';
          return value;
        } catch (error) {
          task.status = error is DiagnosticCancelled ? 'cancelled' : 'failed';
          task.error = sanitizeEvent(_errorText(error)).toString();
          log(
            DiagnosticLevel.error,
            'diagnostics.task',
            'task.error',
            taskId: task.id,
            entityId: task.entityId,
            error: error,
            data: {'type': type, 'status': task.status},
            contextGeneration: context.generation,
          );
          rethrow;
        } finally {
          task.endedAt = clock();
          log(
            task.status == 'failed'
                ? DiagnosticLevel.error
                : DiagnosticLevel.info,
            'diagnostics.task',
            'task.end',
            taskId: task.id,
            entityId: task.entityId,
            data: {
              'type': type,
              'status': task.status,
              'durationMs': task.endedAt!
                  .difference(task.startedAt)
                  .inMilliseconds,
            },
            contextGeneration: context.generation,
          );
          _saveContext(context);
          _active.remove(task.id);
        }
      },
      zoneValues: {
        DiagnosticScope._key: context,
        DiagnosticScope._stepKey: null,
      },
    );
  }

  Future<T> step<T>(String label, Future<T> Function() body) async {
    final context = DiagnosticScope._context;
    if (context == null || context.store != this) return body();
    final step = DiagnosticStep(_id(), label, clock());
    context.task.steps.add(step);
    _saveContext(context);
    log(
      DiagnosticLevel.debug,
      'diagnostics.task',
      'step.start',
      taskId: context.task.id,
      entityId: context.task.entityId,
      data: {'stepId': step.id, 'label': label},
      contextGeneration: context.generation,
    );
    return runZoned(() async {
      try {
        DiagnosticScope.ensureAllowed();
        final result = await body();
        DiagnosticScope.ensureAllowed();
        step.status = 'succeeded';
        return result;
      } catch (error) {
        step.status = error is DiagnosticCancelled ? 'cancelled' : 'failed';
        step.error = sanitizeEvent(_errorText(error)).toString();
        log(
          DiagnosticLevel.error,
          'diagnostics.task',
          'step.error',
          taskId: context.task.id,
          entityId: context.task.entityId,
          error: error,
          data: {'stepId': step.id, 'label': label, 'status': step.status},
          contextGeneration: context.generation,
        );
        failCurrent(step.error!);
        rethrow;
      } finally {
        step.endedAt = clock();
        log(
          step.status == 'failed'
              ? DiagnosticLevel.error
              : DiagnosticLevel.debug,
          'diagnostics.task',
          'step.end',
          taskId: context.task.id,
          entityId: context.task.entityId,
          data: {
            'stepId': step.id,
            'label': label,
            'status': step.status,
            'durationMs': step.endedAt!
                .difference(step.startedAt)
                .inMilliseconds,
          },
          contextGeneration: context.generation,
        );
        _saveContext(context);
      }
    }, zoneValues: {DiagnosticScope._stepKey: step.id});
  }

  void failCurrent(String message) {
    final context = DiagnosticScope._context;
    if (context?.store != this) return;
    context!.task.status = 'failed';
    context.task.error = sanitizeEvent(message).toString();
    _saveContext(context);
  }

  void addInputIds(Iterable<String> ids) {
    final context = DiagnosticScope._context;
    if (context?.store != this) return;
    context!.task.inputItemIds.addAll(
      ids.where((id) => !context.task.inputItemIds.contains(id)),
    );
    _saveContext(context);
  }

  void _saveContext(_Context context) {
    if (context.generation != _generation) return;
    _safe(() {
      _write(context.task);
      _prune();
    });
    _notify();
  }

  void _erasePayloads(DiagnosticTask task) {
    for (final call in task.calls) {
      call.request = null;
      call.response = null;
      call.error = call.error == null ? null : '相关资料已永久删除';
    }
    if (task.error != null) task.error = '相关资料已永久删除';
    for (final step in task.steps) {
      if (step.error != null) step.error = '相关资料已永久删除';
    }
  }

  void _write(DiagnosticTask task) {
    if (_purgedIds.contains(task.entityId) ||
        task.inputItemIds.any(_purgedIds.contains)) {
      _erasePayloads(task);
    }
    final payload = jsonEncode(sanitize(task.toJson()));
    _database!.execute(
      'INSERT INTO tasks(id,started,data) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data',
      [task.id, task.startedAt.toIso8601String(), payload],
    );
  }

  void _prune() {
    final now = clock();
    var changed = false;
    _database!.execute(
      "DELETE FROM events WHERE (level='debug' AND time <= ?) OR (level<>'debug' AND time <= ?)",
      [
        now.subtract(const Duration(days: 7)).toIso8601String(),
        now.subtract(const Duration(days: 30)).toIso8601String(),
      ],
    );
    for (final task in _read()) {
      if (now.difference(task.startedAt) >= const Duration(days: 30)) {
        _database!.execute('DELETE FROM tasks WHERE id=?', [task.id]);
        changed = true;
        continue;
      }
      var payloadExpired = false;
      for (final call in task.calls) {
        if (now.difference(call.startedAt) >= const Duration(days: 7) &&
            (call.request != null || call.response != null)) {
          call.request = null;
          call.response = null;
          payloadExpired = true;
        }
      }
      if (payloadExpired) {
        _write(task);
        changed = true;
      }
    }
    while (logicalBytes > (maxBytes < 0 ? 0 : maxBytes)) {
      final oldestTasks = _database!.select(
        'SELECT id, started AS time FROM tasks ORDER BY started ASC, rowid ASC LIMIT 1',
      );
      final oldestEvents = _database!.select(
        'SELECT id, time FROM events ORDER BY time ASC, rowid ASC LIMIT 1',
      );
      if (oldestTasks.isEmpty && oldestEvents.isEmpty) break;
      final removeTask =
          oldestEvents.isEmpty ||
          (oldestTasks.isNotEmpty &&
              (oldestTasks.first['time'] as String).compareTo(
                    oldestEvents.first['time'] as String,
                  ) <=
                  0);
      if (removeTask) {
        _database!.execute('DELETE FROM tasks WHERE id=?', [
          oldestTasks.first['id'],
        ]);
      } else {
        _database!.execute('DELETE FROM events WHERE id=?', [
          oldestEvents.first['id'],
        ]);
      }
      changed = true;
    }
    // DELETE securely overwrites cells; VACUUM returns released pages to disk.
    if (changed) _database!.execute('VACUUM');
  }

  void prune() {
    _safe(_prune);
    _notify();
  }

  void clear() {
    _generation++;
    _flushTimer?.cancel();
    _flushTimer = null;
    _pendingEvents.clear();
    _droppedEvents = 0;
    _safe(() {
      _database!.execute('DELETE FROM tasks');
      _database!.execute('DELETE FROM events');
      _database!.execute('VACUUM');
    });
    _notify();
  }

  void purgeItemPayloads(Set<String> ids) {
    _purgedIds.addAll(ids);
    _safe(() {
      for (final context in _active.values) {
        if (ids.contains(context.task.entityId) ||
            context.task.inputItemIds.any(ids.contains)) {
          _erasePayloads(context.task);
        }
      }
      for (final task in _read()) {
        if (ids.contains(task.entityId) ||
            task.inputItemIds.any(ids.contains)) {
          _erasePayloads(task);
          _write(task);
        }
      }
      _database!.execute('VACUUM');
    });
    _notify();
  }

  Uint8List exportLogs({String? taskId}) {
    prune();
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'version': 1,
          'exportedAt': clock().toIso8601String(),
          'tasks': tasks
              .where((t) => taskId == null || t.id == taskId)
              .map((t) => t.toJson())
              .toList(),
          'events': events
              .where((event) => taskId == null || event.taskId == taskId)
              .map((event) => event.toJson())
              .toList(),
        }),
      ),
    );
  }

  static final _sensitive = RegExp(
    r'^(?:.*(?:apiKey|apiToken|accessToken|refreshToken|idToken|authToken|password|passwd|secret|secretKey|credential|credentials|privateKey)|authorization|proxyAuthorization|cookie|setCookie|token|key|searchKey|modelKey)$',
    caseSensitive: false,
  );

  static final _eventSensitive = RegExp(
    r'^(?:.*(?:apiKey|apiToken|accessToken|refreshToken|idToken|authToken|password|passwd|secret|secretKey|credential|credentials|privateKey|authorization|cookie|body|payload|content|html|xml|markdown|article|image|binary)|authorization|proxyAuthorization|cookie|setCookie|token|key|searchKey|modelKey|request|response)$',
    caseSensitive: false,
  );

  static final _urlInText = RegExp(
    r'''https?://[^\s"'<>]+''',
    caseSensitive: false,
  );

  static String safeUrl(Uri uri) {
    final buffer = StringBuffer()
      ..write(uri.scheme.isEmpty ? 'https' : uri.scheme)
      ..write('://')
      ..write(uri.host);
    if (uri.port != 0) buffer.write(':${uri.port}');
    final path = uri.path.isEmpty ? '/' : uri.path;
    if (path == '/') {
      buffer.write('/');
    } else {
      final digest = sha256.convert(utf8.encode(path)).toString();
      buffer.write('/[path:${digest.substring(0, 16)}]');
    }
    return buffer.toString();
  }

  String _stackSummary(StackTrace stackTrace) => stackTrace
      .toString()
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .take(12)
      .join('\n');

  String _errorText(Object error) {
    if (error is FormatException) {
      return error.message;
    }
    return error.toString().split('\n').first;
  }

  Object? sanitizeEvent(Object? value) => _sanitizeEvent(value, 0);

  Object? _sanitizeEvent(Object? value, int depth) {
    if (depth > 32) return '[深层嵌套内容已省略]';
    if (value is Uri) return safeUrl(value);
    if (value == null || value is num || value is bool) return value;
    if (value is DateTime) return value.toIso8601String();
    if (value is StackTrace) return _stackSummary(value);
    if (value is Map) {
      return value.map((key, v) {
        final cleanKey = sanitize(key.toString()).toString();
        final normalized = key.toString().replaceAll(RegExp(r'[-_\s]'), '');
        return MapEntry(
          cleanKey,
          _eventSensitive.hasMatch(normalized)
              ? '[REDACTED]'
              : _sanitizeEvent(v, depth + 1),
        );
      });
    }
    if (value is Iterable) {
      return value.map((v) => _sanitizeEvent(v, depth + 1)).toList();
    }
    var text = value is String ? value : value.toString();
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map || decoded is List) {
        return jsonEncode(_sanitizeEvent(decoded, depth + 1));
      }
    } catch (_) {
      /* Ordinary text. */
    }
    text = sanitize(text).toString();
    text = text.replaceAllMapped(_urlInText, (match) {
      final raw = match[0]!;
      final uri = Uri.tryParse(raw);
      return uri == null || !uri.hasScheme || uri.host.isEmpty
          ? '[url]'
          : safeUrl(uri);
    });
    text = text.replaceAll(
      RegExp(r'<[^>\r\n]{16,}>', caseSensitive: false),
      '[markup omitted]',
    );
    if (text.length > 2048) {
      text = '${text.substring(0, 2048)}\n[已截断]';
    }
    return text;
  }

  Object? sanitize(Object? value) => _sanitize(value, 0);

  Object? _sanitize(Object? value, int depth) {
    if (depth > 64) return '[深层嵌套内容已省略]';
    if (value is Map) {
      return value.map(
        (key, v) => MapEntry(
          _sanitize(key.toString(), depth + 1).toString(),
          _sensitive.hasMatch(key.toString().replaceAll(RegExp(r'[-_\s]'), ''))
              ? '[REDACTED]'
              : _sanitize(v, depth + 1),
        ),
      );
    }
    if (value is List) {
      return value.map((v) => _sanitize(v, depth + 1)).toList();
    }
    if (value is! String) return value;
    var text = value;
    text = text.replaceAll(
      RegExp(r'(https?://)[^/@\s]+@', caseSensitive: false),
      'https://[REDACTED]@',
    );
    for (final credential in _credentials.where((c) => c.isNotEmpty)) {
      text = text.replaceAll(credential, '[REDACTED]');
      final encoded = jsonEncode(credential);
      text = text.replaceAll(
        encoded.substring(1, encoded.length - 1),
        '[REDACTED]',
      );
      text = text.replaceAll(Uri.encodeComponent(credential), '[REDACTED]');
    }
    text = text.replaceAllMapped(
      RegExp(
        r'data:image/([^;,\s]+);base64,[A-Za-z0-9+/=\s]+',
        caseSensitive: false,
      ),
      (m) => '[image:${m[1]}; bytes omitted]',
    );
    text = text.replaceAll(
      RegExp(r'Bearer\s+[^\s"\x27,;]+', caseSensitive: false),
      'Bearer [REDACTED]',
    );
    text = text.replaceAllMapped(
      RegExp(
        r'([?&](?:api[_-]?key|token|key|secret|access_token)=)[^&#\s]+',
        caseSensitive: false,
      ),
      (m) => '${m[1]}[REDACTED]',
    );
    // Responses can contain JSON encoded inside model content strings.
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map || decoded is List) {
        return jsonEncode(_sanitize(decoded, depth + 1));
      }
    } catch (_) {
      /* Ordinary text. */
    }
    // Raw HTTP/error text is not necessarily a JSON object. A header value can
    // contain spaces, multiple cookies, or a folded continuation line; redact
    // its entire value instead of only the first token or cookie pair.
    text = text.replaceAllMapped(
      RegExp(
        r'''\b((?:proxy[-_]?authorization|authorization|set[-_]?cookie|cookie)["']?\s*[:=]\s*)[^\r\n]*(?:\r?\n[ \t]+[^\r\n]*)*''',
        caseSensitive: false,
      ),
      (match) => '${match[1]}[REDACTED]',
    );
    // Also sanitize non-JSON error bodies and truncated JSON fragments. Valid
    // structured content was handled above; a partial body may not decode.
    text = text.replaceAllMapped(
      RegExp(
        r'''(["']?(?:authorization|proxy[-_]?authorization|cookie|set[-_]?cookie|api[-_]?key|api[-_]?token|access[-_]?token|refresh[-_]?token|id[-_]?token|token|password|passwd|secret|client[-_]?secret|credential|credentials|key)["']?\s*[:=]\s*)("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[^\s,;&}\]]+)''',
        caseSensitive: false,
      ),
      (match) => '${match[1]}"[REDACTED]"',
    );
    return text;
  }

  (String, bool) _payload(Object value) {
    final clean = sanitize(value);
    final text = clean is String ? clean : jsonEncode(clean);
    final bytes = utf8.encode(text);
    if (bytes.length <= payloadLimitBytes) return (text, false);
    const marker = '\n[已截断]';
    final limit = (payloadLimitBytes - utf8.encode(marker).length).clamp(
      0,
      bytes.length,
    );
    var prefix = utf8.decode(bytes.sublist(0, limit), allowMalformed: true);
    while (utf8.encode(prefix + marker).length > payloadLimitBytes &&
        prefix.isNotEmpty) {
      prefix = prefix.substring(0, prefix.length - 1);
    }
    return (
      payloadLimitBytes < utf8.encode(marker).length ? '' : prefix + marker,
      true,
    );
  }

  void close() {
    if (_closed) return;
    _flushTimer?.cancel();
    _flushTimer = null;
    _safe(_flushEvents);
    _database?.close();
    _database = null;
    _closed = true;
    super.dispose();
  }
}
