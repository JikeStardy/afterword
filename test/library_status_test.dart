import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/app_controller.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/store.dart';
import 'package:readlater/ui/common.dart';
import 'package:readlater/ui/library_page.dart';

void main() {
  testWidgets('waiting PDF is not labelled as extraction failure', (
    tester,
  ) async {
    final controller = _controller(
      AppData(
        items: [
          LibraryItem(
            id: 'pdf',
            title: '待分析PDF',
            kind: ItemKind.pdf,
            body: 'PDF正文已保存',
            status: 'waiting',
            error: '原文已保存，配置模型后可分析',
          ),
        ],
      ),
    );

    await tester.pumpWidget(_wrap(controller));

    expect(find.text('待分析PDF'), findsOneWidget);
    expect(find.text('待配置模型'), findsOneWidget);
    expect(find.text('提取失败'), findsNothing);
  });

  testWidgets('failed web extraction keeps a failure-specific label', (
    tester,
  ) async {
    final controller = _controller(
      AppData(
        items: [
          LibraryItem(
            id: 'web',
            title: '失败网页',
            kind: ItemKind.web,
            url: 'https://example.com/post',
            status: 'failed',
            error: '正文提取失败：HTTP 403',
          ),
        ],
      ),
    );

    await tester.pumpWidget(_wrap(controller));

    expect(find.text('失败网页'), findsOneWidget);
    expect(find.text('提取失败'), findsOneWidget);
    expect(find.text('待配置模型'), findsNothing);
  });
}

Widget _wrap(AppController controller) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: readlaterTheme(),
    home: LibraryPage(controller: controller, data: controller.data),
  );
}

AppController _controller(AppData data) {
  final dir = Directory.systemTemp.createTempSync('readlater_library_status_');
  final controller = _LibraryStatusController(
    store: LocalStore('${dir.path}/library'),
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

class _LibraryStatusController extends AppController {
  _LibraryStatusController({required super.store});

  @override
  Future<void> resume() async {}
}
