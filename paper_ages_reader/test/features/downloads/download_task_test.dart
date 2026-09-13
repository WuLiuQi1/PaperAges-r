import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/features/downloads/domain/download_task.dart';

void main() {
  const machine = DownloadTaskStateMachine();
  DownloadTask task() => const DownloadTask(
    id: 'task',
    bookId: 'book',
    sourceUrl: 'https://example.test/source',
    bindingRevision: 2,
    chapterKeys: ['a', 'b'],
    chapterUrls: {'a': 'https://example.test/a', 'b': 'https://example.test/b'},
    completedKeys: {},
    status: DownloadStatus.queued,
  );
  test('a changed source binding cancels rather than mixing old content', () {
    final result = machine.start(task(), currentBindingRevision: 3);
    expect(result.status, DownloadStatus.cancelled);
  });
  test('only all completed chapters mark a task complete', () {
    final started = machine.start(task(), currentBindingRevision: 2);
    expect(
      machine.chapterCompleted(started, 'a').status,
      DownloadStatus.running,
    );
    expect(
      machine
          .chapterCompleted(machine.chapterCompleted(started, 'a'), 'b')
          .status,
      DownloadStatus.completed,
    );
  });
  test('durable task payload retains URLs and completed chapter keys', () {
    final saved = task().toJson();
    final restored = DownloadTask.fromJson(saved);
    expect(restored.chapterUrls['a'], 'https://example.test/a');
    expect(restored.completedKeys, isEmpty);
    expect(restored.sourceUrl, 'https://example.test/source');
  });
}
