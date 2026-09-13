import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/core/storage/app_database.dart';

void main() {
  test('migrates v3 data without losing books, positions or sources', () async {
    final directory = await Directory.systemTemp.createTemp('paper-ages-db-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}state.json');
    await file.writeAsString(
      jsonEncode({
        'schemaVersion': 3,
        'books': [
          {'id': 'book', 'title': '旧书'},
        ],
        'positions': {
          'book': {'blockIndex': 8},
        },
        'preferences': {'theme': 'dark'},
        'sources': [
          {'url': 'https://source.example'},
        ],
        'networkBooks': [
          {'locator': 'https://source.example/book'},
        ],
      }),
    );

    final database = await AppDatabase.openFile(file);
    expect(database.books.single['id'], 'book');
    expect(database.position('book')?['blockIndex'], 8);
    expect(database.sources.single['url'], 'https://source.example');
    expect(
      database.networkBooks.single['locator'],
      'https://source.example/book',
    );
    await database.transaction((next) {
      expect(next['sourceBindings'], isA<Map>());
      expect(next['downloadTasks'], isEmpty);
    });
    await database.close();

    final decoded =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect(decoded['schemaVersion'], 4);
  });
}
