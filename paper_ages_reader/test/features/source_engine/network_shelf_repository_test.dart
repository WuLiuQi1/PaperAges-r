import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/core/storage/app_database.dart';
import 'package:paper_ages_reader/features/source_engine/data/network_shelf_repository.dart';
import 'package:paper_ages_reader/features/source_engine/data/persistent_source_binding_store.dart';
import 'package:paper_ages_reader/features/source_engine/domain/source_engine.dart';
import 'package:paper_ages_reader/features/source_engine/domain/source_switch_service.dart';

void main() {
  test(
    'shelving initializes a binding but never reverses a later switch',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'paper-ages-shelf-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final database = await AppDatabase.openFile(
        File('${directory.path}${Platform.pathSeparator}state.json'),
      );
      final book = NetworkBook(
        sourceUrl: 'https://one.example',
        title: '春秋',
        locator: Uri.parse('https://one.example/book/1'),
      );
      final first = SourceChapter(
        key: 'one',
        title: '第一章',
        locator: Uri.parse('https://one.example/chapter/1'),
        ordinal: 0,
      );
      final shelf = NetworkShelfRepository(database);
      final shelfUpdates = shelf.watchBooks().take(2).toList();
      await shelf.add(
        book: book,
        sourceUrl: book.sourceUrl,
        initialChapter: first,
      );
      final updates = await shelfUpdates;
      expect(updates.first, isEmpty);
      expect(updates.last.single.title, '春秋');
      final id = NetworkShelfRepository.bookIdFor(
        sourceUrl: book.sourceUrl,
        locator: book.locator,
      );
      final bindings = PersistentSourceBindingStore(database);
      expect(bindings.bindingFor(id)?.chapterKey, 'one');

      final switched = await bindings.replaceIfCurrent(
        expectedRevision: 1,
        next: SourceBinding(
          bookId: id,
          sourceUrl: 'https://two.example',
          locator: Uri.parse('https://two.example/chapter/8'),
          chapterKey: 'two-8',
          revision: 2,
        ),
      );
      expect(switched, isA<SourceSwitchCommitted>());
      await shelf.add(
        book: book,
        sourceUrl: book.sourceUrl,
        initialChapter: first,
      );
      final preserved = bindings.bindingFor(id)!;
      expect(preserved.sourceUrl, 'https://two.example');
      expect(preserved.chapterKey, 'two-8');
      expect(database.networkBooks, hasLength(1));
      await database.close();
    },
  );
}
