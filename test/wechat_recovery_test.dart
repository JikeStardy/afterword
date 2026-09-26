import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/app_controller.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/store.dart';
import 'package:readlater/platform/native_bridge.dart';
import 'package:readlater/services/content_service.dart';

class _Native extends NativeBridge {
  final result = Completer<WebArticleCapture?>();
  int opens = 0;
  Completer<void>? startEntered, releaseStart;
  @override
  Future<void> startBackgroundWork() async {
    if (releaseStart == null) return;
    if (!startEntered!.isCompleted) startEntered!.complete();
    await releaseStart!.future;
  }

  @override
  Future<WebArticleCapture?> captureWebArticle(String url) {
    opens++;
    return result.future;
  }
}

class _Content extends ContentService {
  int fetches = 0, images = 0;
  ExtractedArticle? article;
  Completer<void>? imageEntered, releaseImage;
  @override
  Future<ExtractedArticle> fetchArticle(String url) async {
    fetches++;
    if (article != null) return article!;
    throw StateError('HTTP must not fetch a recovered body');
  }

  @override
  Future<Uint8List> downloadImage(String url) async {
    images++;
    if (images == 1 && releaseImage != null) {
      imageEntered!.complete();
      await releaseImage!.future;
    }
    throw const SocketException('image unavailable');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppController controller;
  late _Native native;
  late _Content content;
  late LibraryItem item;
  late Directory directory;
  const url = 'https://mp.weixin.qq.com/s/article';
  const html =
      '<html><title>微信正文</title><div id="js_content">'
      '<p>这是用户看见并明确保存的真实正文。</p>'
      '<img data-src="https://mmbiz.qpic.cn/image.jpg"></div></html>';

  setUp(() {
    directory = Directory.systemTemp.createTempSync('wechat-recovery-');
    native = _Native();
    content = _Content();
    controller = AppController(
      store: LocalStore(directory.path),
      native: native,
      content: content,
    );
    item = LibraryItem(
      id: 'article',
      title: 'mp.weixin.qq.com',
      kind: ItemKind.web,
      url: url,
      status: 'failed',
      error: '未获取正文',
    );
    controller.data.items.add(item);
    controller.store.save(controller.data);
  });
  tearDown(() async {
    await controller.waitForIdle();
    controller.dispose();
    directory.deleteSync(recursive: true);
  });

  test(
    'pasted text with URL repairs same source and persists its origin',
    () async {
      await controller.supplementWebArticle(
        item.id,
        body: '用户粘贴原文 https://example.com/reference',
        title: '我的文章',
      );
      await controller.waitForIdle();
      expect(controller.data.items, hasLength(1));
      expect(item.url, url);
      expect(item.body, contains('https://example.com/reference'));
      expect(item.title, '我的文章');
      expect(item.bodyOrigin, 'pasted');
      expect(content.fetches, 0);
      expect(controller.store.load().items.single.bodyOrigin, 'pasted');
      expect(item.status, 'waiting');
    },
  );

  test(
    'task retry during image recovery never fetches the recovered body',
    () async {
      content.imageEntered = Completer<void>();
      content.releaseImage = Completer<void>();
      native.result.complete(const WebArticleCapture(url: url, html: html));
      await controller.recoverWebArticle(item.id);
      await content.imageEntered!.future;
      final job = controller.runtime.jobs.single;
      await controller.cancelJob(job.id);
      content.releaseImage!.complete();
      await controller.waitForIdle();
      await controller.retryJob(job.id);
      await controller.waitForIdle();
      expect(content.fetches, 0);
      expect(content.images, 2);
      expect(item.body, contains('明确保存'));
    },
  );

  test(
    'old failed HTTP task cannot overwrite supplemented text on retry',
    () async {
      await controller.retryCapture(item.id);
      await controller.waitForIdle();
      final oldJob = controller.runtime.jobs.single;
      expect(content.fetches, 1);
      await controller.supplementWebArticle(item.id, body: '保留这段手动正文');
      await controller.waitForIdle();
      await expectLater(controller.retryJob(oldJob.id), throwsStateError);
      expect(content.fetches, 1);
      expect(item.body, '保留这段手动正文');
    },
  );

  test(
    'same-host different article is rejected before changing source',
    () async {
      native.result.complete(
        const WebArticleCapture(
          url: 'https://mp.weixin.qq.com/s/another-article',
          html: html,
        ),
      );
      await expectLater(
        controller.recoverWebArticle(item.id),
        throwsFormatException,
      );
      expect(item.body, isEmpty);
      expect(item.url, url);
    },
  );

  test('unchanged HTTP recapture leaves current analysis valid', () async {
    item.body = '相同正文';
    item.analysis = Analysis(summary: '有效结论', inputItemIds: [item.id]);
    content.article = const ExtractedArticle(
      title: '文章',
      body: '相同正文',
      url: url,
      imageUrls: [],
    );
    await controller.retryCapture(item.id);
    await controller.waitForIdle();
    expect(item.analysis!.stale, false);
    expect(item.contentHistory, isEmpty);
    expect(item.contentVersion, 1);
  });

  test(
    'replacement during native startup cannot revive an old retry',
    () async {
      final old = BackgroundJob(
        id: 'old',
        type: 'capture',
        entityId: item.id,
        status: 'paused',
      );
      controller.runtime.jobs.add(old);
      native.startEntered = Completer<void>();
      native.releaseStart = Completer<void>();
      final retry = controller.retryJob(old.id);
      await native.startEntered!.future;
      await controller.supplementWebArticle(item.id, body: '新版正文');
      final rejected = expectLater(retry, throwsA(anything));
      native.releaseStart!.complete();
      await rejected;
      await controller.waitForIdle();
      expect(old.checkpoint['sourceReplaced'], true);
      expect(old.status, 'cancelled');
      expect(content.fetches, 0);
      expect(item.body, '新版正文');
    },
  );

  test(
    'cancelled visible capture does not change data or enqueue work',
    () async {
      final before = item.toJson();
      native.result.complete(null);
      expect(await controller.recoverWebArticle(item.id), false);
      expect(item.toJson(), before);
      expect(controller.runtime.jobs, isEmpty);
    },
  );

  test(
    'visible capture preserves text when images fail and retries only images',
    () async {
      native.result.complete(const WebArticleCapture(url: url, html: html));
      expect(await controller.recoverWebArticle(item.id), true);
      await controller.waitForIdle();
      expect(item.body, contains('明确保存'));
      expect(item.bodyOrigin, 'webview');
      expect(item.warning, contains('图片未能下载'));
      expect(content.fetches, 0);
      await controller.retryImages(item.id);
      await controller.waitForIdle();
      expect(content.images, 2);
      expect(content.fetches, 0);
      expect(controller.store.load().items.single.body, item.body);
    },
  );

  test(
    'verification page and foreign final URL cannot replace saved content',
    () async {
      native.result.complete(
        const WebArticleCapture(
          url: url,
          html: '<html>当前环境异常，完成验证后继续访问</html>',
        ),
      );
      await expectLater(
        controller.recoverWebArticle(item.id),
        throwsFormatException,
      );
      expect(item.body, isEmpty);
      expect(item.status, 'failed');
      expect(controller.runtime.jobs, isEmpty);
    },
  );

  test('rejects untrusted final page host', () async {
    native.result.complete(
      const WebArticleCapture(url: 'https://evil.example/s/a', html: html),
    );
    await expectLater(
      controller.recoverWebArticle(item.id),
      throwsFormatException,
    );
    expect(item.body, isEmpty);
  });

  test('archive while page is open rejects late capture', () async {
    final pending = controller.recoverWebArticle(item.id);
    await controller.archiveItems([item.id]);
    native.result.complete(const WebArticleCapture(url: url, html: html));
    await expectLater(pending, throwsA(anything));
    expect(item.body, isEmpty);
    expect(controller.runtime.jobs, isEmpty);
  });

  test('new pasted content wins over an older open page', () async {
    final pending = controller.recoverWebArticle(item.id);
    await controller.supplementWebArticle(item.id, body: '更新后的原文');
    native.result.complete(const WebArticleCapture(url: url, html: html));
    await expectLater(pending, throwsA(anything));
    expect(item.body, '更新后的原文');
    expect(item.bodyOrigin, 'pasted');
  });

  test('duplicate open requests do not open another viewer', () async {
    final pending = controller.recoverWebArticle(item.id);
    await expectLater(controller.recoverWebArticle(item.id), throwsStateError);
    expect(native.opens, 1);
    native.result.complete(null);
    expect(await pending, false);
  });

  test(
    'replacement retains history, invalidates anchors and prior insights',
    () async {
      item.body = '旧正文';
      item.bodyOrigin = 'pasted';
      item.analysis = Analysis(summary: '旧结论', inputItemIds: [item.id]);
      item.annotations.add(
        Annotation(
          id: 'a',
          anchor: EvidenceAnchor(
            sourceId: item.id,
            sourceVersion: 1,
            quote: '旧正文',
          ),
        ),
      );
      await controller.supplementWebArticle(item.id, body: '新正文');
      expect(item.contentVersion, 2);
      expect(item.contentHistory.single.body, '旧正文');
      expect(item.contentHistory.single.bodyOrigin, 'pasted');
      expect(item.annotations.single.anchor.unresolved, true);
      expect(item.analysis!.stale, true);
      final restored = LocalStore('${directory.path}/restored');
      try {
        restored.restore(controller.store.backup());
        final saved = restored.load().items.single;
        expect(saved.bodyOrigin, 'pasted');
        expect(saved.contentHistory.single.bodyOrigin, 'pasted');
        expect(saved.url, url);
        expect(saved.annotations.single.anchor.unresolved, true);
      } finally {
        restored.close();
      }
    },
  );

  test('empty and archived manual input is rejected without changes', () async {
    await expectLater(
      controller.supplementWebArticle(item.id, body: '  '),
      throwsFormatException,
    );
    await controller.archiveItems([item.id]);
    await expectLater(
      controller.supplementWebArticle(item.id, body: '正文'),
      throwsStateError,
    );
    expect(item.body, isEmpty);
  });
}
