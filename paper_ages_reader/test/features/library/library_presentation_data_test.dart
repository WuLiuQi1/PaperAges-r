import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/core/storage/app_database.dart';
import 'package:paper_ages_reader/features/library/data/local_library_repository.dart';
import 'package:paper_ages_reader/features/library/domain/library_book.dart';

void main() {
  test('recent shelf and percentage derive from persisted positions', () async {
    final directory = await Directory.systemTemp.createTemp(
      'paper-ages-shelf-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/state.json');
    final database = await AppDatabase.openFile(file);
    addTearDown(database.close);
    await database.transaction((next) {
      next['books'] = [
        for (var i = 0; i < 2; i++)
          {
            'id': '$i',
            'kind': 'text',
            'title': 'Book $i',
            'filePath': '/test/$i.txt',
            'fingerprint': '$i',
            'createdAtMillis': i,
          },
      ];
    });
    final repository = LocalLibraryRepository(database);
    expect(repository.recentBooks.first.id, '1');
    expect(repository.progressLabel('0'), '新书');
    await repository.savePosition(
      bookId: '0',
      blockIndex: 2,
      graphemeOffset: 0,
      contextHash: 'hash',
      revision: 1,
      totalBlocks: 100,
    );
    expect(repository.recentBooks.first.id, '0');
    expect(repository.progressLabel('0'), '3%');
    final reopened = await AppDatabase.openFile(file);
    addTearDown(reopened.close);
    expect(LocalLibraryRepository(reopened).progressLabel('0'), '3%');
    await repository.savePosition(
      bookId: '1',
      blockIndex: 2,
      graphemeOffset: 0,
      contextHash: 'hash',
      revision: 1,
    );
    expect(repository.progressLabel('1'), '阅读中');
  });

  test('deleting a local book removes metadata, position and file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'paper-ages-delete-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final imported = File('${directory.path}/book.txt')
      ..writeAsStringSync('正文');
    final database = await AppDatabase.openFile(
      File('${directory.path}/state.json'),
    );
    addTearDown(database.close);
    await database.transaction((next) {
      next['books'] = [
        {
          'id': 'delete-me',
          'kind': 'text',
          'title': '待删除',
          'filePath': imported.path,
          'fingerprint': 'fingerprint',
          'createdAtMillis': 1,
        },
      ];
      next['positions'] = {
        'delete-me': {'blockIndex': 1, 'revision': 1},
      };
    });
    await LocalLibraryRepository(database).removeBook(
      LibraryBook(
        id: 'delete-me',
        kind: LibraryBookKind.text,
        title: '待删除',
        filePath: imported.path,
        fingerprint: 'fingerprint',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1),
      ),
    );
    expect(database.books, isEmpty);
    expect(database.position('delete-me'), isNull);
    expect(imported.existsSync(), isFalse);
  });
}
