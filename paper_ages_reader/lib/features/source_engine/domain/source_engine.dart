// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:async';

import 'package:html/parser.dart' show parse;
import 'package:http/http.dart' as http;

import 'rule_safety_policy.dart';

sealed class SourceEngineFailure implements Exception {
  const SourceEngineFailure(this.message);
  final String message;
}

class UnsupportedRuleFailure extends SourceEngineFailure {
  const UnsupportedRuleFailure(super.message);
}

class NetworkTimeoutFailure extends SourceEngineFailure {
  const NetworkTimeoutFailure(super.message);
}

class ParseFailure extends SourceEngineFailure {
  const ParseFailure(super.message);
}

class CancelledFailure extends SourceEngineFailure {
  const CancelledFailure() : super('Request was cancelled');
}

class SourceCancellationToken {
  bool _cancelled = false;
  void cancel() => _cancelled = true;
  void throwIfCancelled() {
    if (_cancelled) throw const CancelledFailure();
  }
}

class SourceEngineLimits {
  const SourceEngineLimits({
    this.timeout = const Duration(seconds: 15),
    this.maxResponseBytes = 2 * 1024 * 1024,
    this.maxPages = 100,
  });
  final Duration timeout;
  final int maxResponseBytes;
  final int maxPages;
}

class NetworkBook {
  const NetworkBook({
    required this.sourceUrl,
    required this.title,
    required this.locator,
    this.author,
    this.coverUrl,
    this.intro,
    this.lastChapter,
  });
  final String sourceUrl;
  final String title;
  final Uri locator;
  final String? author;
  final String? coverUrl;
  final String? intro;
  final String? lastChapter;
}

class SourceChapter {
  const SourceChapter({
    required this.key,
    required this.title,
    required this.locator,
    required this.ordinal,
  });
  final String key;
  final String title;
  final Uri locator;
  final int ordinal;
}

class NetworkBookDetails {
  const NetworkBookDetails({required this.book, required this.tocUrl});
  final NetworkBook book;
  final Uri tocUrl;
}

class StaticSourceEngine {
  StaticSourceEngine({
    http.Client? client,
    this.limits = const SourceEngineLimits(),
  }) : _client = client ?? http.Client();
  final http.Client _client;
  final SourceEngineLimits limits;

  Future<List<NetworkBook>> search({
    required Map<String, Object?> source,
    required String query,
    SourceCancellationToken? cancellationToken,
  }) async {
    _ensureSafe(source);
    if (query.trim().isEmpty) throw const ParseFailure('Search query is empty');
    final template = source['searchUrl'];
    final rules = source['ruleSearch'];
    if (template is! String || rules is! Map)
      throw const UnsupportedRuleFailure(
        'Static searchUrl and ruleSearch are required',
      );
    final document = await _getHtml(
      _resolve(
        _sourceUri(source),
        template.replaceAll('{{key}}', Uri.encodeQueryComponent(query)),
      ),
      cancellationToken,
    );
    final listSelector = _rule(rules, 'bookList');
    if (listSelector == null)
      throw const UnsupportedRuleFailure('ruleSearch.bookList is required');
    final items = _select(document, listSelector);
    return List<NetworkBook>.from(
      items
          .map(
            (item) => NetworkBook(
              sourceUrl: _sourceUri(source).toString(),
              title: _value(item, _rule(rules, 'name')) ?? '',
              locator: _resolve(
                _sourceUri(source),
                _value(item, _rule(rules, 'bookUrl')) ?? '',
              ),
              author: _value(item, _rule(rules, 'author')),
              coverUrl: _urlOrNull(
                _sourceUri(source),
                _value(item, _rule(rules, 'coverUrl')),
              ),
              intro: _value(item, _rule(rules, 'intro')),
              lastChapter: _value(item, _rule(rules, 'lastChapter')),
            ),
          )
          .where((book) => book.title.isNotEmpty && book.locator.hasScheme)
          .toList(growable: false),
    );
  }

  Future<List<SourceChapter>> chapters({
    required Map<String, Object?> source,
    required Uri tocUrl,
    SourceCancellationToken? cancellationToken,
  }) async {
    _ensureSafe(source);
    final rules = source['ruleToc'];
    if (rules is! Map)
      throw const UnsupportedRuleFailure('ruleToc is required');
    final selector = _rule(rules, 'chapterList');
    if (selector == null)
      throw const UnsupportedRuleFailure('ruleToc.chapterList is required');
    final chapters = <SourceChapter>[];
    final seenPages = <String>{};
    final seenChapterUrls = <String>{};
    var page = tocUrl;
    for (var pageIndex = 0; pageIndex < limits.maxPages; pageIndex++) {
      cancellationToken?.throwIfCancelled();
      if (!seenPages.add(page.toString())) break;
      final document = await _getHtml(page, cancellationToken);
      for (final entry in _select(document, selector).asMap().entries) {
        final title = _value(entry.value, _rule(rules, 'chapterName')) ?? '';
        final url = _value(entry.value, _rule(rules, 'chapterUrl')) ?? '';
        final locator = _resolve(page, url);
        if (title.isEmpty ||
            !locator.hasScheme ||
            !seenChapterUrls.add(locator.toString())) {
          continue;
        }
        chapters.add(
          SourceChapter(
            key: '${chapters.length}:${locator.toString().hashCode}',
            title: title,
            locator: locator,
            ordinal: chapters.length,
          ),
        );
      }
      final next = _value(document, _rule(rules, 'nextTocUrl'));
      if (next == null || next.isEmpty) break;
      page = _resolve(page, next);
    }
    return List.unmodifiable(chapters);
  }

