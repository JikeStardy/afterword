import 'dart:async';
import 'dart:convert';
import 'dart:io' show HandshakeException, HttpDate, OSError, SocketException;
import 'dart:typed_data';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:readlater/core/diagnostics.dart';
import 'package:readlater/core/models.dart';
import 'package:xml/xml.dart' as xml;

class ExtractedArticle {
  final String title, body, url;
  final List<String> imageUrls;
  final int contentVersion;
  final List<ExtractedContentBlock> contentBlocks;

  const ExtractedArticle({
    required this.title,
    required this.body,
    required this.url,
    required this.imageUrls,
    this.contentVersion = 1,
    this.contentBlocks = const <ExtractedContentBlock>[],
  });
}

class ExtractedContentBlock {
  final String id, kind, text;
  final int? level, page;
  final String sourceContext, imageUrl, assetPath;

  const ExtractedContentBlock({
    required this.id,
    required this.kind,
    required this.text,
    this.level,
    this.page,
    this.sourceContext = '',
    this.imageUrl = '',
    this.assetPath = '',
  });

  Json toJson() => {
    'id': id,
    'kind': kind,
    'text': text,
    if (level != null) 'level': level,
    if (page != null) 'page': page,
    if (sourceContext.isNotEmpty) 'sourceContext': sourceContext,
    if (imageUrl.isNotEmpty) 'imageUrl': imageUrl,
    if (assetPath.isNotEmpty) 'assetPath': assetPath,
  };
}

class ParsedFeed {
  final String title;
  final List<FeedEntry> entries;

  const ParsedFeed({required this.title, required this.entries});
}

class ContentService {
  static const maxArticleBytes = 5 * 1024 * 1024;
  static const maxImageBytes = 10 * 1024 * 1024;

  final http.Client _client;
  final Duration timeout;
  int _requestSequence = 0;

