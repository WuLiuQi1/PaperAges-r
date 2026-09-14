// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:paper_ages_reader/features/source_engine/domain/source_engine.dart';

void main() {
  final staticSource = <String, Object?>{
    'bookSourceUrl': 'https://reader.example/',
    'searchUrl': '/search?q={{key}}',
    'ruleSearch': {
      'bookList': '.book',
      'name': 'a.title@text',
      'bookUrl': 'a.title@href',
      'author': '.author@text',
    },
    'ruleToc': {
      'chapterList': '#toc a',
      'chapterName': 'text',
      'chapterUrl': 'href',
    },
    'ruleBookInfo': {'name': 'h1@text', 'tocUrl': 'a.toc@href'},
    'ruleContent': {'content': '#content@textNodes'},
  };

  test(
    'runs only static selectors through search, chapter and content flow',
    () async {
      final engine = StaticSourceEngine(
        client: MockClient((request) async {
          if (request.url.path == '/search')
            return http.Response.bytes(
              utf8.encode(
                '<div class="book"><a class="title" href="/book/1">春秋</a><span class="author">作者</span></div>',
              ),
              200,
              headers: const {'content-type': 'text/html; charset=utf-8'},
            );
          if (request.url.path == '/book/1')
            return http.Response.bytes(
              utf8.encode('<h1>春秋（详情）</h1><a class="toc" href="/toc">目录</a>'),
              200,
              headers: const {'content-type': 'text/html; charset=utf-8'},
            );
          if (request.url.path == '/toc')
            return http.Response.bytes(
              utf8.encode('<div id="toc"><a href="/chapter/1">第一章</a></div>'),
              200,
              headers: const {'content-type': 'text/html; charset=utf-8'},
            );
          return http.Response.bytes(
            utf8.encode('<article id="content">正文\n第二段</article>'),
            200,
            headers: const {'content-type': 'text/html; charset=utf-8'},
          );
        }),
      );
      final books = await engine.search(source: staticSource, query: '春秋');
      expect(books.single.title, '春秋');
      expect(books.single.locator.toString(), 'https://reader.example/book/1');
      final details = await engine.details(
        source: staticSource,
        book: books.single,
      );
      expect(details.book.title, '春秋（详情）');
      final chapters = await engine.chapters(
        source: staticSource,
        tocUrl: details.tocUrl,
      );
      expect(chapters.single.title, '第一章');
      expect(
        await engine.content(
          source: staticSource,
          chapterUrl: chapters.single.locator,
        ),
        contains('第二段'),
      );
    },
  );

  test('substitutes the requested search page', () async {
    Uri? requested;
    final engine = StaticSourceEngine(
      client: MockClient((request) async {
        requested = request.url;
        return http.Response.bytes(
          utf8.encode(
            '<div class="book"><a class="title" href="/book/2">第二页</a></div>',
          ),
          200,
          headers: const {'content-type': 'text/html; charset=utf-8'},
        );
      }),
    );
    final source = Map<String, Object?>.from(staticSource)
      ..['searchUrl'] = '/search?q={{key}}&page={{page}}';
    final books = await engine.search(source: source, query: '书', page: 2);
    expect(requested!.queryParameters['page'], '2');
    expect(books.single.title, '第二页');
    engine.close();
  });

  test('rejects missing mandatory rules before any HTTP request', () async {
    var calls = 0;
    final engine = StaticSourceEngine(
      client: MockClient((_) async {
        calls++;
        return http.Response('', 200);
      }),
    );
    final unsafe = Map<String, Object?>.from(staticSource)
      ..['ruleSearch'] = {'bookList': '@js: anything'};
    await expectLater(
      engine.search(source: unsafe, query: 'x'),
      throwsA(isA<UnsupportedRuleFailure>()),
    );
    expect(calls, 0);
  });

  test(
    'rejects unsupported rule composition before issuing HTTP request',
    () async {
      var calls = 0;
      final engine = StaticSourceEngine(
        client: MockClient((_) async {
          calls++;
          return http.Response('', 200);
        }),
      );
      final unsupported = Map<String, Object?>.from(staticSource)
        ..['ruleSearch'] = {
          'bookList': '.book&&.legacy',
          'name': 'a@text',
          'bookUrl': 'a@href',
        };
      await expectLater(
        engine.search(source: unsupported, query: 'x'),
        throwsA(isA<UnsupportedRuleFailure>()),
      );
      expect(calls, 0);
    },
  );

  test('honors cancellation before any request', () async {
    final token = SourceCancellationToken()..cancel();
    final engine = StaticSourceEngine(
      client: MockClient((_) async => http.Response('', 200)),
    );
    await expectLater(
      engine.search(source: staticSource, query: 'x', cancellationToken: token),
      throwsA(isA<CancelledFailure>()),
    );
  });

  test(
    'treats script markup and event attributes as inert HTML data',
    () async {
      final engine = StaticSourceEngine(
        client: MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(
              '<script>window.__must_not_run = true</script><div class="book" onclick="steal()"><a class="title" href="/book/1">安全正文</a><span class="author">作者</span></div>',
            ),
            200,
            headers: const {'content-type': 'text/html; charset=utf-8'},
          ),
        ),
      );
      final books = await engine.search(source: staticSource, query: '安全');
      expect(books.single.title, '安全正文');
      expect(books.single.locator.toString(), 'https://reader.example/book/1');
    },
  );

  test(
    'reports malformed declared UTF-8 instead of silently corrupting text',
    () async {
      final engine = StaticSourceEngine(
        client: MockClient(
          (_) async => http.Response.bytes(
            [0xff],
            200,
            headers: const {'content-type': 'text/html; charset=utf-8'},
          ),
        ),
      );
      await expectLater(
        engine.search(source: staticSource, query: 'x'),
        throwsA(isA<ParseFailure>()),
      );
    },
  );

  test('deduplicates paged chapters and stops a pagination loop', () async {
    var calls = 0;
    final source = Map<String, Object?>.from(staticSource)
      ..['ruleToc'] = {
        'chapterList': '#toc a.chapter',
        'chapterName': 'text',
        'chapterUrl': 'href',
        'nextTocUrl': 'a.next@href',
      };
    final engine = StaticSourceEngine(
      limits: const SourceEngineLimits(maxPages: 10),
      client: MockClient((request) async {
        calls++;
        if (request.url.path == '/toc') {
          return http.Response.bytes(
            utf8.encode(
              '<div id="toc"><a class="chapter" href="/chapter/1">一</a></div><a class="next" href="/toc-2">next</a>',
            ),
            200,
            headers: const {'content-type': 'text/html; charset=utf-8'},
          );
        }
        return http.Response.bytes(
          utf8.encode(
            '<div id="toc"><a class="chapter" href="/chapter/1">一</a><a class="chapter" href="/chapter/2">二</a></div><a class="next" href="/toc">loop</a>',
          ),
          200,
          headers: const {'content-type': 'text/html; charset=utf-8'},
        );
      }),
    );
    final chapters = await engine.chapters(
      source: source,
      tocUrl: Uri.parse('https://reader.example/toc'),
    );
    expect(chapters.map((chapter) => chapter.title), ['一', '二']);
    expect(calls, 2);
  });
}
