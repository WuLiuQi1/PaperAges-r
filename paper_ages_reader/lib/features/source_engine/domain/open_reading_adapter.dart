import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:charset_converter/charset_converter.dart';
import 'package:http/http.dart' as http;

import '../open_reading/book_sources/models/registered_book_source.dart';
import '../open_reading/book_sources/protocol/book_source_protocol.dart';
import '../open_reading/book_sources/services/book_download_cancellation.dart';
import '../open_reading/book_sources/source_engine/source_config.dart';
import '../open_reading/book_sources/source_engine/source_http_transport.dart';
import '../open_reading/book_sources/source_engine/source_request_template.dart';
import '../open_reading/book_sources/source_engine/source_response.dart';
import '../open_reading/book_sources/source_engine/source_runtime.dart';
import '../open_reading/book_sources/source_engine/source_login_ui.dart';
import '../open_reading/book_sources/source_engine/source_transport.dart';
import 'source_engine.dart';

class OpenReadingSourceAdapter {
  OpenReadingSourceAdapter({
    http.Client? client,
    required SourceEngineLimits limits,
  }) : _runtime = SourceRuntime(
         transport: client == null
             ? SourceHttpTransport(
                 requestTimeout: limits.timeout,
                 maxResponseBytes: limits.maxResponseBytes,
               )
             : _PackageHttpTransport(client, limits),
       );

  final SourceRuntime _runtime;
  final Set<String> _detailedBookIds = {};

  RegisteredBookSource registered(Map<String, Object?> source) {
    try {
      final normalized = source.map((key, value) => MapEntry(key, value));
      normalized.putIfAbsent(
        'bookSourceName',
        () => '${normalized['bookSourceUrl'] ?? '测试书源'}',
      );
      return ReadingSourceConfig.fromJson(normalized)
          .toRegisteredSource(enabled: true);
    } on FormatException catch (error) {
      throw UnsupportedRuleFailure(error.message.toString());
    }
  }

