import '../../../core/storage/app_database.dart';
import '../domain/source_engine.dart';

class NetworkShelfRepository {
  NetworkShelfRepository(this._database);
  final AppDatabase _database;
  Stream<List<NetworkShelfBook>> watchBooks() => _database
      .watchNetworkBooks()
      .map((rows) => rows.map(NetworkShelfBook.fromRow).toList());
  static String bookIdFor({required String sourceUrl, required Uri locator}) =>
      '$sourceUrl|$locator';

  Future<void> add({
    required NetworkBook book,
    required String sourceUrl,
    required SourceChapter initialChapter,
  }) => _database.transaction((next) {
    final books = List<Object?>.from(next['networkBooks']! as List);
    books.removeWhere(
      (row) =>
          row is Map &&
          row['sourceUrl'] == sourceUrl &&
          row['locator'] == book.locator.toString(),
    );
    books.add({
      'title': book.title,
      'author': book.author,
      'sourceUrl': sourceUrl,
      'locator': book.locator.toString(),
      'bindingRevision': 1,
    });
    next['networkBooks'] = books;
    final bookId = bookIdFor(sourceUrl: sourceUrl, locator: book.locator);
    final bindings = Map<String, Object?>.from(
      next['sourceBindings'] as Map? ?? const <String, Object?>{},
    );
    // Re-adding a shelf entry must not undo a verified later source
    // switch. Initial binding is created only once for this identity.
    if (!bindings.containsKey(bookId)) {
      bindings[bookId] = {
        'bookId': bookId,
        'sourceUrl': sourceUrl,
        'locator': initialChapter.locator.toString(),
        'chapterKey': initialChapter.key,
        'revision': 1,
      };
      final positions = Map<String, Object?>.from(next['positions']! as Map);
      positions[bookId] = {
        'sourceUrl': sourceUrl,
        'locator': initialChapter.locator.toString(),
        'chapterKey': initialChapter.key,
        'bindingRevision': 1,
        'updatedAtMillis': DateTime.now().millisecondsSinceEpoch,
      };
      next['positions'] = positions;
    }
    next['sourceBindings'] = bindings;
  });

  Future<void> remove(NetworkShelfBook book) => _database.transaction((next) {
    final bookId = bookIdFor(sourceUrl: book.sourceUrl, locator: book.locator);
    final books = List<Object?>.from(next['networkBooks']! as List)
      ..removeWhere(
        (row) =>
            row is Map &&
            row['sourceUrl'] == book.sourceUrl &&
            row['locator'] == book.locator.toString(),
      );
    final bindings = Map<String, Object?>.from(
      next['sourceBindings'] as Map? ?? const <String, Object?>{},
    )..remove(bookId);
    final positions = Map<String, Object?>.from(next['positions']! as Map)
      ..remove(bookId);
    next['networkBooks'] = books;
    next['sourceBindings'] = bindings;
    next['positions'] = positions;
  });
}

class NetworkShelfBook {
  const NetworkShelfBook({
    required this.title,
    required this.sourceUrl,
    required this.locator,
    this.author,
  });
  factory NetworkShelfBook.fromRow(Map<String, Object?> row) =>
      NetworkShelfBook(
        title: row['title']! as String,
        author: row['author'] as String?,
        sourceUrl: row['sourceUrl']! as String,
        locator: Uri.parse(row['locator']! as String),
      );
  final String title;
  final String? author;
  final String sourceUrl;
  final Uri locator;
}
