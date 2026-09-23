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
                'cancelled': true,
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
    expect(shares.single.cancelled, isTrue);
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
    final runtimeEvents = <NativeRuntimeEvent>[];
    bridge.setShareListener(() {
      readyEvents += 1;
    });
    bridge.setRuntimeEventListener(runtimeEvents.add);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'readlater/native',
          channel.codec.encodeMethodCall(const MethodCall('sharesReady')),
          (_) {},
        );

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'readlater/native',
          channel.codec.encodeMethodCall(
            const MethodCall('runtimeEvent', <String, Object?>{
              'kind': 'openEntity',
              'entityType': 'item',
              'entityId': 'item-1',
            }),
          ),
          (_) {},
        );

    expect(readyEvents, 1);
    expect(runtimeEvents.single.kind, 'openEntity');
    expect(runtimeEvents.single.entityType, 'item');
    expect(runtimeEvents.single.entityId, 'item-1');
  });

  test('reads runtime context and sends background commands', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'runtimeContext') {
            return <String, Object?>{
              'mode': 'digestOnly',
              'openedEntityType': 'research',
              'openedEntityId': 'run-1',
              'launchedFromNotification': true,
              'recentEvents': <Map<String, Object?>>[
                <String, Object?>{'kind': 'interactive'},
                <String, Object?>{
                  'kind': 'openEntity',
                  'entityType': 'today',
                  'entityId': '',
                },
              ],
            };
          }
          if (call.method == 'diagnosticEnvironment') {
            return <String, Object?>{
              'platform': 'android',
              'appVersion': '1.2.3',
              'buildNumber': '7',
              'osVersion': '16',
              'networkType': 'mobile',
              'vpnActive': false,
            };
          }
          if (call.method == 'notificationStatus') {
            return true;
          }
          if (call.method == 'publishNotification') {
            return true;
          }
          return null;
        });

    final context = await bridge.runtimeContext();
    final environment = await bridge.diagnosticEnvironment();
    await bridge.startBackgroundWork();
    await bridge.updateBackgroundProgress(
      jobId: 'job-1',
      title: '分析资料',
      stage: 'PDF 2/4',
      completed: 2,
      total: 4,
    );
    await bridge.stopBackgroundWork();
    await bridge.configureDigest(enabled: true, hour: 20, minute: 15);
    final notificationsAllowed = await bridge.notificationStatus();
    final notificationPublished = await bridge.publishNotification(
      id: 'digest-2026-09-22',
      channel: 'digest',
      title: '今日推荐',
      body: '有 3 条值得读',
      entityType: 'today',
      entityId: '2026-09-22',
    );
    await bridge.finishDigest();

    expect(context.mode, 'digestOnly');
    expect(context.openedEntityType, 'research');
    expect(context.openedEntityId, 'run-1');
    expect(context.launchedFromNotification, isTrue);
    expect(context.recentEvents.map((event) => event.kind), <String>[
      'interactive',
      'openEntity',
    ]);
    expect(context.recentEvents.last.entityType, 'today');
    expect(context.recentEvents.last.entityId, '');
    expect(environment['networkType'], 'mobile');
    expect(environment['vpnActive'], isFalse);
    expect(notificationsAllowed, isTrue);
    expect(notificationPublished, isTrue);
    expect(calls.map((call) => call.method), <String>[
      'runtimeContext',
      'diagnosticEnvironment',
      'startBackgroundWork',
      'updateBackgroundProgress',
      'stopBackgroundWork',
      'configureDigest',
      'notificationStatus',
      'publishNotification',
      'finishDigest',
    ]);
    expect(calls[3].arguments, <String, Object?>{
      'jobId': 'job-1',
      'title': '分析资料',
      'stage': 'PDF 2/4',
      'completed': 2,
      'total': 4,
    });
    expect(calls[5].arguments, <String, Object?>{
      'enabled': true,
      'hour': 20,
      'minute': 15,
    });
    expect(calls[7].arguments, <String, Object?>{
      'id': 'digest-2026-09-22',
      'channel': 'digest',
      'title': '今日推荐',
      'body': '有 3 条值得读',
      'entityType': 'today',
      'entityId': '2026-09-22',
    });

    await bridge.publishNotification(
      id: 'digest-today',
      channel: 'digest',
      title: '今日推荐',
      body: '有 2 条值得读',
      entityType: 'today',
    );
    expect(calls.last.arguments, <String, Object?>{
      'id': 'digest-today',
      'channel': 'digest',
      'title': '今日推荐',
      'body': '有 2 条值得读',
      'entityType': 'today',
      'entityId': null,
    });
  });

  test('keeps runtime listeners scoped to bridge instances', () async {
    const firstChannel = MethodChannel('readlater/native/first');
    const secondChannel = MethodChannel('readlater/native/second');
    const firstBridge = NativeBridge(channel: firstChannel);
    const secondBridge = NativeBridge(channel: secondChannel);
    var firstShares = 0;
    var secondShares = 0;

    firstBridge.setShareListener(() => firstShares += 1);
    secondBridge.setShareListener(() => secondShares += 1);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'readlater/native/first',
          firstChannel.codec.encodeMethodCall(const MethodCall('sharesReady')),
          (_) {},
        );

    expect(firstShares, 1);
    expect(secondShares, 0);

    firstBridge.setShareListener(null);
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'readlater/native/second',
          secondChannel.codec.encodeMethodCall(const MethodCall('sharesReady')),
          (_) {},
        );

    expect(firstShares, 1);
    expect(secondShares, 1);
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
