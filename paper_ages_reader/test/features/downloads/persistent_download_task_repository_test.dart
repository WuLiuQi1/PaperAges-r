import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/core/storage/app_database.dart';
import 'package:paper_ages_reader/features/downloads/data/persistent_download_task_repository.dart';
import 'package:paper_ages_reader/features/downloads/domain/download_task.dart';

void main() {
  const task = DownloadTask(
    id: 'task',
    bookId: 'book',
    sourceUrl: 'https://source.example',
    bindingRevision: 3,
    chapterKeys: ['one', 'two'],
    chapterUrls: {
      'one': 'https://source.example/one',
      'two': 'https://source.example/two',
    },
    completedKeys: {'one', 'two'},
    status: DownloadStatus.completed,
  );

  test(
    'persists tasks and resets offline claims before cache removal',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'paper-ages-task-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}${Platform.pathSeparator}state.json');
      final database = await AppDatabase.openFile(file);
      final repository = PersistentDownloadTaskRepository(database);
      await repository.upsert(task);
      await repository.resetForCacheClear();
      await database.close();

      final reopened = await AppDatabase.openFile(file);
      final restored = PersistentDownloadTaskRepository(reopened).byId('task')!;
      expect(restored.status, DownloadStatus.queued);
      expect(restored.completedKeys, isEmpty);
      expect(restored.chapterUrls, task.chapterUrls);
      await reopened.close();
    },
  );
}
