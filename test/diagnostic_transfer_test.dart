import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:readlater/core/diagnostics.dart';
import 'package:readlater/services/diagnostic_transfer.dart';

void main() {
  late Directory dir;
  late DiagnosticStore logs;
  final secrets = <String, String>{};
  DiagnosticTransfer transfer({http.Client Function()? clientFactory}) =>
      DiagnosticTransfer(
        directory: dir,
        readSecret: (key) async => secrets[key],
        writeSecret: (key, value) async => secrets[key] = value,
        clientFactory: clientFactory,
      );
  setUp(() {
    dir = Directory.systemTemp.createTempSync('diagnostic-transfer');
    logs = DiagnosticStore('${dir.path}/logs.sqlite');
    secrets.clear();
  });
  tearDown(() {
    logs.close();
    dir.deleteSync(recursive: true);
  });
  test(
    'endpoint accepts explicit LAN HTTP and HTTPS but rejects unsafe forms',
    () {
      for (final url in [
        'http://192.168.1.2:18766/diagnostics',
        'http://10.0.0.1/diagnostics',
        'http://127.0.0.1/diagnostics',
        'http://[::1]/diagnostics',
        'https://example.com/diagnostics',
      ]) {
        expect(() => DiagnosticTransfer.validateEndpoint(url), returnsNormally);
      }
      for (final url in [
        'http://example.com/diagnostics',
        'http://8.8.8.8/diagnostics',
        'http://172.32.0.1/diagnostics',
        'http://127.0.0.1@evil.test/diagnostics',
        'https://u:p@example.com/diagnostics',
        'https://example.com/diagnostics?token=secret',
        'file:///tmp/a',
      ]) {
        expect(
          () => DiagnosticTransfer.validateEndpoint(url),
          throwsFormatException,
        );
      }
    },
  );
  test('config persists without token in ordinary files', () async {
    await transfer().saveConfig(
      'http://192.168.1.2:18766/diagnostics',
      'private-token',
    );
    final config = await transfer().loadConfig();
    expect(config.endpoint, contains('192.168.1.2'));
    expect(config.token, 'private-token');
    expect(
      await File('${dir.path}/endpoint.json').readAsString(),
      isNot(contains('private-token')),
    );
  });
  test(
    'bundle excludes model payloads and article title, snapshots persist',
    () async {
      logs.debugEnabled = true;
      await logs.runTask(
        type: 'analysis',
        title: 'private article title',
        body: () async {
          final call = DiagnosticScope.beginCall(
            endpoint: 'https://host.test/private-path?aihot_actor=secret-actor',
            request: {'text': 'secret original text'},
            credential: 'private-key',
          );
          DiagnosticScope.finishCall(call, response: 'secret model answer');
        },
      );
      final bundle = await transfer().createBundle(
        logs,
        const DiagnosticSelection(),
        environment: {'os': 'Android'},
      );
      final archive = ZipDecoder().decodeBytes(bundle.bytes);
      final all = archive.files
          .map((file) => utf8.decode(file.content as List<int>))
          .join('\n');
      for (final secret in [
        'secret original text',
        'secret model answer',
        'private article title',
        'secret-actor',
        'private-path',
        'private-key',
      ]) {
        expect(all, isNot(contains(secret)));
      }
      expect(
        archive.files.map((f) => f.name),
        containsAll([
          'manifest.json',
          'environment.json',
          'tasks.json',
          'events.jsonl',
        ]),
      );
      final restored = await transfer().loadPending();
      expect(restored!.reportId, bundle.reportId);
      expect(restored.sha256, bundle.sha256);
    },
  );
  test(
    'upload disables redirects and validates ack, failed snapshot survives',
    () async {
      final bundle = await transfer().createBundle(
        logs,
        const DiagnosticSelection(),
      );
      final config = DiagnosticUploadConfig(
        'http://127.0.0.1:18766/diagnostics',
        'token',
      );
      final success = transfer(
        clientFactory: () => MockClient((request) async {
          expect(request.followRedirects, isFalse);
          expect(request.headers['authorization'], 'Bearer token');
          expect(request.headers['x-report-id'], bundle.reportId);
          expect(request.bodyBytes, bundle.bytes);
          return http.Response(
            jsonEncode({
              'reportId': bundle.reportId,
              'bytes': bundle.bytes.length,
              'sha256': bundle.sha256,
            }),
            201,
          );
        }),
      );
      await success.upload(bundle, config);
      for (final status in [302, 401, 413, 500]) {
        final failed = transfer(
          clientFactory: () =>
              MockClient((_) async => http.Response('', status)),
        );
        await expectLater(
          failed.upload(bundle, config),
          throwsA(isA<DiagnosticUploadException>()),
        );
        expect(await failed.loadPending(), isNotNull);
      }
      final wrong = transfer(
        clientFactory: () => MockClient(
          (_) async => http.Response(
            jsonEncode({
              'reportId': bundle.reportId,
              'bytes': 1,
              'sha256': 'wrong',
            }),
            200,
          ),
        ),
      );
      await expectLater(
        wrong.upload(bundle, config),
        throwsA(isA<DiagnosticUploadException>()),
      );
    },
  );
  test('tampered pending bundle is not offered for upload', () async {
    await transfer().createBundle(logs, const DiagnosticSelection());
    await File('${dir.path}/pending.zip')
        .writeAsBytes(Uint8List.fromList([1, 2, 3]));
    await expectLater(transfer().loadPending(), throwsFormatException);
  });
  test(
    'timeout closes the client and keeps the same report for retry',
    () async {
      final bundle = await transfer().createBundle(
        logs,
        const DiagnosticSelection(),
      );
      final client = _HangingClient();
      final service = DiagnosticTransfer(
        directory: dir,
        readSecret: (key) async => secrets[key],
        writeSecret: (key, value) async => secrets[key] = value,
        clientFactory: () => client,
        timeout: const Duration(milliseconds: 10),
      );
      await expectLater(
        service.upload(
          bundle,
          const DiagnosticUploadConfig(
            'http://127.0.0.1:18766/diagnostics',
            'token',
          ),
        ),
        throwsA(
          isA<DiagnosticUploadException>().having(
            (error) => error.message,
            'timeout',
            contains('超时'),
          ),
        ),
      );
      expect(client.closed, isTrue);
      expect((await service.loadPending())!.reportId, bundle.reportId);
    },
  );
  test('bundle checksum matches bytes', () async {
    final bundle = await transfer().createBundle(
      logs,
      const DiagnosticSelection(),
    );
    expect(bundle.sha256, sha256.convert(bundle.bytes).toString());
  });
}

class _HangingClient extends http.BaseClient {
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Completer<http.StreamedResponse>().future;
  @override
  void close() {
    closed = true;
  }
}
