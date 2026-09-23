import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

import '../core/diagnostics.dart';

class DiagnosticSelection {
  const DiagnosticSelection({
    this.sessionId,
    this.module,
    this.level,
    this.taskId,
    this.from,
    this.to,
  });
  final String? sessionId, module, taskId;
  final DiagnosticLevel? level;
  final DateTime? from, to;
  bool includesTime(DateTime time) =>
      (from == null || !time.isBefore(from!)) &&
      (to == null || !time.isAfter(to!));
  bool includes(DiagnosticEvent event) =>
      (sessionId == null || event.sessionId == sessionId) &&
      (module == null || event.module == module) &&
      (level == null || event.level == level) &&
      (taskId == null || event.taskId == taskId) &&
      includesTime(event.time);
}

class DiagnosticUploadConfig {
  const DiagnosticUploadConfig(this.endpoint, this.token);
  final String endpoint, token;
}

class DiagnosticBundle {
  DiagnosticBundle({
    required this.reportId,
    required Uint8List bytes,
    required this.createdAt,
    required this.eventCount,
    required this.taskCount,
    this.from,
    this.to,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView(),
       sha256 = crypto.sha256.convert(bytes).toString();
  final String reportId, sha256;
  final Uint8List bytes;
  final DateTime createdAt;
  final DateTime? from, to;
  final int eventCount, taskCount;
  Map<String, Object?> get manifest => {
    'version': 1,
    'reportId': reportId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'from': from?.toUtc().toIso8601String(),
    'to': to?.toUtc().toIso8601String(),
    'eventCount': eventCount,
    'taskCount': taskCount,
    'modelPayloadsIncluded': false,
  };
}

class DiagnosticUploadException implements Exception {
  const DiagnosticUploadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Explicit local export/upload only. Never participates in instrumented clients.
class DiagnosticTransfer {
  DiagnosticTransfer({
    required this.directory,
    required this.readSecret,
    required this.writeSecret,
    http.Client Function()? clientFactory,
    this.timeout = const Duration(seconds: 60),
  }) : _clientFactory = clientFactory ?? http.Client.new;
  static const maxBytes = 64 * 1024 * 1024;
  static const _tokenKey = 'diagnosticUploadToken';
  final Directory directory;
  final Future<String?> Function(String) readSecret;
  final Future<void> Function(String, String) writeSecret;
  final http.Client Function() _clientFactory;
  final Duration timeout;

  static Uri validateEndpoint(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path != '/diagnostics') {
      throw const FormatException(
        '请输入完整接收地址，例如 http://192.168.1.2:18766/diagnostics；不能包含凭据或查询参数',
      );
    }
    if (uri.scheme == 'http') {
      final address = InternetAddress.tryParse(uri.host);
      var private = address?.isLoopback ?? false;
      if (address?.type == InternetAddressType.IPv4) {
        final b = address!.rawAddress;
        private =
            private ||
            b[0] == 10 ||
            (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
            (b[0] == 192 && b[1] == 168);
      } else if (address?.type == InternetAddressType.IPv6) {
        private = private || (address!.rawAddress[0] & 0xfe) == 0xfc;
      }
      if (!private) {
        throw const FormatException('HTTP 仅支持明确的局域网或回环 IP；其他地址请使用 HTTPS');
      }
    }
    return uri;
  }

  Future<DiagnosticUploadConfig> loadConfig() async {
    final file = File('${directory.path}/endpoint.json');
    final endpoint = await file.exists()
        ? (jsonDecode(await file.readAsString()) as Map)['endpoint'] as String
        : '';
    return DiagnosticUploadConfig(endpoint, await readSecret(_tokenKey) ?? '');
  }

  Future<void> saveConfig(String endpoint, String token) async {
    final uri = validateEndpoint(endpoint);
    if (token.trim().isEmpty ||
        token.length > 4096 ||
        RegExp(r'[\r\n]').hasMatch(token)) {
      throw const FormatException('请填写有效的上传令牌');
    }
    await directory.create(recursive: true);
    await writeSecret(_tokenKey, token.trim());
    final temp = File('${directory.path}/endpoint.tmp');
    await temp.writeAsString(
      jsonEncode({'endpoint': uri.toString()}),
      flush: true,
    );
    await temp.rename('${directory.path}/endpoint.json');
  }

  Future<DiagnosticBundle> createBundle(
    DiagnosticStore logs,
    DiagnosticSelection selection, {
    Map<String, Object?> environment = const {},
  }) async {
    logs.flush();
    final events = logs.events.where(selection.includes).toList();
    final eventTaskIds = events
        .map((e) => e.taskId)
        .whereType<String>()
        .toSet();
    final tasks = logs.tasks
        .where(
          (task) =>
              (selection.sessionId == null ||
                  task.sessionId == selection.sessionId) &&
              (selection.taskId == null || task.id == selection.taskId) &&
              ((selection.module == null && selection.level == null) ||
                  eventTaskIds.contains(task.id)) &&
              (selection.includesTime(task.startedAt) ||
                  eventTaskIds.contains(task.id)),
        )
        .toList();
    final times = [
      ...events.map((e) => e.time),
      ...tasks.map((t) => t.startedAt),
    ]..sort();
    final id = List<int>.generate(
      16,
      (_) => Random.secure().nextInt(256),
    ).map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    final createdAt = DateTime.now();
    final manifest = {
      'version': 1,
      'reportId': id,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'from': times.firstOrNull?.toUtc().toIso8601String(),
      'to': times.lastOrNull?.toUtc().toIso8601String(),
      'eventCount': events.length,
      'taskCount': tasks.length,
      'modelPayloadsIncluded': false,
    };
    // Allowlisted summaries intentionally exclude user titles and model payloads.
    final summaries = tasks
        .map(
          (task) => {
            'id': task.id,
            'sessionId': task.sessionId,
            'parentId': task.parentId,
            'type': task.type,
            'status': task.status,
            'entityId': task.entityId,
            'startedAt': task.startedAt.toUtc().toIso8601String(),
            'endedAt': task.endedAt?.toUtc().toIso8601String(),
            'error': logs.sanitizeEvent(task.error),
            'steps': task.steps
                .map(
                  (step) => {
                    'id': step.id,
                    'status': step.status,
                    'startedAt': step.startedAt.toUtc().toIso8601String(),
                    'endedAt': step.endedAt?.toUtc().toIso8601String(),
                    'error': logs.sanitizeEvent(step.error),
                  },
                )
                .toList(),
            'calls': task.calls
                .map(
                  (call) => {
                    'id': call.id,
                    'endpoint': _safeEndpoint(call.endpoint),
                    'statusCode': call.statusCode,
                    'startedAt': call.startedAt.toUtc().toIso8601String(),
                    'endedAt': call.endedAt?.toUtc().toIso8601String(),
                    'error': logs.sanitizeEvent(call.error),
                  },
                )
                .toList(),
          },
        )
        .toList();
    final archive = Archive();
    void add(String name, String text) {
      final bytes = utf8.encode(text);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    add('manifest.json', jsonEncode(manifest));
    add('environment.json', jsonEncode(logs.sanitizeEvent(environment)));
    add('tasks.json', jsonEncode(summaries));
    add(
      'events.jsonl',
      events.map((e) => jsonEncode(logs.sanitizeEvent(e.toJson()))).join('\n'),
    );
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    if (bytes.length > maxBytes) {
      throw const FormatException('诊断包超过 64 MiB，请缩小时间范围');
    }
    final bundle = DiagnosticBundle(
      reportId: id,
      bytes: bytes,
      createdAt: createdAt,
      eventCount: events.length,
      taskCount: tasks.length,
      from: times.firstOrNull,
      to: times.lastOrNull,
    );
    await directory.create(recursive: true);
    await File('${directory.path}/pending.tmp')
        .writeAsBytes(bytes, flush: true);
    await File('${directory.path}/pending.tmp')
        .rename('${directory.path}/pending.zip');
    await File('${directory.path}/pending-info.tmp').writeAsString(
      jsonEncode({...bundle.manifest, 'sha256': bundle.sha256}),
      flush: true,
    );
    await File('${directory.path}/pending-info.tmp')
        .rename('${directory.path}/pending.json');
    return bundle;
  }

  static String _safeEndpoint(String endpoint) {
    final uri = Uri.tryParse(endpoint);
    return uri != null && uri.hasAuthority
        ? DiagnosticStore.safeUrl(uri)
        : '[redacted]';
  }

  Future<DiagnosticBundle?> loadPending() async {
    final file = File('${directory.path}/pending.zip');
    final info = File('${directory.path}/pending.json');
    if (!await file.exists() || !await info.exists()) return null;
    if (await file.length() > maxBytes) {
      throw const FormatException('诊断包超过大小限制');
    }
    final data = jsonDecode(await info.readAsString()) as Map;
    final bundle = DiagnosticBundle(
      reportId: data['reportId'] as String,
      bytes: await file.readAsBytes(),
      createdAt: DateTime.parse(data['createdAt'] as String),
      eventCount: data['eventCount'] as int,
      taskCount: data['taskCount'] as int,
      from: data['from'] == null
          ? null
          : DateTime.parse(data['from'] as String),
      to: data['to'] == null ? null : DateTime.parse(data['to'] as String),
    );
    if (bundle.sha256 != data['sha256']) {
      throw const FormatException('本地诊断包校验失败，请重新生成');
    }
    return bundle;
  }

  Future<void> clearPending() async {
    for (final name in [
      'pending.zip',
      'pending.json',
      'pending.tmp',
      'pending-info.tmp',
    ]) {
      final file = File('${directory.path}/$name');
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> upload(
    DiagnosticBundle bundle,
    DiagnosticUploadConfig config,
  ) async {
    final endpoint = validateEndpoint(config.endpoint);
    if (config.token.isEmpty ||
        config.token.length > 4096 ||
        RegExp(r'[\r\n]').hasMatch(config.token)) {
      throw const DiagnosticUploadException('请先配置上传令牌');
    }
    if (bundle.bytes.length > maxBytes) {
      throw const DiagnosticUploadException('诊断包超过 64 MiB');
    }
    final client = _clientFactory();
    try {
      await (() async {
        final request = http.Request('POST', endpoint)
          ..followRedirects = false
          ..headers.addAll({
            'authorization': 'Bearer ${config.token}',
            'content-type': 'application/zip',
            'x-report-id': bundle.reportId,
          })
          ..bodyBytes = bundle.bytes;
        final response = await client.send(request);
        if (![200, 201].contains(response.statusCode)) {
          await response.stream.listen(null).cancel();
          throw DiagnosticUploadException(
            '上传失败：HTTP ${response.statusCode}；诊断包已保留',
          );
        }
        final bytes = BytesBuilder();
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > 16384) {
            throw const DiagnosticUploadException('接收端回执过大');
          }
          bytes.add(chunk);
        }
        final ack = jsonDecode(utf8.decode(bytes.takeBytes()));
        if (ack is! Map ||
            ack['reportId'] != bundle.reportId ||
            ack['bytes'] != bundle.bytes.length ||
            ack['sha256'] != bundle.sha256) {
          throw const DiagnosticUploadException('上传回执校验失败；诊断包已保留，可重试');
        }
      })().timeout(timeout);
    } on DiagnosticUploadException {
      rethrow;
    } on TimeoutException {
      throw const DiagnosticUploadException('上传超时；诊断包已保留，请检查 Wi-Fi 和电脑接收服务');
    } catch (_) {
      // No server text or URL/credentials are exposed through upload failures.
      throw const DiagnosticUploadException('上传未完成；诊断包已保留，请检查接收服务、防火墙及路由器设备隔离');
    } finally {
      client.close();
    }
  }
}
