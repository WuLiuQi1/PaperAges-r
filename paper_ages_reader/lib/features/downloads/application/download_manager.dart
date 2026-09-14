import '../data/chapter_cache.dart';
import '../data/persistent_download_task_repository.dart';
import '../domain/download_task.dart';
import '../../source_engine/domain/source_engine.dart';

typedef SourceEngineFactory = StaticSourceEngine Function();

/// Sequential, resumable downloader.  A task is durably updated after each
/// chapter; cancelling a running request prevents subsequent writes while
/// preserving already verified cache entries.
class DownloadManager {
  DownloadManager(
    this._repository,
    this._cache, {
    SourceEngineFactory? engineFactory,
  }) : _engineFactory = engineFactory ?? StaticSourceEngine.new;
  final PersistentDownloadTaskRepository _repository;
  final ChapterCache _cache;
  final SourceEngineFactory _engineFactory;
  final Map<String, SourceCancellationToken> _cancellations = {};
  final _machine = const DownloadTaskStateMachine();

  void cancel(String taskId) {
    _cancellations[taskId]?.cancel();
  }

  Future<void> run({
    required String taskId,
    required int currentBindingRevision,
    required Map<String, Object?> source,
  }) async {
    final saved = _repository.byId(taskId);
    if (saved == null) return;
    var task = _machine.start(
      saved,
      currentBindingRevision: currentBindingRevision,
    );
    // Register before the first await so a UI cancellation cannot fall into
    // the queued→running persistence window.
    final token = SourceCancellationToken();
    _cancellations[task.id] = token;
    await _repository.upsert(task);
    if (task.status != DownloadStatus.running) {
      _cancellations.remove(task.id);
      return;
    }

    final engine = _engineFactory();
    try {
      for (final key in task.chapterKeys) {
        token.throwIfCancelled();
        if (task.completedKeys.contains(key)) continue;
        final rawUrl = task.chapterUrls[key];
        if (rawUrl == null) throw StateError('下载任务缺少章节地址');
        final locator = Uri.parse(rawUrl);
        final content = await engine.content(
          source: source,
          chapterUrl: locator,
          bookUrl: Uri.tryParse(
            task.bookId.contains('|')
                ? task.bookId.substring(task.bookId.indexOf('|') + 1)
                : task.bookId,
          ),
          cancellationToken: token,
        );
        await _cache.write(
          ChapterCacheKey(
            sourceUrl: task.sourceUrl,
            sourceVersion: 'v1',
            locator: locator,
            chapterKey: key,
            contentRevision: 'v1',
          ),
          content,
        );
        task = _machine.chapterCompleted(task, key);
        await _repository.upsert(task);
      }
    } on CancelledFailure {
      task = _machine.cancel(task);
      await _repository.upsert(task);
    } catch (error) {
      task = _machine.fail(task, error);
      await _repository.upsert(task);
    } finally {
      _cancellations.remove(taskId);
      engine.close();
    }
  }

  Future<void> cancelPersisted(String taskId) async {
    cancel(taskId);
    final task = _repository.byId(taskId);
    if (task != null) await _repository.upsert(_machine.cancel(task));
  }

  Future<void> retry(String taskId) async {
    final task = _repository.byId(taskId);
    if (task == null || task.status == DownloadStatus.completed) return;
    await _repository.upsert(
      DownloadTask(
        id: task.id,
        bookId: task.bookId,
        sourceUrl: task.sourceUrl,
        bindingRevision: task.bindingRevision,
        chapterKeys: task.chapterKeys,
        chapterUrls: task.chapterUrls,
        completedKeys: task.completedKeys,
        status: DownloadStatus.queued,
      ),
    );
  }
}
