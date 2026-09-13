import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/storage/app_database.dart';
import '../domain/library_book.dart';

class SavedReadingPosition {
  const SavedReadingPosition({
    required this.blockIndex,
    required this.revision,
  });
  final int blockIndex;
  final int revision;
}

class LocalLibraryRepository {
  LocalLibraryRepository(this._database);
  final AppDatabase _database;

  List<LibraryBook> get recentBooks {
    final books = _database.books.map(_bookFromRow).toList();
    books.sort((a, b) {
      final aTime =
          _database.position(a.id)?['updatedAtMillis'] as int? ??
          a.createdAt.millisecondsSinceEpoch;
      final bTime =
          _database.position(b.id)?['updatedAtMillis'] as int? ??
          b.createdAt.millisecondsSinceEpoch;
      return bTime.compareTo(aTime);
    });
    return books;
  }

  String progressLabel(String bookId) {
    final row = _database.position(bookId);
    if (row == null) return '新书';
    final count = row['totalBlocks'] as int?;
    if (count == null || count <= 0) return '阅读中';
    final index = row['blockIndex'] as int? ?? 0;
    return '${((index + 1) / count * 100).clamp(0, 100).floor()}%';
  }

  Stream<List<LibraryBook>> watchBooks() => _database.watchBooks().map((rows) {
    final books = rows.map(_bookFromRow).toList();
    books.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return books;
  });

  Future<LibraryBook> importFile({
    required String title,
    required LibraryBookKind kind,
    required List<int> bytes,
    String? encoding,
  }) async {
    final id = _newId();
    final root = await getApplicationDocumentsDirectory();
    final imports = Directory('${root.path}${Platform.pathSeparator}imports');
    await imports.create(recursive: true);
    final extension = kind == LibraryBookKind.pdf ? 'pdf' : 'txt';
    final finalFile = File(
      '${imports.path}${Platform.pathSeparator}$id.$extension',
    );
    final temporary = File('${finalFile.path}.part');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(finalFile.path);
    final now = DateTime.now();
    final book = LibraryBook(
      id: id,
      kind: kind,
      title: title,
      filePath: finalFile.path,
      encoding: encoding,
      fingerprint: sha256.convert(bytes).toString(),
      createdAt: now,
    );
    try {
      await _database.transaction((next) {
        final books = List<Object?>.from(next['books']! as List);
        books.add({
          'id': book.id,
          'kind': book.kind.name,
          'title': book.title,
          'filePath': book.filePath,
          'encoding': book.encoding,
          'fingerprint': book.fingerprint,
          'createdAtMillis': book.createdAt.millisecondsSinceEpoch,
        });
        next['books'] = books;
      });
    } catch (_) {
      if (await finalFile.exists()) await finalFile.delete();
      rethrow;
    }
    return book;
  }

  Future<String> readText(LibraryBook book) =>
      File(book.filePath).readAsString();

  Future<void> savePosition({
    required String bookId,
    required int blockIndex,
    required int graphemeOffset,
    required String contextHash,
    required int revision,
    int? totalBlocks,
  }) => _database.transaction((next) {
    final positions = Map<String, Object?>.from(next['positions']! as Map);
    positions[bookId] = {
      'blockIndex': blockIndex,
      'graphemeOffset': graphemeOffset,
      'contextHash': contextHash,
      'revision': revision,
      'totalBlocks': ?totalBlocks,
      'updatedAtMillis': DateTime.now().millisecondsSinceEpoch,
    };
    next['positions'] = positions;
  });

  Future<SavedReadingPosition?> readPosition(String bookId) async {
    final row = _database.position(bookId);
    if (row == null) return null;
    return SavedReadingPosition(
      blockIndex: row['blockIndex'] as int? ?? 0,
      revision: row['revision'] as int? ?? 0,
    );
  }

  Future<void> savePreference(String key, String value) =>
      _database.transaction((next) {
        final preferences = Map<String, Object?>.from(
          next['preferences']! as Map,
        )..[key] = value;
        next['preferences'] = preferences;
      });

  Future<String?> readPreference(String key) async => _database.preference(key);

  LibraryBook _bookFromRow(Map<String, Object?> row) => LibraryBook(
    id: row['id']! as String,
    kind: row['kind'] == 'pdf' ? LibraryBookKind.pdf : LibraryBookKind.text,
    title: row['title']! as String,
    filePath: row['filePath']! as String,
    encoding: row['encoding'] as String?,
    fingerprint: row['fingerprint']! as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      row['createdAtMillis']! as int,
    ),
  );

  String _newId() => base64UrlEncode(
    List<int>.generate(16, (_) => Random.secure().nextInt(256)),
  ).replaceAll('=', '');
}
