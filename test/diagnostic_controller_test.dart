import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' hide DiagnosticLevel;
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/app_controller.dart';
import 'package:readlater/core/diagnostic_controller.dart';
import 'package:readlater/core/diagnostics.dart';
import 'package:readlater/core/store.dart';
import 'package:readlater/platform/native_bridge.dart';
import 'package:readlater/services/diagnostic_transfer.dart';

class _Native extends NativeBridge {
  _Native(this.getEnvironment);
  final Future<Map<String, Object?>> Function() getEnvironment;
  @override
  Future<Map<String, Object?>> diagnosticEnvironment() => getEnvironment();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppController controller;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('diagnostic-controller');
  });
  tearDown(() {
    controller.dispose();
    directory.deleteSync(recursive: true);
  });
  test(
    'optional environment failure does not prevent exporting existing logs',
    () async {
      controller = AppController(
        store: LocalStore(directory.path),
        native: _Native(
          () async => throw PlatformException(code: 'unavailable'),
        ),
      );
      controller.diagnostics.log(DiagnosticLevel.error, 'rss', 'failed');
      final bundle = await controller.prepareDiagnosticBundle(
        const DiagnosticSelection(),
      );
      final archive = ZipDecoder().decodeBytes(bundle.bytes);
      final env = jsonDecode(
        utf8.decode(archive.find('environment.json')!.content as List<int>),
      );
      expect(env['networkType'], 'unknown');
      expect(bundle.eventCount, greaterThan(0));
    },
  );
  test('clear during environment lookup cancels old snapshot without writing it back', () async {
    final gate = Completer<Map<String, Object?>>();
    controller = AppController(
      store: LocalStore(directory.path),
      native: _Native(() => gate.future),
    );
    final pending = controller.prepareDiagnosticBundle(
      const DiagnosticSelection(),
    );
    final assertion = expectLater(pending, throwsA(isA<DiagnosticCancelled>()));
    await controller.clearAppDiagnostics();
    gate.complete({'networkType': 'wifi'});
    await assertion;
    expect(await controller.pendingDiagnosticBundle(), isNull);
    expect(controller.diagnostics.events, isEmpty);
  });
}
