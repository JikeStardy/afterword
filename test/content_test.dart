import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:readlater/services/content_service.dart';

void main() {
  group('article extraction', () {
    test(
      'explicit short article bodies may match their metadata description',
      () {
        for (final container in [
          '<div itemprop="articleBody">',
          '<div id="js_content">',
        ]) {
          final article = ContentService.extractHtml(
            '''
          <html><head><title>今日简讯</title><meta name="description" content="这是一篇完整的简短更新，所有信息都在这一段。"></head>
          <body>$container<p>这是一篇完整的简短更新，所有信息都在这一段。</p></div></body></html>
        ''',
            container.contains('js_content')
                ? 'https://mp.weixin.qq.com/s/short'
                : 'https://example.com/short',
          );
          expect(article.body, '这是一篇完整的简短更新，所有信息都在这一段。');
        }
      },
    );

    test(
      'Tencent article container excludes recommendations and site chrome',
      () {
        final article = ContentService.extractHtml('''
        <html><head><meta property="og:title" content="正文标题"></head><body>
          <div><p>页面顶部广告不属于正文。</p></div>
          <section class="c-mod col-article"><h1 class="col-article-title">正文标题</h1>
            <div><div class="rno-markdown undefined rno-"><p>这是真正的文章第一段。</p><p>这是完整正文的最后一段。</p></div></div>
          </section>
          <div><h2>相关快讯</h2><p>其他文章的推荐摘要。</p></div>
        </body></html>
      ''', 'https://cloud.tencent.com/developer/news/1116925');
        expect(article.body, '这是真正的文章第一段。\n\n这是完整正文的最后一段。');
        expect(article.title, '正文标题');
      },
    );

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
      expect(
        article.contentBlocks.map((block) => block.kind),
        containsAll(['heading', 'paragraph', 'list', 'image']),
      );
      expect(article.contentBlocks.first.toJson(), containsPair('level', 1));
      expect(
        article.contentBlocks.last.toJson(),
        containsPair('imageUrl', 'https://example.com/assets/cover.jpg'),
      );
    });

    test('keeps code and table blocks with stable ids', () {
      final article = ContentService.extractHtml('''
        <article>
          <h1>Structured reading</h1>
          <pre>final answer = evidence;</pre>
          <table>
            <tr><th>Claim</th><th>Evidence</th></tr>
            <tr><td>Local first</td><td>Saved notes</td></tr>
          </table>
        </article>
      ''', 'https://example.com/structured');

      final kinds = article.contentBlocks.map((block) => block.kind).toList();
      expect(kinds, ['heading', 'code', 'table']);
      expect(article.contentBlocks[1].text, 'final answer = evidence;');
      expect(article.contentBlocks[2].text, contains('Claim | Evidence'));
      expect(
        article.contentBlocks.map((block) => block.id).toSet(),
        hasLength(3),
      );
    });

    test('keeps mixed container and inline text in document order', () {
      final article = ContentService.extractHtml('''
        <article>
          <h1>Reading without missing paragraphs</h1>
          <p>A short introduction.</p>
          <div>First <strong>important</strong> paragraph.
            <section>Second <em>useful</em> paragraph.</section>
            Text after the section.
          </div>
          <div>Another line.<br>Next line.</div>
          <p>Before image.<img src="/figure.png">After image.</p>
        </article>
      ''', 'https://example.com/containers');

      expect(article.contentBlocks.map((block) => block.text), [
        'Reading without missing paragraphs',
        'A short introduction.',
        'First important paragraph.',
        'Second useful paragraph.',
        'Text after the section.',
        'Another line. Next line.',
        'Before image.',
        'https://example.com/figure.png',
        'After image.',
      ]);
      expect(article.body, contains('Second useful paragraph.'));
      expect(article.body, contains('Text after the section.'));
    });

    test('preserves repeated content and nested semantic blocks once', () {
      final article = ContentService.extractHtml('''
        <article>
          <blockquote><p>A repeated quotation.</p><p>A repeated quotation.</p></blockquote>
          <ul><li><p>A list item.</p><ul><li>A nested item.</li></ul></li></ul>
          <pre><code>final answer = evidence;</code></pre>
          <table><tr><td><p>Claim</p></td><td>Evidence</td></tr></table>
          <img src="/repeat.png"><img src="/repeat.png">
        </article>
      ''', 'https://example.com/semantic');

      expect(article.contentBlocks.map((block) => block.kind), [
        'quote',
        'quote',
        'list',
        'list',
        'code',
        'table',
        'image',
        'image',
      ]);
      expect(article.contentBlocks.map((block) => block.text), [
        'A repeated quotation.',
        'A repeated quotation.',
        'A list item.',
        'A nested item.',
        'final answer = evidence;',
        'Claim | Evidence',
        'https://example.com/repeat.png',
        'https://example.com/repeat.png',
      ]);
      expect(
        article.contentBlocks.map((block) => block.id).toSet(),
        hasLength(8),
      );
      expect(article.imageUrls, ['https://example.com/repeat.png']);
    });

    test('prefers an explicit article body over a teaser article', () {
      final article = ContentService.extractHtml('''
        <html><head><meta property="og:title" content="The full article"></head>
        <body>
          <article><h1>Related article</h1><p>This is only a teaser.</p></article>
          <main><div itemprop="articleBody"><div>The complete first paragraph.</div>
            <section>The complete final paragraph.</section></div></main>
        </body></html>
      ''', 'https://example.com/explicit-body');

      expect(article.title, 'The full article');
      expect(
        article.body,
        'The complete first paragraph.\n\nThe complete final paragraph.',
      );
      expect(article.body, isNot(contains('teaser')));
    });

    test(
      'rejects a title and metadata description without article content',
      () {
        expect(
          () => ContentService.extractHtml('''
          <html><head><meta name="description" content="A summary of the article, with no actual paragraphs."></head>
          <body><article><h1>A page with only its preview</h1>
            <p>A summary of the article, with no actual paragraphs.</p>
          </article></body></html>
        ''', 'https://example.com/preview'),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('摘要'),
            ),
          ),
        );
      },
    );

    test('keeps a valid short article with content beyond its description', () {
      final article = ContentService.extractHtml('''
        <html><head><meta name="description" content="A short reading note."></head>
        <body><article><h1>A brief note</h1><p>Read slowly. Keep your own notes.</p></article></body></html>
      ''', 'https://example.com/brief');

      expect(article.body, contains('Read slowly. Keep your own notes.'));
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
