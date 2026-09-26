part of 'app_controller.dart';

extension WebCaptureController on AppController {
  LibraryItem _webItem(String itemId) {
    final item = _item(itemId);
    _requireActive(item);
    if (item.kind != ItemKind.web) throw StateError('只有网页支持补充正文');
    if (_digestOnly || _disposed) throw StateError('请打开资料后重试');
    return item;
  }

  Future<bool> recoverWebArticle(String itemId) async {
    final item = _webItem(itemId);
    if (!WebArticleCapture.allowsUrl(item.url)) {
      throw const FormatException('页面保存仅支持 HTTPS 微信公众号链接');
    }
    if (!_openWebCaptures.add(itemId)) throw StateError('该文章的保存页面已打开');
    final revision = _lifecycleRevision;
    final version = item.contentVersion;
    final originalBody = item.body;
    final originalUrl = item.url;
    try {
      final capture = await native.captureWebArticle(originalUrl);
      if (capture == null) return false;
      _guard(revision);
      if (!identical(_webItem(itemId), item) ||
          version != item.contentVersion ||
          originalBody != item.body ||
          originalUrl != item.url) {
        throw StateError('资料已更新，请重新打开页面后保存');
      }
      capture.validate();
      if (!WebArticleCapture.isSameArticle(originalUrl, capture.url)) {
        throw const FormatException('页面已跳转到其他文章，请返回原文章或另行收藏');
      }
      final article = ContentService.extractHtml(capture.html, capture.url);
      _saveRecoveredArticle(item, article, origin: 'webview');
      return true;
    } finally {
      _openWebCaptures.remove(itemId);
    }
  }

  Future<void> supplementWebArticle(
    String itemId, {
    required String body,
    String title = '',
  }) async {
    final item = _webItem(itemId);
    final text = body.trim();
    if (text.isEmpty) throw const FormatException('请粘贴需要保存的正文');
    if (body.length > ContentService.maxArticleBytes ||
        utf8.encode(body).length > ContentService.maxArticleBytes ||
        title.length > 500) {
      throw const FormatException('正文不能超过 5 MB，标题不能超过 500 字');
    }
    final paragraphs = text.split(RegExp(r'\n\s*\n'));
    _saveRecoveredArticle(
      item,
      ExtractedArticle(
        title: title.trim().isEmpty ? item.title : title.trim(),
        body: text,
        url: item.url,
        imageUrls: const [],
        contentBlocks: [
          for (var i = 0; i < paragraphs.length; i++)
            ExtractedContentBlock(
              id: 'body-${i + 1}',
              kind: 'paragraph',
              text: paragraphs[i],
            ),
        ],
      ),
      origin: 'pasted',
    );
  }

  void _saveRecoveredArticle(
    LibraryItem item,
    ExtractedArticle article, {
    required String origin,
  }) {
    // Match the existing conservative invalidation used by source/context edits.
    // No await between invalidation, replacement and the durable queue save.
    _invalidateTasks();
    for (final job in runtime.jobs.where((job) => job.entityId == item.id)) {
      if (['capture', 'fetch', 'analysis'].contains(job.type)) {
        job.checkpoint['sourceReplaced'] = true;
      }
    }
    _replaceWebBody(item, article, origin: origin);
    item.error = '';
    item.warning = article.imageUrls.isEmpty ? '' : '正文已保存，图片待下载';
    _enqueue(
      'capture',
      item.id,
      checkpoint: {
        'articleFetched': true,
        'imageUrls': article.imageUrls,
        'savedImages': <String, String>{},
        'contentVersion': item.contentVersion,
        'bodyOrigin': origin,
      },
    );
    _save();
    _scheduleQueue();
  }

  void _replaceWebBody(
    LibraryItem item,
    ExtractedArticle article, {
    required String origin,
  }) {
    final changed =
        item.body != article.body ||
        (item.bodyOrigin.isEmpty ? 'http' : item.bodyOrigin) != origin;
    if (item.body.isNotEmpty && changed) {
      item.contentHistory.add(
        ContentRevision(
          version: item.contentVersion,
          title: item.title,
          body: item.body,
          bodyOrigin: item.bodyOrigin,
          blocks: item.contentBlocks
              .map((block) => ContentBlock.fromJson(block.toJson()))
              .toList(),
        ),
      );
      item.contentVersion++;
      for (final annotation in item.annotations) {
        annotation.anchor.unresolved = true;
      }
      item.readingPosition = null;
    }
    if (changed) {
      if (item.analysis != null) item.analysis!.stale = true;
      for (final dependent in data.items) {
        if (dependent.analysis?.inputItemIds?.contains(item.id) == true) {
          dependent.analysis!.stale = true;
        }
      }
      for (final run in data.runs) {
        if (run.inputItemIds?.contains(item.id) == true) run.stale = true;
      }
      for (final topic in data.topics) {
        if (topic.inputItemIds?.contains(item.id) == true ||
            topic.sourceIds.contains(item.id) ||
            topic.selectedSourceIds?.contains(item.id) == true) {
          topic.overviewStale = true;
        }
      }
    }
    item.title = article.title;
    item.body = article.body;
    item.bodyOrigin = origin;
    item.contentBlocks = article.contentBlocks
        .map(
          (block) => ContentBlock(
            id: block.id,
            kind: enumValue(
              ContentBlockKind.values,
              block.kind,
              ContentBlockKind.paragraph,
            ),
            text: block.text,
            level: block.level ?? 0,
            items: block.kind == 'list' ? block.text.split('\n') : [],
            rows: block.kind == 'table'
                ? block.text.split('\n').map((row) => row.split('\t')).toList()
                : [],
            assetId: block.imageUrl,
            alt: block.text,
          ),
        )
        .toList();
    item.status = 'saved';
  }
}
