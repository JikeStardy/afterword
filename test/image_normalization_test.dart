import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/platform/native_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('readlater/native');
  const bridge = NativeBridge(channel: channel);
  final calls = <MethodCall>[];

  tearDown(() async {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'normalizes an image through native channel and returns jpeg base64',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            expect(call.method, 'normalizeImage');
            expect(call.arguments, <String, Object?>{
              'path': '/private/share/photo.webp',
            });
            return 'normalized-jpeg-base64';
          });

      final normalized = await bridge.normalizeImage(
        '/private/share/photo.webp',
      );

      expect(normalized, 'normalized-jpeg-base64');
      expect(calls.single.method, 'normalizeImage');
    },
  );

  test('missing native image normalization is explicit', () async {
    await expectLater(
      bridge.normalizeImage('/tmp/photo.png'),
      throwsA(isA<UnsupportedError>()),
    );
  });
}
