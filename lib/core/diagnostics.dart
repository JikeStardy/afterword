import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

class DiagnosticCancelled implements Exception {
  const DiagnosticCancelled();
  @override
  String toString() => '资料或授权已变更，本次任务已停止；已发送的请求无法撤回';
}

DateTime _date(dynamic value) => DateTime.parse(value as String);

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
  final String? entityId, parentId;
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
  static Set<String> get excludedUrls => _context?.excludedUrls ?? const {};
  static void registerCredentials(Iterable<String> credentials) {
    _context?.store._credentials.addAll(
      credentials.where((key) => key.isNotEmpty),
    );
  }

  static void ensureAllowed() {
    if (_context?.allowed?.call() == false) throw const DiagnosticCancelled();
  }

  static void failCurrent(String message) =>
      _context?.store.failCurrent(message);

  static String sanitizeError(Object error) =>
      _context?.store.sanitize(error.toString()).toString() ?? error.toString();

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
          : store.sanitize(error.toString()).toString();
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
  final int maxBytes, payloadLimitBytes;
  Database? _database;
  bool debugEnabled = false;
  String? lastError;
  bool _closed = false;
  int _sequence = 0, _generation = 0;
  final Set<String> _credentials = {}, _purgedIds = {};
  final Map<String, _Context> _active = {};
  DiagnosticStore(
    String path, {
    DateTime Function()? clock,
    this.maxBytes = 50 * 1024 * 1024,
    this.payloadLimitBytes = 256 * 1024,
  }) : clock = clock ?? DateTime.now {
    _safe(() {
      if (path != ':memory:') File(path).parent.createSync(recursive: true);
      _database = sqlite3.open(path);
      _database!.execute('PRAGMA secure_delete=ON');
      _database!.execute('PRAGMA busy_timeout=1000');
      _database!.execute(
        'CREATE TABLE IF NOT EXISTS tasks (id TEXT PRIMARY KEY, started TEXT NOT NULL, data TEXT NOT NULL)',
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
  List<DiagnosticTask> get tasks {
    var result = <DiagnosticTask>[];
    _safe(() {
      _prune();
      result = _read();
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
          _database!
                  .select(
                    'SELECT COALESCE(SUM(length(CAST(data AS BLOB))),0) AS size FROM tasks',
                  )
                  .single['size']
              as int;
    });
    return bytes;
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
          task.error = sanitize(error.toString()).toString();
          rethrow;
        } finally {
          task.endedAt = clock();
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
    return runZoned(() async {
      try {
        DiagnosticScope.ensureAllowed();
        final result = await body();
        DiagnosticScope.ensureAllowed();
        step.status = 'succeeded';
        return result;
      } catch (error) {
        step.status = error is DiagnosticCancelled ? 'cancelled' : 'failed';
        step.error = sanitize(error.toString()).toString();
        failCurrent(step.error!);
        rethrow;
      } finally {
        step.endedAt = clock();
        _saveContext(context);
      }
    }, zoneValues: {DiagnosticScope._stepKey: step.id});
  }

  void failCurrent(String message) {
    final context = DiagnosticScope._context;
    if (context?.store != this) return;
    context!.task.status = 'failed';
    context.task.error = sanitize(message).toString();
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
      _database!.execute(
        'DELETE FROM tasks WHERE id IN (SELECT id FROM tasks ORDER BY started ASC, rowid ASC LIMIT 1)',
      );
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
    _safe(() {
      _database!.execute('DELETE FROM tasks');
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
        }),
      ),
    );
  }

  static final _sensitive = RegExp(
    r'^(?:.*(?:apiKey|apiToken|accessToken|refreshToken|idToken|authToken|password|passwd|secret|secretKey|credential|credentials|privateKey)|authorization|proxyAuthorization|cookie|setCookie|token|key|searchKey|modelKey)$',
    caseSensitive: false,
  );
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
    _database?.close();
    _database = null;
    _closed = true;
    super.dispose();
  }
}
