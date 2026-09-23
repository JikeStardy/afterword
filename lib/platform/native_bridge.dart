import 'package:flutter/services.dart';

class SharedInput {
  const SharedInput({
    required this.id,
    required this.text,
    required this.paths,
    this.error = '',
    this.cancelled = false,
  });

  factory SharedInput.fromMap(Map<Object?, Object?> map) {
    return SharedInput(
      id: map['id'] as String? ?? '',
      text: map['text'] as String? ?? '',
      paths: ((map['paths'] as List<Object?>?) ?? const <Object?>[])
          .whereType<String>()
          .toList(growable: false),
      error: map['error'] as String? ?? '',
      cancelled: map['cancelled'] == true,
    );
  }

  final String id;
  final String text;
  final List<String> paths;
  final String error;
  final bool cancelled;
}

class PdfPages {
  const PdfPages({required this.pageCount, required this.images});

  factory PdfPages.fromMap(Map<Object?, Object?> map) {
    return PdfPages(
      pageCount: map['pageCount'] as int? ?? 0,
      images: ((map['images'] as List<Object?>?) ?? const <Object?>[])
          .whereType<String>()
          .toList(growable: false),
    );
  }

  final int pageCount;
  final List<String> images;
}

class NativeRuntimeContext {
  const NativeRuntimeContext({
    required this.mode,
    this.openedEntityType,
    this.openedEntityId,
    this.launchedFromNotification = false,
    this.recentEvents = const <NativeRuntimeEvent>[],
  });

  factory NativeRuntimeContext.fromMap(Map<Object?, Object?> map) {
    return NativeRuntimeContext(
      mode: map['mode'] as String? ?? 'interactive',
      openedEntityType: map['openedEntityType'] as String?,
      openedEntityId: map['openedEntityId'] as String?,
      launchedFromNotification: map['launchedFromNotification'] == true,
      recentEvents:
          ((map['recentEvents'] as List<Object?>?) ?? const <Object?>[])
              .whereType<Map<Object?, Object?>>()
              .map(NativeRuntimeEvent.fromMap)
              .toList(growable: false),
    );
  }

  final String mode;
  final String? openedEntityType;
  final String? openedEntityId;
  final bool launchedFromNotification;
  final List<NativeRuntimeEvent> recentEvents;
}

class NativeRuntimeEvent {
  const NativeRuntimeEvent({
    required this.kind,
    this.entityType,
    this.entityId,
    this.message,
  });

  factory NativeRuntimeEvent.fromMap(Map<Object?, Object?> map) {
    return NativeRuntimeEvent(
      kind: map['kind'] as String? ?? '',
      entityType: map['entityType'] as String?,
      entityId: map['entityId'] as String?,
      message: map['message'] as String?,
    );
  }

  final String kind;
  final String? entityType;
  final String? entityId;
  final String? message;
}

class NativeBridge {
  const NativeBridge({
    MethodChannel channel = const MethodChannel('readlater/native'),
  }) : this._(channel);

  const NativeBridge._(this._channel);

  final MethodChannel _channel;
  static final Expando<_NativeBridgeListeners> _listeners =
      Expando<_NativeBridgeListeners>();

  void setShareListener(void Function()? listener) {
    _listenerState.share = listener;
    _installHandler();
  }

  void setRuntimeEventListener(
    void Function(NativeRuntimeEvent event)? listener,
  ) {
    _listenerState.runtimeEvent = listener;
    _installHandler();
  }

  _NativeBridgeListeners get _listenerState =>
      _listeners[this] ??= _NativeBridgeListeners();

