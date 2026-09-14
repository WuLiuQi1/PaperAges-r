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

  test('enable state is durable and unbound sources can be removed', () async {
    final directory = await Directory.systemTemp.createTemp(
      'paper-ages-source-state-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final database = await AppDatabase.openFile(
      File('${directory.path}${Platform.pathSeparator}state.json'),
    );
    final sources = LocalSourceRepository(database);
    await sources.importJson(
      '[{"bookSourceName":"A","bookSourceUrl":"https://a.example","enabled":false,"bookSourceGroup":"小说,测试"},{"bookSourceName":"B","bookSourceUrl":"https://b.example"}]',
    );

    expect((await sources.findByUrl('https://a.example'))!.enabled, isFalse);
    expect((await sources.findByUrl('https://a.example'))!.groups, [
      '小说',
      '测试',
    ]);
    await sources.setEnabledAll(const [
      'https://a.example',
      'https://b.example',
    ], true);
    expect((await sources.findByUrl('https://a.example'))!.enabled, isTrue);
    await sources.remove('https://b.example');
    expect(await sources.findByUrl('https://b.example'), isNull);
    await database.close();
  });

  test('bulk removal is atomic when any selected source is bound', () async {
    final directory = await Directory.systemTemp.createTemp(
      'paper-ages-source-remove-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final database = await AppDatabase.openFile(
      File('${directory.path}${Platform.pathSeparator}state.json'),
    );
    final sources = LocalSourceRepository(database);
    await sources.importJson(
      '[{"bookSourceName":"A","bookSourceUrl":"https://a.example"},{"bookSourceName":"B","bookSourceUrl":"https://b.example"}]',
    );
    await PersistentSourceBindingStore(database).replaceIfCurrent(
      expectedRevision: 0,
      next: SourceBinding(
        bookId: 'bound-book',
        sourceUrl: 'https://b.example',
        locator: Uri.parse('https://b.example/1'),
        chapterKey: 'one',
        revision: 1,
      ),
    );

    await expectLater(
      sources.removeAll(const ['https://a.example', 'https://b.example']),
      throwsStateError,
    );
    expect(await sources.findByUrl('https://a.example'), isNotNull);
    expect(await sources.findByUrl('https://b.example'), isNotNull);
    await database.close();
  });
}
