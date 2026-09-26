import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/app_controller.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/store.dart';
import 'package:readlater/ui/common.dart';
import 'package:readlater/ui/item_detail.dart';
import 'package:readlater/ui/library_page.dart';
import 'package:readlater/ui/research_detail.dart';
import 'package:readlater/ui/research_page.dart';
import 'package:readlater/ui/rss_page.dart';
import 'package:readlater/ui/today_page.dart';

import 'support/reading_fixture.dart';

void main() {
  for (final preset in ReadingPreset.values) {
    for (final width in [320.0, 390.0, 430.0]) {
      for (final scale in [1.0, 1.8]) {
        testWidgets(
          'populated reading chain ${preset.name} $width scale $scale',
          (tester) async {
            tester.view.physicalSize = Size(width, 850);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final directory = Directory.systemTemp.createTempSync(
              'reading_matrix_',
            );
            final controller = AppController(store: LocalStore(directory.path));
            final data = readingFixture(preset: preset);
            data.feeds.add(
              Feed(
                id: 'feed',
                title: '长期阅读笔记',
                url: 'https://example.com/feed',
              ),
            );
            data.entries.add(
              FeedEntry(
                id: 'entry',
                feedId: 'feed',
                title: '在连续阅读中保留自己的问题与思考',
                url: 'https://example.com/reading',
                summary: '阅读需要被放回真实情境，才有机会形成判断。',
              ),
            );
            controller.data = data;
            addTearDown(() {
              controller.dispose();
              directory.deleteSync(recursive: true);
            });
            final pages = <Widget>[
              TodayPage(controller: controller, data: data),
              LibraryPage(controller: controller, data: data),
              RssPage(controller: controller, data: data),
              ResearchPage(controller: controller, data: data),
              ArticleDetailPage(controller: controller, item: data.items.first),
              TopicDetailPage(
                controller: controller,
                topicId: data.topics.first.id,
              ),
            ];
            for (final page in pages) {
              await tester.pumpWidget(
                MaterialApp(
                  theme: readlaterTheme(preset),
                  home: MediaQuery(
                    data: MediaQueryData(
                      size: Size(width, 850),
                      textScaler: TextScaler.linear(scale),
                    ),
                    child: page,
                  ),
                ),
              );
              await tester.pumpAndSettle();
              expect(
                tester.takeException(),
                isNull,
                reason: '${page.runtimeType} at $width/$scale/${preset.name}',
              );
              await tester.pumpWidget(const SizedBox.shrink());
            }
          },
        );
      }
    }
  }
}