  void _installHandler() {
    final listeners = _listenerState;
    if (listeners.share == null && listeners.runtimeEvent == null) {
      _channel.setMethodCallHandler(null);
      return;
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharesReady') {
        listeners.share?.call();
      } else if (call.method == 'runtimeEvent') {
        final arguments = call.arguments;
        if (arguments is Map<Object?, Object?>) {
          listeners.runtimeEvent?.call(NativeRuntimeEvent.fromMap(arguments));
        }
      }
    });
  }

  Future<NativeRuntimeContext> runtimeContext() async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'runtimeContext',
      );
      return NativeRuntimeContext.fromMap(result ?? const <Object?, Object?>{});
    } on MissingPluginException {
      return const NativeRuntimeContext(mode: 'interactive');
    }
  }

  Future<List<SharedInput>> pendingShares() async {
    try {
      final rawShares = await _channel.invokeMethod<List<Object?>>(
        'pendingShares',
      );
      return (rawShares ?? const <Object?>[])
          .whereType<Map<Object?, Object?>>()
          .map(SharedInput.fromMap)
          .where((share) => share.id.isNotEmpty)
          .toList(growable: false);
    } on MissingPluginException {
      return const <SharedInput>[];
    }
  }

  Future<void> acknowledgeShare(String id) async {
    try {
      await _channel.invokeMethod<void>('acknowledgeShare', <String, Object?>{
        'id': id,
      });
    } on MissingPluginException {
      return;
    }
  }

  Future<PdfPages> renderPdf(
    String path, {
    int startPage = 0,
    int maxPages = 4,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'renderPdf',
        <String, Object?>{
          'path': path,
          'startPage': startPage,
          'maxPages': maxPages,
        },
      );
      return PdfPages.fromMap(result ?? const <Object?, Object?>{});
    } on MissingPluginException {
      throw UnsupportedError(
        'PDF rendering is not available on this platform.',
      );
    }
  }

  Future<void> notify(String title, String body) async {
    try {
      await _channel.invokeMethod<void>('notify', <String, Object?>{
        'title': title,
        'body': body,
      });
    } on MissingPluginException {
      return;
    }
  }

  Future<void> startBackgroundWork() async {
    try {
      await _channel.invokeMethod<void>('startBackgroundWork');
    } on MissingPluginException {
      return;
    }
  }

  Future<void> updateBackgroundProgress({
    required String jobId,
    required String title,
    required String stage,
    int? completed,
    int? total,
  }) async {
    try {
      await _channel.invokeMethod<void>('updateBackgroundProgress', {
        'jobId': jobId,
        'title': title,
        'stage': stage,
        'completed': completed,
        'total': total,
      });
    } on MissingPluginException {
      return;
    }
  }

  Future<void> stopBackgroundWork() async {
    try {
      await _channel.invokeMethod<void>('stopBackgroundWork');
    } on MissingPluginException {
      return;
    }
  }

  Future<void> configureDigest({
    required bool enabled,
    required int hour,
    required int minute,
  }) async {
    try {
      await _channel.invokeMethod<void>('configureDigest', {
        'enabled': enabled,
        'hour': hour,
        'minute': minute,
      });
    } on MissingPluginException {
      return;
    }
  }

  Future<bool> notificationStatus() async {
    try {
      return await _channel.invokeMethod<bool>('notificationStatus') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> publishNotification({
    required String id,
    required String channel,
    required String title,
    required String body,
    String? entityType,
    String? entityId,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('publishNotification', {
            'id': id,
            'channel': channel,
            'title': title,
            'body': body,
            'entityType': entityType,
            'entityId': entityId,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> finishDigest() async {
    try {
      await _channel.invokeMethod<void>('finishDigest');
    } on MissingPluginException {
      return;
    }
  }

  Future<void> requestNotificationPermission() async {
    try {
      await _channel.invokeMethod<void>('requestNotificationPermission');
    } on MissingPluginException {
      return;
    }
  }

  Future<void> openFile(String path) async {
    try {
      await _channel.invokeMethod<void>('openFile', <String, Object?>{
        'path': path,
      });
    } on MissingPluginException {
      return;
    }
  }

  Future<void> openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const FormatException('仅支持打开 HTTP 或 HTTPS 来源链接');
    }
    try {
      await _channel.invokeMethod<void>('openUrl', {'url': url});
    } on MissingPluginException {
      throw UnsupportedError('当前平台尚不支持打开来源链接');
    }
  }
}

class _NativeBridgeListeners {
  void Function()? share;
  void Function(NativeRuntimeEvent event)? runtimeEvent;
}