  Future<NetworkBookDetails> details({
    required Map<String, Object?> source,
    required NetworkBook book,
    SourceCancellationToken? cancellationToken,
  }) async {
    _ensureSafe(source);
    final rules = source['ruleBookInfo'];
    if (rules is! Map)
      throw const UnsupportedRuleFailure('ruleBookInfo is required');
    final document = await _getHtml(book.locator, cancellationToken);
    final toc = _value(document, _rule(rules, 'tocUrl'));
    if (toc == null || toc.isEmpty)
      throw const ParseFailure('Book information has no catalogue URL');
    return NetworkBookDetails(
      book: NetworkBook(
        sourceUrl: book.sourceUrl,
        title: _value(document, _rule(rules, 'name')) ?? book.title,
        locator: book.locator,
        author: _value(document, _rule(rules, 'author')) ?? book.author,
        coverUrl:
            _urlOrNull(
              book.locator,
              _value(document, _rule(rules, 'coverUrl')),
            ) ??
            book.coverUrl,
        intro: _value(document, _rule(rules, 'intro')) ?? book.intro,
        lastChapter:
            _value(document, _rule(rules, 'lastChapter')) ?? book.lastChapter,
      ),
      tocUrl: _resolve(book.locator, toc),
    );
  }

  Future<String> content({
    required Map<String, Object?> source,
    required Uri chapterUrl,
    SourceCancellationToken? cancellationToken,
  }) async {
    _ensureSafe(source);
    final rules = source['ruleContent'];
    if (rules is! Map)
      throw const UnsupportedRuleFailure('ruleContent is required');
    final pages = <String>[];
    final seenPages = <String>{};
    var page = chapterUrl;
    for (var pageIndex = 0; pageIndex < limits.maxPages; pageIndex++) {
      cancellationToken?.throwIfCancelled();
      if (!seenPages.add(page.toString())) break;
      final document = await _getHtml(page, cancellationToken);
      final result = _value(document, _rule(rules, 'content'));
      if (result == null || result.trim().isEmpty) {
        if (pages.isEmpty)
          throw const ParseFailure('Content rule returned no text');
        break;
      }
      pages.add(result.replaceAll('\r\n', '\n').replaceAll('\r', '\n'));
      final next = _value(document, _rule(rules, 'nextContentUrl'));
      if (next == null || next.isEmpty) break;
      page = _resolve(page, next);
    }
    return pages.join('\n\n');
  }

  void _ensureSafe(Map<String, Object?> source) {
    final report = const RuleSafetyPolicy().inspect(source);
    if (!report.isSafe)
      throw UnsupportedRuleFailure(
        'Source contains forbidden dynamic rule: ${report.issues.first.path}',
      );
  }

  Future<dynamic> _getHtml(Uri url, SourceCancellationToken? token) async {
    token?.throwIfCancelled();
    try {
      final response = await _client.get(url).timeout(limits.timeout);
      token?.throwIfCancelled();
      if (response.statusCode < 200 || response.statusCode >= 300)
        throw ParseFailure('HTTP ${response.statusCode}');
      if (response.bodyBytes.length > limits.maxResponseBytes)
        throw const ParseFailure('Response exceeds size limit');
      return parse(response.body);
    } on TimeoutException {
      throw const NetworkTimeoutFailure('Request timed out');
    }
  }

  String? _rule(Map rules, String key) =>
      rules[key] is String ? rules[key] as String : null;
  dynamic _select(dynamic document, String rule) =>
      document.querySelectorAll(_selector(rule));
  String _selector(String rule) =>
      rule.split('||').first.split('@').first.trim();
  String? _value(dynamic element, String? rule) {
    if (rule == null) return null;
    final selected = rule.contains('@')
        ? element.querySelector(_selector(rule)) ?? element
        : element;
    final suffix = rule.contains('@')
        ? rule.substring(rule.indexOf('@') + 1)
        : 'text';
    if (suffix == 'text' || suffix == 'textNodes') return selected.text.trim();
    if (suffix.startsWith('[') && suffix.endsWith(']'))
      return selected.attributes[suffix.substring(1, suffix.length - 1)]
          ?.trim();
    if (suffix.startsWith('@'))
      return selected.attributes[suffix.substring(1)]?.trim();
    return selected.attributes[suffix]?.trim();
  }

  Uri _sourceUri(Map<String, Object?> source) =>
      Uri.parse(source['bookSourceUrl']! as String);
  Uri _resolve(Uri base, String raw) => base.resolve(raw.trim());
  String? _urlOrNull(Uri base, String? raw) =>
      raw == null || raw.isEmpty ? null : _resolve(base, raw).toString();
  void close() => _client.close();
}
