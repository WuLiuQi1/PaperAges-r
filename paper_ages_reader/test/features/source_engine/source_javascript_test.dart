import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:paper_ages_reader/features/source_engine/domain/source_engine.dart';
import 'package:paper_ages_reader/features/source_engine/domain/source_javascript.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'supplied source rule shapes: fallback, index, regex, JS and chapter href',
    () async {
      final engine = StaticSourceEngine(
        client: MockClient(
          (request) async => http.Response(
            '<div class="bookbox"><div class="bookname"><a href="/book/1234.html">Novel</a></div><span class="author">Writer</span></div>',
            200,
          ),
        ),
      );
      addTearDown(engine.close);
      final books = await engine.search(
        source: {
          'bookSourceUrl': 'https://example.test',
          'searchUrl': '/?q={{key}}',
          'ruleSearch': {
            'bookList': '.bookbox||body:has(h1)',
            'name': '.bookname a@text||h1@text',
            'author': '.author.0@text||meta@content',
            'bookUrl': '.bookname a@href||meta@content',
            'coverUrl': r"""##book/(\d+)\.html##$1###@js:result?'https://example.test/'+Math.floor(result/1000)+'/'+result+'.jpg':''""",
          },
        },
        query: 'Novel',
      );
      expect(books.single.author, 'Writer');
      expect(books.single.coverUrl, 'https://example.test/1/1234.jpg');
      expect(books.single.locator.path, '/book/1234.html');
    },
    skip: !const bool.fromEnvironment('NATIVE_JS_TEST')
        ? 'Native runtime integration opt-in'
        : false,
  );
  test(
    'native JS evaluates result transformations and the selector bridge',
    () {
      expect(
        evaluateSourceScript(
          'result.replace(/old/g, "new")',
          'old old',
          {},
          (_) => null,
        ),
        'new new',
      );
      expect(
        evaluateSourceScript('java.getString("h1@text")', '', {}, (_) => '正文'),
        '正文',
      );
      expect(
        () => evaluateSourceScript(
          'throw new Error("broken")',
          '',
          {},
          (_) => null,
        ),
        throwsFormatException,
      );
    },
    skip: !const bool.fromEnvironment('NATIVE_JS_TEST')
        ? 'Requires bundled QuickJS DLL on PATH; iOS must be tested on device.'
        : false,
  );

  test(
    'native JS postprocessor is wired into content extraction',
    () async {
      final engine = StaticSourceEngine(
        client: MockClient((_) async => http.Response('<p>old body</p>', 200)),
      );
      addTearDown(engine.close);
      expect(
        await engine.content(
          source: {
            'bookSourceUrl': 'https://example.test',
            'ruleContent': {
              'content': 'p@text@js:result.replace("old", "new")',
            },
          },
          chapterUrl: Uri.parse('https://example.test/chapter'),
        ),
        'new body',
      );
    },
    skip: !const bool.fromEnvironment('NATIVE_JS_TEST')
        ? 'Native runtime integration opt-in'
        : false,
  );
}
