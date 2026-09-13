import '../../../core/storage/app_database.dart';
import '../domain/download_task.dart';

/// Persists task state after every state transition.  It intentionally stores
/// only metadata; chapter bodies continue to live in ChapterCache.
class PersistentDownloadTaskRepository {
  const PersistentDownloadTaskRepository(this._database);
  final AppDatabase _database;

  Stream<List<DownloadTask>> watchTasks() => _database.watchDownloadTasks().map(
    (rows) => rows.map(DownloadTask.fromJson).toList(growable: false),
  );

  List<DownloadTask> get tasks => _database.downloadTasks
      .map(DownloadTask.fromJson)
      .toList(growable: false);

  DownloadTask? byId(String id) {
    for (final task in tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  Future<void> upsert(DownloadTask task) => _database.transaction((data) {
    final rows = List<Object?>.from(data['downloadTasks']! as List);
    rows.removeWhere((raw) => raw is Map && raw['id'] == task.id);
    rows.add(task.toJson());
    data['downloadTasks'] = rows;
  });
}
