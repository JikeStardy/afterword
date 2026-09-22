import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:readlater/services/content_service.dart';

void main() {
  group('article extraction', () {
    test('extracts a readable blog article and normalizes image urls', () {
      final article = ContentService.extractHtml('''
        <html>
          <head><title>Ignored shell title</title></head>
          <body>
            <nav>navigation should disappear</nav>
            <article>
              <h1>Practical Knowledge Work</h1>
              <p>First useful paragraph.</p>
              <ul>
                <li>Keep evidence close.</li>
                <li>Review claims later.</li>
              </ul>
              <img src="/assets/cover.jpg">
            </article>
            <script>throw 'noise';</script>
          </body>
        </html>
      ''', 'https://example.com/posts/readlater');

      expect(article.title, 'Practical Knowledge Work');
      expect(article.url, 'https://example.com/posts/readlater');
      expect(article.body, contains('First useful paragraph.'));
      expect(article.body, contains('Keep evidence close.'));
      expect(article.body, isNot(contains('navigation should disappear')));
      expect(article.body, isNot(contains('throw')));
      expect(article.imageUrls, <String>[
        'https://example.com/assets/cover.jpg',
      ]);
    });

    test('prefers WeChat js_content and lazy image data-src', () {
      final article = ContentService.extractHtml('''
        <html>
          <body>
            <main><p>Outer duplicated frame.</p></main>
            <div id="js_content">
              <h1>微信公众号文章</h1>
              <p>这是一段可离线阅读的正文。</p>
              <img data-src="//mmbiz.qpic.cn/mmbiz_jpg/image.jpg">
            </div>
          </body>
        </html>
      ''', 'https://mp.weixin.qq.com/s/example');

      expect(article.title, '微信公众号文章');
      expect(article.body, contains('这是一段可离线阅读的正文。'));
      expect(article.body, isNot(contains('Outer duplicated frame')));
      expect(article.imageUrls, <String>[
        'https://mmbiz.qpic.cn/mmbiz_jpg/image.jpg',
      ]);
    });

    test('rejects empty or gated pages with a clear extraction error', () {
      expect(
        () => ContentService.extractHtml(
          '<html><body><p>请登录后继续访问</p></body></html>',
          'https://example.com/private',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('正文'),
          ),
        ),
      );
    });
    test(
      'WeChat verification page without article body is not saved as original',
      () {
        expect(
          () => ContentService.extractHtml('''
        <html><body><h2>环境异常</h2><p>当前环境异常，完成验证后即可继续访问。</p><button>去验证</button></body></html>
      ''', 'https://mp.weixin.qq.com/s/public-article'),
          throwsFormatException,
        );
      },
    );

    test('keeps normal articles that discuss login or captcha topics', () {
      final article = ContentService.extractHtml('''
        <article>
          <h1>账户教程</h1>
          <p>登录后可以同步笔记，接下来介绍如何组织知识。</p>
          <p>如果遇到验证码，也可以先保存本地草稿，再稍后处理。</p>
        </article>
      ''', 'https://example.com/account-guide');

      expect(article.title, '账户教程');
      expect(article.body, contains('接下来介绍如何组织知识'));
      expect(article.body, contains('验证码'));
    });
  });

  group('feed parsing', () {
    test('parses RSS items with namespaces and strips summary HTML', () {
      final feed = ContentService.parseFeed('''
        <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
          <channel>
            <title>Research Feed</title>
            <item>
              <title>First item</title>
              <guid>item-1</guid>
              <link>https://example.com/first</link>
              <description><![CDATA[<p>Summary <b>one</b>.</p>]]></description>
            </item>
            <item>
              <title>Missing link is skipped</title>
              <guid>item-2</guid>
            </item>
            <item>
              <title>Namespaced content</title>
              <link>https://example.com/second</link>
              <content:encoded><![CDATA[<div>Long <em>summary</em>.</div>]]></content:encoded>
            </item>
          </channel>
        </rss>
      ''', 'https://example.com/feed.xml');

      expect(feed.title, 'Research Feed');
      expect(feed.entries, hasLength(2));
      expect(feed.entries.first.feedId, '');
      expect(feed.entries.first.id, isNotEmpty);
      expect(feed.entries.first.summary, 'Summary one.');
      expect(feed.entries.last.summary, 'Long summary.');
    });

    test('parses Atom relative links and stable ids', () {
      final feed = ContentService.parseFeed('''
        <feed xmlns="http://www.w3.org/2005/Atom" xml:base="https://example.com/base/">
          <title>Atom Research</title>
          <entry>
            <id>tag:example.com,2026:entry</id>
            <title>Atom item</title>
            <link href="../atom-entry"/>
            <summary type="html"><![CDATA[<p>Atom <b>summary</b>.</p>]]></summary>
          </entry>
        </feed>
      ''', 'https://example.com/feeds/atom.xml');

      expect(feed.title, 'Atom Research');
      expect(feed.entries.single.url, 'https://example.com/atom-entry');
      expect(feed.entries.single.summary, 'Atom summary.');
      expect(feed.entries.single.id, isNotEmpty);
      expect(feed.entries.single.feedId, '');
    });
  });

  group('network boundaries', () {
    test('redirect loops stop after the allowed number of hops', () async {
      var requests = 0;
      final service = ContentService(
        client: MockClient((request) async {
          requests++;
          return http.Response('', 302, headers: {'location': '/loop'});
        }),
      );
      addTearDown(service.close);

      await expectLater(
        service.fetchArticle('https://example.com/loop'),
        throwsA(isA<http.ClientException>()),
      );
      expect(requests, 6);
    });

    test('redirects cannot change to unsupported URL schemes', () async {
      var requests = 0;
      final service = ContentService(
        client: MockClient((request) async {
          requests++;
          return http.Response(
            '',
            302,
            headers: {'location': 'file:///private/article'},
          );
        }),
      );
      addTearDown(service.close);

      await expectLater(
        service.fetchArticle('https://example.com/redirect'),
        throwsArgumentError,
      );
      expect(requests, 1);
    });

    test(
      'redirected articles resolve images against the final page URL',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final base = 'http://127.0.0.1:${server.port}';
        final service = ContentService();
        addTearDown(() async {
          service.close();
          await server.close(force: true);
        });
        server.listen((request) async {
          if (request.uri.path == '/short') {
            request.response.statusCode = 302;
            request.response.headers.set('location', '/posts/step');
          } else if (request.uri.path == '/posts/step') {
            request.response.statusCode = 307;
            request.response.headers.set('location', 'article');
          } else {
            request.response.write(
              '<article><h1>Redirected article</h1>'
              '<p>Preserve the original evidence.</p>'
              '<img src="images/cover.png"></article>',
            );
          }
          await request.response.close();
        });

        final article = await service.fetchArticle('$base/short');
        expect(article.imageUrls, ['$base/posts/images/cover.png']);
        expect(article.url, '$base/posts/article');
      },
    );

    test(
      'redirected feeds resolve entries against the final feed URL',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final base = 'http://127.0.0.1:${server.port}';
        final service = ContentService();
        addTearDown(() async {
          service.close();
          await server.close(force: true);
        });
        server.listen((request) async {
          if (request.uri.path == '/feed') {
            request.response.statusCode = 301;
            request.response.headers.set('location', '$base/news/feed.xml');
          } else {
            request.response.write(
              '<rss><channel><title>News</title><item>'
              '<title>Article</title><guid>article-1</guid><link>article</link>'
              '</item></channel></rss>',
            );
          }
          await request.response.close();
        });

        final feed = await service.fetchFeed('$base/feed');
        expect(feed.entries.single.url, '$base/news/article');
        final originalIdentity = ContentService.parseFeed(
          '<rss><channel><title>News</title><item>'
              '<title>Article</title><guid>article-1</guid><link>article</link>'
              '</item></channel></rss>',
          '$base/feed',
        ).entries.single.id;
        expect(feed.entries.single.id, originalIdentity);
      },
    );

    test('fetchArticle checks status and body size', () async {
      final tooLarge = 'x' * (ContentService.maxArticleBytes + 1);
      final service = ContentService(
        client: MockClient((request) async {
          if (request.url.path == '/missing') {
            return http.Response('nope', 404);
          }
          return http.Response(tooLarge, 200);
        }),
      );

      await expectLater(
        service.fetchArticle('https://example.com/missing'),
        throwsA(isA<http.ClientException>()),
      );
      await expectLater(
        service.fetchArticle('https://example.com/large'),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'downloadImage accepts http images and enforces size limits',
      () async {
        final bytes = List<int>.filled(ContentService.maxImageBytes + 1, 1);
        final service = ContentService(
          client: MockClient((request) async {
            if (request.url.path == '/small.png') {
              return http.Response.bytes(<int>[1, 2, 3], 200);
            }
            return http.Response.bytes(bytes, 200);
          }),
        );

        expect(
          await service.downloadImage('https://example.com/small.png'),
          <int>[1, 2, 3],
        );
        await expectLater(
          service.downloadImage('https://example.com/large.png'),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test('rejects unsupported URL schemes before network access', () async {
      final service = ContentService(
        client: MockClient((request) async {
          fail('unsupported schemes should not reach the client');
        }),
      );

      await expectLater(
        service.fetchArticle('file:///private/doc.html'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
