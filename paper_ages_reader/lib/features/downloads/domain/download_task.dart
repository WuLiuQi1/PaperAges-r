enum DownloadStatus { queued, running, completed, cancelled, failed }

class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.bindingRevision,
    required this.chapterKeys,
    required this.completedKeys,
    required this.status,
    this.lastError,
  });
  final String id;
  final int bindingRevision;
  final List<String> chapterKeys;
  final Set<String> completedKeys;
  final DownloadStatus status;
  final String? lastError;
  bool get isComplete => completedKeys.length == chapterKeys.length;
}

class DownloadTaskStateMachine {
  const DownloadTaskStateMachine();
  DownloadTask start(DownloadTask task, {required int currentBindingRevision}) {
    if (task.bindingRevision != currentBindingRevision) {
      return _with(
        task,
        status: DownloadStatus.cancelled,
        lastError: '书源已切换，旧下载已取消',
      );
    }
    return _with(task, status: DownloadStatus.running);
  }

  DownloadTask chapterCompleted(DownloadTask task, String chapterKey) {
    if (task.status != DownloadStatus.running) {
      return task;
    }
    final completed = {...task.completedKeys, chapterKey};
    return _with(
      task,
      completedKeys: completed,
      status: completed.length == task.chapterKeys.length
          ? DownloadStatus.completed
          : DownloadStatus.running,
    );
  }

  DownloadTask cancel(DownloadTask task) =>
      task.status == DownloadStatus.completed
      ? task
      : _with(task, status: DownloadStatus.cancelled);
  DownloadTask fail(DownloadTask task, Object error) =>
      _with(task, status: DownloadStatus.failed, lastError: error.toString());
  DownloadTask _with(
    DownloadTask task, {
    Set<String>? completedKeys,
    DownloadStatus? status,
    String? lastError,
  }) => DownloadTask(
    id: task.id,
    bindingRevision: task.bindingRevision,
    chapterKeys: task.chapterKeys,
    completedKeys: completedKeys ?? task.completedKeys,
    status: status ?? task.status,
    lastError: lastError,
  );
}
