import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:readlater/core/diagnostics.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/services/intelligence_service.dart';

class SlowResponseClient extends http.BaseClient {
  final aborted = Completer<void>();
  final controller = StreamController<List<int>>();
  Timer? timer;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Abortable) {
      request.abortTrigger?.then((_) {
        if (!aborted.isCompleted) aborted.complete();
        timer?.cancel();
        controller.addError(http.RequestAbortedException(request.url));
        unawaited(controller.close());
      });
    }
    timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
      controller.add(utf8.encode(' '));
    });
    return http.StreamedResponse(controller.stream, 200);
  }

  @override
  void close() {
    timer?.cancel();
    unawaited(controller.close());
  }
}

class PermitCountingClient extends http.BaseClient {
  final secondEntered = Completer<void>();
  final releases = <Completer<void>>[];
  int sends = 0, active = 0, maxActive = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sends++;
    active++;
    maxActive = maxActive < active ? active : maxActive;
    if (sends == 2 && !secondEntered.isCompleted) secondEntered.complete();
    final release = Completer<void>();
    releases.add(release);
    if (request is http.Abortable) {
      request.abortTrigger?.then((_) {
        if (!release.isCompleted) release.complete();
      });
    }
    await release.future;
    active--;
    final body = jsonEncode({
      'choices': [
        {
          'message': {
            'content': jsonEncode({'answer': 'ok-$sends'}),
          },
        },
      ],
    });
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}

void main() {
  test('deadline aborts even a continuously trickling response', () async {
    final client = SlowResponseClient();
    final service = IntelligenceService(
      client: client,
      requestTimeout: const Duration(milliseconds: 55),
    );
    try {
      await expectLater(
        service
            .complete(AppSettings(textModel: 'fixture'), 'key', '{}')
            .timeout(const Duration(milliseconds: 300)),
        throwsA(isA<TimeoutException>()),
      );
      await client.aborted.future.timeout(const Duration(milliseconds: 100));
    } finally {
      service.close();
    }
  });
  test('one request cancellation aborts its stream', () async {
    final client = SlowResponseClient();
    final service = IntelligenceService(client: client);
    final cancel = Completer<void>();
    try {
      final request = service.complete(
        AppSettings(textModel: 'fixture'),
        'key',
        '{}',
        abortTrigger: cancel.future,
      );
      final assertion = expectLater(
        request,
        throwsA(isA<DiagnosticCancelled>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 25));
      cancel.complete();
      await assertion;
      expect(client.aborted.isCompleted, isTrue);
    } finally {
      service.close();
    }
  });
  test('text and media budgets reject before network submission', () async {
    final client = SlowResponseClient();
    final service = IntelligenceService(client: client);
    try {
      await expectLater(
        service.complete(AppSettings(textModel: 'fixture'), 'key', 'x' * 70000),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        service.complete(
          AppSettings(textModel: 'fixture', visionModel: 'vision'),
          'key',
          '{}',
          imageDataUrls: List.filled(5, 'data:image/jpeg;base64,AA=='),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(client.timer, isNull);
    } finally {
      service.close();
    }
  });

  test(
    'model permits cap direct complete calls at two and cancel queued waiters',
    () async {
      final client = PermitCountingClient();
      final service = IntelligenceService(client: client);
      final queuedCancel = Completer<void>();
      try {
        final first = service.complete(
          AppSettings(textModel: 'fixture'),
          'key',
          'first',
        );
        final second = service.complete(
          AppSettings(textModel: 'fixture'),
          'key',
          'second',
        );
        final third = service.complete(
          AppSettings(textModel: 'fixture'),
          'key',
          'third',
          abortTrigger: queuedCancel.future,
        );

        await client.secondEntered.future.timeout(
          const Duration(milliseconds: 300),
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(client.sends, 2);
        expect(client.maxActive, 2);

        queuedCancel.complete();
        await expectLater(third, throwsA(isA<DiagnosticCancelled>()));
        expect(client.sends, 2);

        for (final release in client.releases) {
          if (!release.isCompleted) release.complete();
        }
        expect((await first)['answer'], 'ok-2');
        expect((await second)['answer'], 'ok-2');
        expect(client.maxActive, 2);
      } finally {
        for (final release in client.releases) {
          if (!release.isCompleted) release.complete();
        }
        service.close();
      }
    },
  );
}
