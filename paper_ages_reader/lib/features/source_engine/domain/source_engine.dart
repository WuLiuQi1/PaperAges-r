import 'package:http/http.dart' as http;

import 'open_reading_adapter.dart';

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
  final Set<void Function()> _listeners = {};

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List<void Function()>.from(_listeners)) {
      listener();
    }
    _listeners.clear();
  }

  void addListener(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

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
    this.bookLocator,
  });
  final String key;
  final String title;
  final Uri locator;
  final int ordinal;
  final Uri? bookLocator;
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
  }) : _adapter = OpenReadingSourceAdapter(client: client, limits: limits);

  final SourceEngineLimits limits;
  final OpenReadingSourceAdapter _adapter;

  Future<List<NetworkBook>> search({
    required Map<String, Object?> source,
    required String query,
    int page = 1,
    SourceCancellationToken? cancellationToken,
  }) => _adapter.search(
    source: source,
    query: query,
    page: page,
    cancellationToken: cancellationToken,
  );

  Future<List<SourceChapter>> chapters({
    required Map<String, Object?> source,
    required Uri tocUrl,
    SourceCancellationToken? cancellationToken,
  }) => _adapter.chapters(
    source: source,
    bookUrl: tocUrl,
    cancellationToken: cancellationToken,
  );

  Future<NetworkBookDetails> details({
    required Map<String, Object?> source,
    required NetworkBook book,
    SourceCancellationToken? cancellationToken,
  }) => _adapter.details(
    source: source,
    book: book,
    cancellationToken: cancellationToken,
  );

  Future<String> content({
    required Map<String, Object?> source,
    required Uri chapterUrl,
    Uri? bookUrl,
    SourceCancellationToken? cancellationToken,
  }) => _adapter.content(
    source: source,
    chapterUrl: chapterUrl,
    bookUrl: bookUrl,
    cancellationToken: cancellationToken,
  );

  void close() => _adapter.close();
}
