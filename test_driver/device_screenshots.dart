import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final output = Directory(
    Platform.environment['READLATER_SCREENSHOT_DIR'] ?? 'docs/v2/screenshots',
  );
  await output.create(recursive: true);
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(name) ||
          bytes.length < 8 ||
          bytes[0] != 137 ||
          bytes[1] != 80 ||
          bytes[2] != 78 ||
          bytes[3] != 71) {
        return false;
      }
      await File('${output.path}/$name.png').writeAsBytes(bytes, flush: true);
      return true;
    },
    responseDataCallback: (data) async {
      await File('${output.path}/device-result.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'passed': true,
          'screenshots': (data?['screenshots'] as List? ?? [])
              .map((entry) => entry['screenshotName'])
              .toList(),
        }),
      );
    },
  );
}
