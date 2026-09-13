import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:paper_ages_reader/core/storage/app_database.dart';
import 'package:paper_ages_reader/features/downloads/application/download_manager.dart';
import 'package:paper_ages_reader/features/downloads/data/chapter_cache.dart';
import 'package:paper_ages_reader/features/downloads/data/persistent_download_task_repository.dart';
import 'package:paper_ages_reader/features/downloads/domain/download_task.dart';
import 'package:paper_ages_reader/features/source_engine/domain/source_engine.dart';

void main() {
  final source = <String, Object?>{
    'bookSourceUrl': 'https://source.example/',
    'ruleContent': {'content': '#content@text'},
  };

  DownloadTask task({String id = 'task'}) => DownloadTask(
    id: id,
    bookId: 'book',
    sourceUrl: 'https://source.example/',
    bindingRevision: 2,
    chapterKeys: const ['one', 'two'],
    chapterUrls: const {
      'one': 'https://source.example/one',
      'two': 'https://source.example/two',
    },
    completedKeys: const {},
    status: DownloadStatus.queued,
  );

  Future<
    ({
      AppDatabase database,
      PersistentDownloadTaskRepository tasks,
      ChapterCache cache,
      Directory directory,
    })
  >
  setup() async {
    final directory = await Directory.systemTemp.createTemp(
      'paper-ages-download-',
    );
    final database = await AppDatabase.openFile(
      File('${directory.path}${Platform.pathSeparator}state.json'),
    );
    final cacheDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}cache',
    );
    await cacheDirectory.create();
    return (
      database: database,
      tasks: PersistentDownloadTaskRepository(database),
      cache: ChapterCache(cacheDirectory),
      directory: directory,
    );
  }

  test(
    'downloads each chapter and persists only verified completed keys',
    () async {
      final values = await setup();
      addTearDown(() async {
        await values.database.close();
        await values.directory.delete(recursive: true);
      });
      await values.tasks.upsert(task());
      final manager = DownloadManager(
        values.tasks,
        values.cache,
        engineFactory: () => StaticSourceEngine(
          client: MockClient(
            (request) async => http.Response.bytes(
              request.url.path == '/one'
                  ? utf8.encode('<article id="content">第一章</article>')
                  : utf8.encode('<article id="content">第二章</article>'),
              200,
              headers: const {'content-type': 'text/html; charset=utf-8'},
            ),
          ),
        ),
      );

      await manager.run(
        taskId: 'task',
        currentBindingRevision: 2,
        source: source,
      );

      final completed = values.tasks.byId('task')!;
      expect(completed.status, DownloadStatus.completed);
      expect(completed.completedKeys, {'one', 'two'});
      expect(
        await values.cache.read(
          ChapterCacheKey(
            sourceUrl: completed.sourceUrl,
            sourceVersion: 'v1',
            locator: Uri.parse(completed.chapterUrls['one']!),
            chapterKey: 'one',
            contentRevision: 'v1',
          ),
        ),
        '第一章',
      );
    },
  );

  test('binding mismatch cancels before a network request', () async {
    final values = await setup();
    addTearDown(() async {
      await values.database.close();
      await values.directory.delete(recursive: true);
    });
    await values.tasks.upsert(task());
    var calls = 0;
    final manager = DownloadManager(
      values.tasks,
      values.cache,
      engineFactory: () => StaticSourceEngine(
        client: MockClient((_) async {
          calls++;
          return http.Response('', 200);
        }),
      ),
    );

    await manager.run(
      taskId: 'task',
      currentBindingRevision: 3,
      source: source,
    );
    expect(values.tasks.byId('task')!.status, DownloadStatus.cancelled);
    expect(calls, 0);
  });

  test(
    'cancellation during a request writes neither completion nor cache',
    () async {
      final values = await setup();
      addTearDown(() async {
        await values.database.close();
        await values.directory.delete(recursive: true);
      });
      await values.tasks.upsert(task(id: 'cancel'));
      final response = Completer<http.Response>();
      final manager = DownloadManager(
        values.tasks,
        values.cache,
        engineFactory: () =>
            StaticSourceEngine(client: MockClient((_) => response.future)),
      );
      final running = manager.run(
        taskId: 'cancel',
        currentBindingRevision: 2,
        source: source,
      );
      await Future<void>.delayed(Duration.zero);
      manager.cancel('cancel');
      response.complete(
        http.Response.bytes(
          utf8.encode('<article id="content">不应写入</article>'),
          200,
          headers: const {'content-type': 'text/html; charset=utf-8'},
        ),
      );
      await running;

      final cancelled = values.tasks.byId('cancel')!;
      expect(cancelled.status, DownloadStatus.cancelled);
      expect(cancelled.completedKeys, isEmpty);
      expect(
        await values.cache.read(
          ChapterCacheKey(
            sourceUrl: cancelled.sourceUrl,
            sourceVersion: 'v1',
            locator: Uri.parse(cancelled.chapterUrls['one']!),
            chapterKey: 'one',
            contentRevision: 'v1',
          ),
        ),
        isNull,
      );
    },
  );
}
