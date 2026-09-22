import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/platform/native_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('readlater/native');
  late List<MethodCall> calls;
  late NativeBridge bridge;

  setUp(() {
    calls = <MethodCall>[];
    bridge = const NativeBridge(channel: channel);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('reads pending shares and acknowledges by id', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'pendingShares') {
            return <Map<String, Object?>>[
              <String, Object?>{
                'id': 'share-1',
                'text': 'https://example.com/post',
                'paths': <String>['/private/share/image.jpg'],
                'error': 'image import failed',
              },
            ];
          }
          if (call.method == 'acknowledgeShare') {
            return null;
          }
          throw PlatformException(code: 'unexpected');
        });

    final shares = await bridge.pendingShares();
    await bridge.acknowledgeShare(shares.single.id);

    expect(shares.single.id, 'share-1');
    expect(shares.single.text, 'https://example.com/post');
    expect(shares.single.paths, <String>['/private/share/image.jpg']);
    expect(shares.single.error, 'image import failed');
    expect(calls.last.method, 'acknowledgeShare');
    expect(calls.last.arguments, <String, Object?>{'id': 'share-1'});
  });

  test(
    'opens only web source URLs and surfaces missing viewer failures',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.arguments['url'] == 'https://example.com/missing') {
              throw PlatformException(code: 'no_viewer');
            }
            return null;
          });
      await bridge.openUrl('https://example.com/source');
      expect(calls.single.method, 'openUrl');
      expect(calls.single.arguments, {'url': 'https://example.com/source'});
      for (final url in [
        'javascript:alert(1)',
        'file:///private/data',
        'not-a-url',
      ]) {
        await expectLater(bridge.openUrl(url), throwsFormatException);
      }
      expect(calls.length, 1);
      await expectLater(
        bridge.openUrl('https://example.com/missing'),
        throwsA(isA<PlatformException>()),
      );
    },
  );

  test('notifies listener when native side reports shares ready', () async {
    var readyEvents = 0;
    bridge.setShareListener(() {
      readyEvents += 1;
    });

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'readlater/native',
          channel.codec.encodeMethodCall(const MethodCall('sharesReady')),
          (_) {},
        );

    expect(readyEvents, 1);
  });

  test('renders a bounded pdf page batch through the native channel', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          expect(call.method, 'renderPdf');
          expect(call.arguments, <String, Object?>{
            'path': '/private/share/doc.pdf',
            'startPage': 2,
            'maxPages': 3,
          });
          return <String, Object?>{
            'pageCount': 9,
            'images': <String>['jpeg-page-2', 'jpeg-page-3'],
          };
        });

    final pages = await bridge.renderPdf(
      '/private/share/doc.pdf',
      startPage: 2,
      maxPages: 3,
    );

    expect(pages.pageCount, 9);
    expect(pages.images, <String>['jpeg-page-2', 'jpeg-page-3']);
    expect(calls.single.method, 'renderPdf');
  });

  test('forwards notification and open file operations', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });

    await bridge.requestNotificationPermission();
    await bridge.notify('重要更新', '主题综述有新结论');
    await bridge.openFile('/private/share/doc.pdf');

    expect(calls.map((call) => call.method), <String>[
      'requestNotificationPermission',
      'notify',
      'openFile',
    ]);
    expect(calls[1].arguments, <String, Object?>{
      'title': '重要更新',
      'body': '主题综述有新结论',
    });
    expect(calls[2].arguments, <String, Object?>{
      'path': '/private/share/doc.pdf',
    });
  });

  test(
    'non Android share inbox is empty and pdf rendering is explicit',
    () async {
      final shares = await bridge.pendingShares();

      expect(shares, isEmpty);
      await expectLater(
        bridge.renderPdf('/tmp/doc.pdf'),
        throwsA(isA<UnsupportedError>()),
      );
    },
  );
}
