import '../../../core/storage/app_database.dart';
import '../domain/source_switch_service.dart';

/// Durable compare-and-set store for source mappings.  The expected revision
/// check and replacement share one database transaction, so an interrupted
/// switch leaves the previous readable mapping intact.
class PersistentSourceBindingStore {
  const PersistentSourceBindingStore(this._database);
  final AppDatabase _database;

  SourceBinding? bindingFor(String bookId) {
    final row = _database.sourceBinding(bookId);
    return row == null ? null : _fromRow(row);
  }

  Future<SourceSwitchResult> replaceIfCurrent({
    required SourceBinding next,
    required int expectedRevision,
  }) async {
    SourceSwitchResult result = const SourceSwitchRejected('书源切换未执行');
    await _database.transaction((data) {
      final bindings = Map<String, Object?>.from(
        data['sourceBindings']! as Map,
      );
      final currentRaw = bindings[next.bookId];
      final current = currentRaw is Map
          ? _fromRow(Map<String, Object?>.from(currentRaw))
          : null;
      if ((current?.revision ?? 0) != expectedRevision) {
        result = const SourceSwitchRejected('书源已被其他操作更新');
        return;
      }
      bindings[next.bookId] = _toRow(next);
      data['sourceBindings'] = bindings;
      // The source identity and the readable chapter anchor are one durable
      // snapshot. Preserve any layout-specific anchor data already present;
      // only replace the source-facing fields after the candidate was read.
      final positions = Map<String, Object?>.from(data['positions']! as Map);
      final priorPosition = positions[next.bookId];
      final position = priorPosition is Map
          ? Map<String, Object?>.from(priorPosition)
          : <String, Object?>{};
      position
        ..['sourceUrl'] = next.sourceUrl
        ..['locator'] = next.locator.toString()
        ..['chapterKey'] = next.chapterKey
        ..['bindingRevision'] = next.revision
        ..['updatedAtMillis'] = DateTime.now().millisecondsSinceEpoch;
      positions[next.bookId] = position;
      data['positions'] = positions;
      result = SourceSwitchCommitted(next);
    });
    return result;
  }

  static Map<String, Object?> _toRow(SourceBinding binding) => {
    'bookId': binding.bookId,
    'sourceUrl': binding.sourceUrl,
    'locator': binding.locator.toString(),
    'chapterKey': binding.chapterKey,
    'revision': binding.revision,
  };

  static SourceBinding _fromRow(Map<String, Object?> row) => SourceBinding(
    bookId: row['bookId']! as String,
    sourceUrl: row['sourceUrl']! as String,
    locator: Uri.parse(row['locator']! as String),
    chapterKey: row['chapterKey']! as String,
    revision: row['revision']! as int,
  );
}
