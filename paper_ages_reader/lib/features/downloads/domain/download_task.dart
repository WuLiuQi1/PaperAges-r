enum DownloadStatus { queued, running, completed, cancelled, failed }

class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.bookId,
    required this.sourceUrl,
    required this.bindingRevision,
    required this.chapterKeys,
    required this.chapterUrls,
    required this.completedKeys,
    required this.status,
    this.lastError,
  });
  final String id;
  final String bookId;
  final String sourceUrl;
  final int bindingRevision;
  final List<String> chapterKeys;

  /// Stable chapter key to URL mapping. URLs are persisted so a resumed task
  /// never needs to infer a chapter from a title or ordinal.
  final Map<String, String> chapterUrls;
  final Set<String> completedKeys;
  final DownloadStatus status;
  final String? lastError;
  bool get isComplete => completedKeys.length == chapterKeys.length;

  Map<String, Object?> toJson() => {
    'id': id,
    'bookId': bookId,
    'sourceUrl': sourceUrl,
    'bindingRevision': bindingRevision,
    'chapterKeys': chapterKeys,
    'chapterUrls': chapterUrls,
    'completedKeys': completedKeys.toList(growable: false),
    'status': status.name,
    if (lastError != null) 'lastError': lastError,
  };

  factory DownloadTask.fromJson(Map<String, Object?> json) {
    final statusName = json['status'] as String?;
    final status = DownloadStatus.values.where(
      (item) => item.name == statusName,
    );
    return DownloadTask(
      id: json['id']! as String,
      bookId: json['bookId']! as String,
      sourceUrl: json['sourceUrl']! as String,
      bindingRevision: json['bindingRevision']! as int,
      chapterKeys: List<String>.from(json['chapterKeys']! as List),
      chapterUrls: Map<String, String>.from(json['chapterUrls']! as Map),
      completedKeys: Set<String>.from(json['completedKeys']! as List),
      status: status.isEmpty ? DownloadStatus.failed : status.first,
      lastError: json['lastError'] as String?,
    );
  }
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
    bookId: task.bookId,
    sourceUrl: task.sourceUrl,
    bindingRevision: task.bindingRevision,
    chapterKeys: task.chapterKeys,
    chapterUrls: task.chapterUrls,
    completedKeys: completedKeys ?? task.completedKeys,
    status: status ?? task.status,
    lastError: lastError,
  );
}