  Future<List<NetworkBook>> search({
    required Map<String, Object?> source,
    required String query,
    required int page,
    SourceCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final registeredSource = registered(source);
    final cancellation = _cancellation(cancellationToken);
    try {
      final result = await _runtime.search(
        registeredSource,
        query,
        page: page,
        pageSize: 100,
        cancellation: cancellation,
      );
      cancellationToken?.throwIfCancelled();
      return result.items
          .map(
            (book) => NetworkBook(
              sourceUrl: registeredSource.apiBaseUrl.toString(),
              title: book.title,
              locator: Uri.parse(book.id),
              author: book.author.isEmpty ? null : book.author,
              coverUrl: book.coverUrl?.toString(),
              intro: book.description.isEmpty ? null : book.description,
              lastChapter: book.latestChapter,
            ),
          )
          .toList(growable: false);
    } on BookDownloadCancelledException {
      throw const CancelledFailure();
    } on BookSourceProtocolException catch (error) {
      throw ParseFailure(error.message);
    }
  }

  Future<NetworkBookDetails> details({
    required Map<String, Object?> source,
    required NetworkBook book,
    SourceCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final registeredSource = registered(source);
    cancellationToken?.throwIfCancelled();
    try {
      final result = await _runtime.getBook(
        registeredSource,
        book.locator.toString(),
      );
      cancellationToken?.throwIfCancelled();
      _detailedBookIds
        ..add(book.locator.toString())
        ..add(result.id);
      return NetworkBookDetails(
        book: NetworkBook(
          sourceUrl: book.sourceUrl,
          title: result.title,
          locator: Uri.parse(result.id),
          author: result.author.isEmpty ? book.author : result.author,
          coverUrl: result.coverUrl?.toString() ?? book.coverUrl,
          intro: result.description.isEmpty ? book.intro : result.description,
          lastChapter: result.latestChapter ?? book.lastChapter,
        ),
        // SourceRuntime resolves the actual TOC request from this book id.
        tocUrl: Uri.parse(result.id),
      );
    } on BookSourceProtocolException catch (error) {
      throw ParseFailure(error.message);
    }
  }

  Future<List<SourceChapter>> chapters({
    required Map<String, Object?> source,
    required Uri bookUrl,
    SourceCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final effectiveSource = _detailedBookIds.contains(bookUrl.toString())
        ? source
        : (Map<String, Object?>.from(source)..['ruleBookInfo'] = const {});
    final registeredSource = registered(effectiveSource);
    cancellationToken?.throwIfCancelled();
    try {
      final chapters = await _runtime.getChapters(
        registeredSource,
        bookUrl.toString(),
      );
      cancellationToken?.throwIfCancelled();
      return chapters
          .map(
            (chapter) => SourceChapter(
              key: chapter.id,
              title: chapter.title,
              locator: Uri.parse(chapter.id),
              ordinal: chapter.order,
              bookLocator: bookUrl,
            ),
          )
          .toList(growable: false);
    } on BookSourceProtocolException catch (error) {
      throw ParseFailure(error.message);
    }
  }

  Future<String> content({
    required Map<String, Object?> source,
    required Uri chapterUrl,
    Uri? bookUrl,
    SourceCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final registeredSource = registered(source);
    cancellationToken?.throwIfCancelled();
    try {
      final result = await _runtime.getChapterContent(
        registeredSource,
        bookId: (bookUrl ?? chapterUrl).toString(),
        chapterId: chapterUrl.toString(),
      );
      cancellationToken?.throwIfCancelled();
      return result.content;
    } on BookSourceProtocolException catch (error) {
      throw ParseFailure(error.message);
    }
  }

  Future<List<SourceLoginField>> loadLoginFields(
    Map<String, Object?> source,
  ) async {
    try {
      return await _runtime.loadLoginFields(registered(source));
    } on BookSourceProtocolException catch (error) {
      throw ParseFailure(error.message);
    }
  }

  Future<void> login(
    Map<String, Object?> source,
    Map<String, String> values,
  ) async {
    try {
      await _runtime.login(registered(source), values);
    } on BookSourceProtocolException catch (error) {
      throw ParseFailure(error.message);
    }
  }

  Future<void> clearLogin(Map<String, Object?> source) async {
    try {
      await _runtime.clearLoginSession(registered(source));
    } on BookSourceProtocolException catch (error) {
      throw ParseFailure(error.message);
    }
  }

  BookDownloadCancellation? _cancellation(SourceCancellationToken? token) {
    if (token == null) return null;
    final cancellation = BookDownloadCancellation();
    token.addListener(cancellation.cancel);
    if (token.isCancelled) cancellation.cancel();
    return cancellation;
  }

  void close() => _runtime.close();
}

class _PackageHttpTransport
    implements SourceTransport, SourceClosableTransport {
  _PackageHttpTransport(this._client, this._limits);

  final http.Client _client;
  final SourceEngineLimits _limits;

  @override
  Future<SourceResponse> send(
    SourceRequestTemplate request, {
    BookDownloadCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    final outgoing = http.Request(
      request.method.name.toUpperCase(),
      request.url,
    )..headers.addAll(request.headers);
    if (request.body case final body? when body.isNotEmpty) {
      outgoing.bodyBytes = await CharsetConverter.encode(request.charset, body);
    }
    late http.StreamedResponse streamed;
    try {
      streamed = await _client.send(outgoing).timeout(_limits.timeout);
    } on TimeoutException {
      throw const BookSourceProtocolException('Book source request timed out.');
    }
    final bytes = <int>[];
    await for (final chunk in streamed.stream) {
      cancellation?.throwIfCancelled();
      bytes.addAll(chunk);
      if (bytes.length > _limits.maxResponseBytes) {
        throw const BookSourceProtocolException(
          'Book source response exceeds the supported size.',
        );
      }
    }
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw BookSourceProtocolException('HTTP ${streamed.statusCode}');
    }
    final contentType = streamed.headers['content-type'] ?? '';
    final declared = RegExp(
      r'''charset\s*=\s*["']?([^;\s"']+)''',
      caseSensitive: false,
    ).firstMatch(contentType)?.group(1)?.toLowerCase();
    final charset = declared ?? request.charset;
    late String body;
    try {
      body = charset == 'utf-8' || charset == 'utf8'
          ? utf8.decode(bytes)
          : await CharsetConverter.decode(charset, Uint8List.fromList(bytes));
    } on Object {
      throw BookSourceProtocolException('Unable to decode $charset response.');
    }
    return SourceResponse(
      body: body,
      finalUri: streamed.request?.url ?? request.url,
      statusCode: streamed.statusCode,
      headers: streamed.headers,
    );
  }

  @override
  void close({bool force = true}) => _client.close();
}