  ContentService({
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  Future<ExtractedArticle> fetchArticle(String url) async {
    final uri = _validatedHttpUri(url);
    final fetched = await _fetchBytes(uri, maxArticleBytes);
    final stopwatch = Stopwatch()..start();
    DiagnosticScope.log(
      DiagnosticLevel.debug,
      'content',
      'parse.start',
      data: {
        'kind': 'article',
        'url': fetched.url,
        'bytes': fetched.bytes.length,
      },
    );
    try {
      final article = extractHtml(
        utf8.decode(fetched.bytes, allowMalformed: true),
        fetched.url.toString(),
      );
      DiagnosticScope.log(
        DiagnosticLevel.info,
        'content',
        'parse.success',
        data: {
          'kind': 'article',
          'url': fetched.url,
          'durationMs': stopwatch.elapsedMilliseconds,
          'blocks': article.contentBlocks.length,
        },
      );
      return article;
    } catch (error, stackTrace) {
      DiagnosticScope.log(
        DiagnosticLevel.error,
        'content',
        'parse.failure',
        data: {
          'kind': 'article',
          'url': fetched.url,
          'durationMs': stopwatch.elapsedMilliseconds,
          'phase': 'parse',
        },
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  static ExtractedArticle extractHtml(String html, String url) {
    final baseUri = _validatedHttpUri(url);
    final document = html_parser.parse(html);
    _removeNoise(document);

    final wechatBody = document.querySelector('#js_content');
    if (baseUri.host == 'mp.weixin.qq.com' && wechatBody == null) {
      throw const FormatException(
        '未获取到微信公众号正文，可能需要验证或文章已不可用；链接已保留，可稍后重试或粘贴原文、导入截图',
      );
    }

    final root =
        wechatBody ??
        document.querySelector('article') ??
        document.querySelector('main') ??
        document.body;
    if (root == null) {
      throw const FormatException('无法提取正文：页面为空或结构不可读');
    }

    final title = _articleTitle(document, root);
    final blocks = _articleBlocks(root, baseUri);
    final body = blocks.isEmpty
        ? _articleText(root)
        : blocks
              .where((block) => block.kind != 'image')
              .map((block) => block.text)
              .where((text) => text.trim().isNotEmpty)
              .join('\n\n');
    if (_isBlockedOrEmpty(body)) {
      throw const FormatException('无法提取正文：页面为空或需要登录/验证');
    }

    return ExtractedArticle(
      title: title.isEmpty ? baseUri.host : title,
      body: body,
      url: baseUri.toString(),
      imageUrls: _imageUrls(root, baseUri),
      contentBlocks: blocks,
    );
  }

  Future<ParsedFeed> fetchFeed(String url) async {
    final uri = _validatedHttpUri(url);
    final fetched = await _fetchBytes(uri, maxArticleBytes);
    final stopwatch = Stopwatch()..start();
    DiagnosticScope.log(
      DiagnosticLevel.debug,
      'content',
      'parse.start',
      data: {
        'kind': 'rss',
        'url': uri,
        'documentUrl': fetched.url,
        'bytes': fetched.bytes.length,
      },
    );
    try {
      final parsed = parseFeed(
        utf8.decode(fetched.bytes, allowMalformed: true),
        uri.toString(),
        documentUrl: fetched.url.toString(),
      );
      DiagnosticScope.log(
        DiagnosticLevel.info,
        'content',
        'parse.success',
        data: {
          'kind': 'rss',
          'url': uri,
          'documentUrl': fetched.url,
          'durationMs': stopwatch.elapsedMilliseconds,
          'entries': parsed.entries.length,
        },
      );
      return parsed;
    } catch (error, stackTrace) {
      DiagnosticScope.log(
        DiagnosticLevel.error,
        'content',
        'parse.failure',
        data: {
          'kind': 'rss',
          'url': uri,
          'documentUrl': fetched.url,
          'durationMs': stopwatch.elapsedMilliseconds,
          'phase': 'parse',
        },
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  static ParsedFeed parseFeed(
    String feedXml,
    String url, {
    String? documentUrl,
  }) {
    final feedUri = _validatedHttpUri(url);
    final documentUri = documentUrl == null
        ? feedUri
        : _validatedHttpUri(documentUrl);
    final document = xml.XmlDocument.parse(feedXml);
    final root = document.rootElement;
    final localName = root.name.local.toLowerCase();
    if (localName == 'feed') {
      return _parseAtom(root, feedUri, documentUri);
    }
    if (localName == 'rss' || localName == 'rdf') {
      return _parseRss(root, feedUri, documentUri);
    }
    throw FormatException('不支持的订阅格式：${root.name.local}');
  }

  Future<Uint8List> downloadImage(String url) async {
    final uri = _validatedHttpUri(url);
    return (await _fetchBytes(uri, maxImageBytes)).bytes;
  }

  void close() => _client.close();

  Future<({Uint8List bytes, Uri url})> _fetchBytes(
    Uri uri,
    int maxBytes,
  ) async {
    var currentUri = uri;
    final requestId =
        'content-${DateTime.now().microsecondsSinceEpoch}-${_requestSequence++}';
    late http.StreamedResponse response;
    // Track every hop: the HTTP client's final URL may be a relative Location.
    for (var redirects = 0; ; redirects++) {
      final request = http.Request('GET', currentUri)..followRedirects = false;
      final stopwatch = Stopwatch()..start();
      DiagnosticScope.log(
        DiagnosticLevel.debug,
        'content',
        'request.start',
        data: {
          'url': currentUri,
          'requestId': requestId,
          'host': currentUri.host,
          'port': currentUri.hasPort ? currentUri.port : null,
          'phase': 'request',
          'redirect': redirects,
        },
      );
      try {
        response = await _client.send(request).timeout(timeout);
      } catch (error, stackTrace) {
        DiagnosticScope.log(
          DiagnosticLevel.error,
          'content',
          'request.failure',
          data: {
            'url': currentUri,
            'requestId': requestId,
            'host': currentUri.host,
            'port': currentUri.hasPort ? currentUri.port : null,
            'phase': _requestFailurePhase(error),
            'durationMs': stopwatch.elapsedMilliseconds,
            'statusCode': null,
            ..._networkErrorData(error),
          },
          error: error,
          stackTrace: stackTrace,
        );
        rethrow;
      }
      DiagnosticScope.log(
        DiagnosticLevel.info,
        'content',
        'response.headers',
        data: {
          'url': currentUri,
          'requestId': requestId,
          'host': currentUri.host,
          'port': currentUri.hasPort ? currentUri.port : null,
          'phase': 'headers',
          'durationMs': stopwatch.elapsedMilliseconds,
          'statusCode': response.statusCode,
          'contentLength': response.contentLength,
          'headerCount': response.headers.length,
        },
      );
      if (![301, 302, 303, 307, 308].contains(response.statusCode)) break;
      await response.stream.listen(null).cancel();
      final location = response.headers['location'];
      if (redirects >= 5 || location == null || location.trim().isEmpty) {
        DiagnosticScope.log(
          DiagnosticLevel.error,
          'content',
          'redirect.failure',
          data: {
            'url': currentUri,
            'requestId': requestId,
            'phase': 'redirect',
            'statusCode': response.statusCode,
            'redirect': redirects,
          },
        );
        throw http.ClientException('网页跳转过多或缺少目标地址', currentUri);
      }
      final nextUri = _validatedHttpUri(
        currentUri.resolve(location.trim()).toString(),
      );
      DiagnosticScope.log(
        DiagnosticLevel.info,
        'content',
        'redirect.follow',
        data: {
          'url': currentUri,
          'requestId': requestId,
          'location': nextUri,
          'phase': 'redirect',
          'statusCode': response.statusCode,
          'redirect': redirects,
        },
      );
      currentUri = nextUri;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      DiagnosticScope.log(
        DiagnosticLevel.error,
        'content',
        'request.failure',
        data: {
          'url': currentUri,
          'requestId': requestId,
          'phase': 'status',
          'statusCode': response.statusCode,
        },
      );
      throw http.ClientException('请求失败：HTTP ${response.statusCode}', uri);
    }
    final contentLength = response.contentLength;
    if (contentLength != null && contentLength > maxBytes) {
      DiagnosticScope.log(
        DiagnosticLevel.error,
        'content',
        'body.failure',
        data: {
          'url': currentUri,
          'requestId': requestId,
          'phase': 'body',
          'statusCode': response.statusCode,
          'bytes': contentLength,
          'limitBytes': maxBytes,
        },
      );
      throw FormatException('响应过大：超过 ${maxBytes ~/ (1024 * 1024)}MB 上限');
    }

    final builder = BytesBuilder(copy: false);
    var total = 0;
    final bodyStopwatch = Stopwatch()..start();
    try {
      await for (final chunk in response.stream.timeout(timeout)) {
        total += chunk.length;
        if (total > maxBytes) {
          DiagnosticScope.log(
            DiagnosticLevel.error,
            'content',
            'body.failure',
            data: {
              'url': currentUri,
              'requestId': requestId,
              'phase': 'body',
              'statusCode': response.statusCode,
              'bytes': total,
              'limitBytes': maxBytes,
            },
          );
          throw FormatException('响应过大：超过 ${maxBytes ~/ (1024 * 1024)}MB 上限');
        }
        builder.add(chunk);
      }
      DiagnosticScope.log(
        DiagnosticLevel.info,
        'content',
        'body.success',
        data: {
          'url': currentUri,
          'requestId': requestId,
          'phase': 'body',
          'statusCode': response.statusCode,
          'bytes': total,
          'durationMs': bodyStopwatch.elapsedMilliseconds,
        },
      );
    } catch (error, stackTrace) {
      DiagnosticScope.log(
        DiagnosticLevel.error,
        'content',
        'body.failure',
        data: {
          'url': currentUri,
          'requestId': requestId,
          'phase': 'body',
          'statusCode': response.statusCode,
          'bytes': total,
          'durationMs': bodyStopwatch.elapsedMilliseconds,
          ..._networkErrorData(error),
        },
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
    return (bytes: builder.takeBytes(), url: currentUri);
  }

  static String _requestFailurePhase(Object error) {
    if (error is HandshakeException ||
        error.runtimeType.toString().contains('Handshake')) {
      return 'tls';
    }
    if (error is SocketException) return 'connect';
    if (error is TimeoutException) return 'timeout';
    return 'request';
  }

  static Map<String, Object?> _networkErrorData(Object error) {
    OSError? osError;
    if (error is SocketException) osError = error.osError;
    return {
      'errorType': error.runtimeType.toString(),
      if (osError != null) 'osErrorCode': osError.errorCode,
      if (osError != null) 'osErrorMessage': osError.message,
    };
  }

  static Uri _validatedHttpUri(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw ArgumentError.value(url, 'url', 'URL 必须是完整的 http/https 地址');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw ArgumentError.value(url, 'url', '仅支持 http/https 地址');
    }
    return uri;
  }

  static void _removeNoise(dom.Document document) {
    for (final selector in <String>[
      'script',
      'style',
      'noscript',
      'nav',
      'header',
      'footer',
      'aside',
      'iframe',
      'form',
      'button',
      'svg',
      'canvas',
      '[role="navigation"]',
      '.advertisement',
      '.ads',
      '.comment',
      '.comments',
    ]) {
      for (final element in document.querySelectorAll(selector)) {
        element.remove();
      }
    }
  }

  static String _articleTitle(dom.Document document, dom.Element root) {
    final rootTitle = _clean(root.querySelector('h1')?.text ?? '');
    if (rootTitle.isNotEmpty) return rootTitle;

    for (final selector in <String>[
      'meta[property="og:title"]',
      'meta[name="twitter:title"]',
    ]) {
      final content = _clean(
        document.querySelector(selector)?.attributes['content'] ?? '',
      );
      if (content.isNotEmpty) return content;
    }

    return _clean(document.querySelector('title')?.text ?? '');
  }

  static String _articleText(dom.Element root) {
    final lines = <String>[];
    for (final element in root.querySelectorAll(
      'h1,h2,h3,h4,p,li,blockquote,pre',
    )) {
      final text = _clean(element.text);
      if (text.isNotEmpty && (lines.isEmpty || lines.last != text)) {
        lines.add(text);
      }
    }
    if (lines.isEmpty) {
      final fallback = _clean(root.text);
      if (fallback.isNotEmpty) lines.add(fallback);
    }
    return lines.join('\n\n');
  }

  static List<ExtractedContentBlock> _articleBlocks(
    dom.Element root,
    Uri baseUri,
  ) {
    final blocks = <ExtractedContentBlock>[];
    var index = 0;
    final seen = <String>{};
    for (final element in root.querySelectorAll(
      'h1,h2,h3,h4,p,li,blockquote,pre,table,img',
    )) {
      final tag = element.localName?.toLowerCase() ?? '';
      final kind = switch (tag) {
        'h1' || 'h2' || 'h3' || 'h4' => 'heading',
        'li' => 'list',
        'blockquote' => 'quote',
        'pre' => 'code',
        'table' => 'table',
        'img' => 'image',
        _ => 'paragraph',
      };
      final imageUrl = tag == 'img'
          ? _resolveHttpUrl(
              element.attributes['data-src'] ??
                  element.attributes['data-original'] ??
                  element.attributes['src'],
              baseUri,
            )
          : null;
      final text = tag == 'table'
          ? _tableText(element)
          : (tag == 'img'
                ? _clean(
                    element.attributes['alt'] ??
                        element.attributes['title'] ??
                        imageUrl ??
                        '',
                  )
                : _clean(element.text));
      if (text.isEmpty && imageUrl == null) continue;
      final dedupeKey = '$kind|$text|$imageUrl';
      if (!seen.add(dedupeKey)) continue;
      index++;
      blocks.add(
        ExtractedContentBlock(
          id: 'b${_stableId('$index|$dedupeKey').substring(0, 10)}',
          kind: kind,
          text: text.isEmpty ? imageUrl! : text,
          level: kind == 'heading'
              ? int.tryParse(tag.replaceFirst('h', ''))
              : null,
          sourceContext: tag,
          imageUrl: imageUrl ?? '',
        ),
      );
    }
    return blocks;
  }

  static String _tableText(dom.Element table) {
    final rows = <String>[];
    for (final row in table.querySelectorAll('tr')) {
      final cells = row
          .querySelectorAll('th,td')
          .map((cell) => _clean(cell.text))
          .where((text) => text.isNotEmpty)
          .toList();
      if (cells.isNotEmpty) rows.add(cells.join(' | '));
    }
    if (rows.isNotEmpty) return rows.join('\n');
    return _clean(table.text);
  }

  static bool _isBlockedOrEmpty(String body) {
    final compact = body.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    if (compact.length < 10) return true;

    final shortGate = compact.length < 300;
    final sparseGate = compact.length < 1000 && body.split('\n\n').length <= 3;
    if (shortGate &&
        (compact.contains('请登录') ||
            compact.contains('登录后继续') ||
            compact.contains('登录后查看') ||
            compact.contains('登录后阅读'))) {
      return true;
    }
    if ((shortGate || sparseGate) &&
        (compact.contains('安全验证') ||
            compact.contains('访问频繁') ||
            compact.contains('accessdenied') ||
            compact.contains('forbidden'))) {
      return true;
    }
    if ((shortGate || sparseGate) &&
        compact.contains('captcha') &&
        (compact.contains('required') ||
            compact.contains('verify') ||
            compact.contains('challenge'))) {
      return true;
    }
    return false;
  }

  static List<String> _imageUrls(dom.Element root, Uri baseUri) {
    final urls = <String>{};
    for (final image in root.querySelectorAll('img')) {
      final raw =
          image.attributes['data-src'] ??
          image.attributes['data-original'] ??
          image.attributes['src'];
      final resolved = _resolveHttpUrl(raw, baseUri);
      if (resolved != null) urls.add(resolved);
    }
    return urls.toList(growable: false);
  }

  static ParsedFeed _parseRss(
    xml.XmlElement root,
    Uri feedUri,
    Uri documentUri,
  ) {
    final channel = _firstChild(root, 'channel') ?? root;
    final title = _clean(_firstText(channel, 'title'));
    final entries = <FeedEntry>[];
    for (final item in _children(channel, 'item')) {
      final linkText = _firstText(item, 'link');
      final guid = _firstText(item, 'guid');
      final url =
          _resolveHttpUrl(linkText, documentUri) ??
          _resolveHttpUrl(_guidPermalink(item, guid), documentUri);
      if (url == null) continue;

      final summary = _stripHtml(
        _firstText(item, 'description').isNotEmpty
            ? _firstText(item, 'description')
            : _firstText(item, 'encoded'),
      );
      entries.add(
        FeedEntry(
          id: _stableId(
            '${feedUri.toString()}|${guid.isNotEmpty ? guid : url}',
          ),
          feedId: '',
          title: _clean(_firstText(item, 'title')).isEmpty
              ? url
              : _clean(_firstText(item, 'title')),
          url: url,
          summary: summary,
          publishedAt: _parseDate(
            _firstText(item, 'pubDate').isNotEmpty
                ? _firstText(item, 'pubDate')
                : _firstText(item, 'date'),
          ),
        ),
      );
    }
    return ParsedFeed(
      title: title.isEmpty ? feedUri.host : title,
      entries: entries,
    );
  }

  static String _guidPermalink(xml.XmlElement item, String guid) {
    final guidElement = _firstChild(item, 'guid');
    if (guidElement?.getAttribute('isPermaLink') == 'true') return guid;
    return '';
  }

  static ParsedFeed _parseAtom(
    xml.XmlElement root,
    Uri feedUri,
    Uri documentUri,
  ) {
    final baseUri = _xmlBase(root, documentUri);
    final title = _clean(_firstText(root, 'title'));
    final entries = <FeedEntry>[];
    for (final entry in _children(root, 'entry')) {
      final entryBase = _xmlBase(entry, baseUri);
      final link = _atomLink(entry, entryBase);
      if (link == null) continue;
      final id = _firstText(entry, 'id');
      final summary = _stripHtml(
        _firstText(entry, 'summary').isNotEmpty
            ? _firstText(entry, 'summary')
            : _firstText(entry, 'content'),
      );
      entries.add(
        FeedEntry(
          id: _stableId('${feedUri.toString()}|${id.isNotEmpty ? id : link}'),
          feedId: '',
          title: _clean(_firstText(entry, 'title')).isEmpty
              ? link
              : _clean(_firstText(entry, 'title')),
          url: link,
          summary: summary,
          publishedAt: _parseDate(
            _firstText(entry, 'published').isNotEmpty
                ? _firstText(entry, 'published')
                : _firstText(entry, 'updated'),
          ),
        ),
      );
    }
    return ParsedFeed(
      title: title.isEmpty ? feedUri.host : title,
      entries: entries,
    );
  }

  static Uri _xmlBase(xml.XmlElement element, Uri fallback) {
    final value =
        element.getAttribute(
          'base',
          namespaceUri: 'http://www.w3.org/XML/1998/namespace',
        ) ??
        element.getAttribute('xml:base');
    if (value == null || value.trim().isEmpty) return fallback;
    return fallback.resolve(value.trim());
  }

  static String? _atomLink(xml.XmlElement entry, Uri baseUri) {
    xml.XmlElement? firstLink;
    for (final link in _children(entry, 'link')) {
      firstLink ??= link;
      if ((link.getAttribute('rel') ?? 'alternate') == 'alternate') {
        final resolved = _resolveHttpUrl(link.getAttribute('href'), baseUri);
        if (resolved != null) return resolved;
      }
    }
    return _resolveHttpUrl(firstLink?.getAttribute('href'), baseUri);
  }

  static Iterable<xml.XmlElement> _children(
    xml.XmlElement element,
    String localName,
  ) => element.childElements.where((child) => child.name.local == localName);

  static xml.XmlElement? _firstChild(xml.XmlElement element, String localName) {
    for (final child in _children(element, localName)) {
      return child;
    }
    return null;
  }

  static String _firstText(xml.XmlElement element, String localName) {
    final child = _firstChild(element, localName);
    return _clean(child?.innerText ?? '');
  }

  static String _stripHtml(String value) {
    if (value.isEmpty) return '';
    return _clean(html_parser.parseFragment(value).text ?? '');
  }

  static String? _resolveHttpUrl(String? raw, Uri baseUri) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    final resolved = baseUri.resolve(value);
    if (resolved.scheme != 'http' && resolved.scheme != 'https') return null;
    return resolved.toString();
  }

  static DateTime? _parseDate(String value) {
    if (value.isEmpty) return null;
    final isoDate = DateTime.tryParse(value);
    if (isoDate != null) return isoDate;
    try {
      return HttpDate.parse(value);
    } on FormatException {
      return null;
    }
  }

  static String _clean(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _stableId(String seed) {
    var hash = 0xcbf29ce484222325;
    for (final codeUnit in seed.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
