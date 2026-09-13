import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/core/storage/app_database.dart';
import 'package:paper_ages_reader/features/source_engine/data/persistent_source_binding_store.dart';
import 'package:paper_ages_reader/features/source_engine/domain/source_switch_service.dart';

void main() {
  test(
    'serializes competing switches and restores binding plus anchor',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'paper-ages-binding-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}${Platform.pathSeparator}state.json');
      final database = await AppDatabase.openFile(file);
      final store = PersistentSourceBindingStore(database);
      final first = SourceBinding(
        bookId: 'book',
        sourceUrl: 'https://one.example',
        locator: Uri.parse('https://one.example/chapter/1'),
        chapterKey: 'one-1',
        revision: 1,
      );
      final second = SourceBinding(
        bookId: 'book',
        sourceUrl: 'https://two.example',
        locator: Uri.parse('https://two.example/chapter/1'),
        chapterKey: 'two-1',
        revision: 1,
      );

      final results = await Future.wait([
        store.replaceIfCurrent(next: first, expectedRevision: 0),
        store.replaceIfCurrent(next: second, expectedRevision: 0),
      ]);
      expect(results.whereType<SourceSwitchCommitted>(), hasLength(1));
      expect(results.whereType<SourceSwitchRejected>(), hasLength(1));
      final committed = results
          .whereType<SourceSwitchCommitted>()
          .single
          .binding;
      expect(database.position('book')?['chapterKey'], committed.chapterKey);
      await database.close();

      final reopened = await AppDatabase.openFile(file);
      expect(reopened.sourceBinding('book')?['revision'], 1);
      expect(reopened.position('book')?['sourceUrl'], committed.sourceUrl);
      expect(reopened.position('book')?['bindingRevision'], 1);
      await reopened.close();
    },
  );
}
