import '../../../core/storage/app_database.dart';
import '../domain/source_engine.dart';

class NetworkShelfRepository {
  NetworkShelfRepository(this._database);
  final AppDatabase _database;
  Stream<List<NetworkShelfBook>> watchBooks() => _database
      .watchNetworkBooks()
      .map((rows) => rows.map(NetworkShelfBook.fromRow).toList());
  Future<void> add({required NetworkBook book, required String sourceUrl}) =>
      _database.transaction((next) {
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
