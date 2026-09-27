// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:readlater/core/app_controller.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/store.dart';
import 'package:readlater/platform/native_bridge.dart';
import 'package:readlater/ui/common.dart';
import 'package:readlater/ui/settings_page.dart';

void main() {
  late FilePickerPlatform originalPicker;
  late _FakeFilePicker picker;

  setUp(() {
    originalPicker = FilePickerPlatform.instance;
    picker = _FakeFilePicker();
    FilePickerPlatform.instance = picker;
  });

  tearDown(() {
    FilePickerPlatform.instance = originalPicker;
  });

  testWidgets('backup export saves a restorable ZIP through file picker', (
    tester,
  ) async {
    _useLargeSurface(tester);
    final controller = _controller(AppData());
    final asset = Asset(
      path: 'assets/test-diagram.png',
      name: 'diagram.png',
      mime: 'image/png',
    );
    File(controller.store.assetPath(asset))
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3], flush: true);
    controller.data.items.add(
      LibraryItem(
        id: 'i1',
        title: '图像资料',
        kind: ItemKind.image,
        assets: [asset],
      ),
    );
    controller.store.save(controller.data);

    await tester.pumpWidget(_settingsPage(controller));
    await tester.pump();
    await _reveal(tester, find.text('导出 ZIP'), 500);
    await tester.tap(find.text('导出 ZIP'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(picker.savedFileName, startsWith('afterword-backup-'));
    expect(picker.savedFileName, endsWith('.zip'));
    expect(picker.savedMimeType, 'application/zip');
    expect(find.text('备份已导出'), findsOneWidget);

    final restoredDir = Directory.systemTemp.createTempSync(
      'readlater-export-restore-',
    );
    final restored = LocalStore(restoredDir.path);
    try {
      restored.restore(picker.savedBytes!);
      final item = restored.load().items.single;
      expect(item.title, '图像资料');
      expect(File(restored.assetPath(item.assets.single)).readAsBytesSync(), [
        1,
        2,
        3,
      ]);
    } finally {
      restored.close();
      restoredDir.deleteSync(recursive: true);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('restore refreshes visible preference fields after success', (
    tester,
  ) async {
    _useLargeSurface(tester);
    final archive = _backupFor(
      AppData(
        settings: AppSettings(
          endpoint: 'https://archive.example/v1',
          textModel: 'archive-text',
          visionModel: 'archive-vision',
          searchEndpoint: 'https://archive-search.example',
          customInstructions: '恢复后的分析要求',
          explicitInterests: ['个人知识管理'],
          inferredInterests: ['渐进总结'],
          confirmedInterests: ['渐进总结'],
        ),
      ),
    );
    picker.pickBytes = archive;
    final controller = _controller(
      AppData(
        settings: AppSettings(
          endpoint: 'https://trusted.example/v1',
          textModel: 'trusted-text',
          visionModel: 'trusted-vision',
          searchEndpoint: 'https://trusted-search.example',
          customInstructions: '旧的分析要求',
        ),
      ),
    );

    await tester.pumpWidget(_settingsPage(controller));
    await tester.pump();
    expect(find.text('旧的分析要求'), findsOneWidget);

    await _reveal(tester, find.text('恢复'), 500);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '恢复'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(picker.pickFileCalls, 1);
    expect(controller.restoreCalls, 1);
    expect(controller.restoreError, isNull);
    await _reveal(tester, find.text('https://trusted.example/v1'), -500);
    expect(find.text('https://trusted.example/v1'), findsOneWidget);
    expect(find.text('trusted-text'), findsOneWidget);
    expect(find.text('trusted-vision'), findsOneWidget);
    expect(controller.data.settings.customInstructions, '恢复后的分析要求');
    expect(controller.data.settings.endpoint, 'https://trusted.example/v1');
    await _reveal(tester, find.text('https://trusted-search.example'), 300);
    expect(find.text('https://trusted-search.example'), findsOneWidget);
    await _reveal(tester, find.text('恢复后的分析要求'), -400);
    expect(find.text('恢复后的分析要求'), findsOneWidget);
    expect(find.text('个人知识管理'), findsOneWidget);
    expect(find.text('渐进总结'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _reveal(WidgetTester tester, Finder target, double delta) async {
  final scrollable = find
      .descendant(
        of: find.byType(SettingsPage),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(
    target,
    delta,
    scrollable: scrollable,
    maxScrolls: 30,
  );
  await Scrollable.ensureVisible(tester.element(target), alignment: .5);
  await tester.pumpAndSettle();
}

void _useLargeSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _settingsPage(AppController controller) {
  return MaterialApp(
    theme: readlaterTheme(),
    home: SettingsPage(controller: controller, data: controller.data),
  );
}

_TestController _controller(AppData data) {
  final dir = Directory.systemTemp.createTempSync('readlater_backup_ui_');
  final controller = _TestController(
    store: LocalStore('${dir.path}/library'),
    native: _NoopNativeBridge(),
  );
  controller.data = data;
  controller.store.save(data);
  addTearDown(() {
    controller.dispose();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  return controller;
}

Uint8List _backupFor(AppData data) {
  final dir = Directory.systemTemp.createTempSync('readlater_backup_source_');
  final store = LocalStore(dir.path);
  try {
    store.save(data);
    return store.backup();
  } finally {
    store.close();
    dir.deleteSync(recursive: true);
  }
}

class _TestController extends AppController {
  _TestController({required super.store, required super.native});

  int restoreCalls = 0;
  Object? restoreError;

  @override
  Future<void> resume() async {}

  @override
  Future<void> restore(Uint8List bytes) async {
    restoreCalls++;
    try {
      await super.restore(bytes);
    } catch (error) {
      restoreError = error;
      rethrow;
    }
  }
}

class _NoopNativeBridge extends NativeBridge {
  @override
  Future<void> stopBackgroundWork() async {}

  @override
  Future<void> configureDigest({
    required bool enabled,
    required int hour,
    required int minute,
  }) async {}
}

class _FakeFilePicker extends FilePickerPlatform
    with MockPlatformInterfaceMixin {
  Uint8List? savedBytes;
  String? savedFileName;
  String? savedMimeType;
  Uint8List? pickBytes;
  int pickFileCalls = 0;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    savedFileName = fileName;
    savedBytes = bytes;
    savedMimeType = mimeType;
    return Uri.parse('content://readlater/$fileName');
  }

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    pickFileCalls++;
    final bytes = pickBytes;
    return bytes == null ? null : _MemoryPlatformFile(bytes);
  }
}

final class _MemoryPlatformFile extends PlatformFile {
  _MemoryPlatformFile(this._bytes);

  final Uint8List _bytes;

  @override
  String get name => 'backup.zip';

  @override
  Uri get uri => Uri.parse('memory://backup.zip');

  @override
  XFile get xFile => XFile.fromData(_bytes, name: name);

  @override
  Future<int?> length() async => _bytes.length;

  @override
  int? lengthSync() => _bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => _bytes;

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(_bytes);
}
