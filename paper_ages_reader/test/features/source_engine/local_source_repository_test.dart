import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/core/storage/app_database.dart';
import 'package:paper_ages_reader/features/source_engine/data/local_source_repository.dart';
import 'package:paper_ages_reader/features/source_engine/data/persistent_source_binding_store.dart';
import 'package:paper_ages_reader/features/source_engine/domain/source_switch_service.dart';

void main() {
  const original = '''[
    {"bookSourceName":"原配置","bookSourceUrl":"https://source.example","searchUrl":"/one?key={{key}}","ruleSearch":{"bookList":".book","name":"a@text","bookUrl":"a@href"}}
  ]''';
  const reimport = '''[
    {"bookSourceName":"新配置","bookSourceUrl":"https://source.example","searchUrl":"/two?key={{key}}","ruleSearch":{"bookList":".book","name":"a@text","bookUrl":"a@href"}}
  ]''';

  test(
    'reimport never replaces the configuration of an active binding',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'paper-ages-source-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final database = await AppDatabase.openFile(
        File('${directory.path}${Platform.pathSeparator}state.json'),
      );
      final sources = LocalSourceRepository(database);
      await sources.importJson(original);
      final switched = await PersistentSourceBindingStore(database)
          .replaceIfCurrent(
            expectedRevision: 0,
            next: SourceBinding(
              bookId: 'book',
              sourceUrl: 'https://source.example',
              locator: Uri.parse('https://source.example/chapter/1'),
              chapterKey: 'one',
              revision: 1,
            ),
          );
      expect(switched, isA<SourceSwitchCommitted>());

      final result = await sources.importJson(reimport);
      expect(result.retainedBoundUrls, ['https://source.example']);
      final stored = await sources.findByUrl('https://source.example');
      expect(stored!.name, '原配置');
      expect(stored.configuration['searchUrl'], '/one?key={{key}}');
      await database.close();
    },
  );
}
