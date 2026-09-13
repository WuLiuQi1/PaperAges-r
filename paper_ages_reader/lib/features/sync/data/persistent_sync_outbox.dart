import '../../../core/storage/app_database.dart';
import '../domain/immutable_event_merge.dart';
import '../domain/sync_whitelist_policy.dart';

/// Durable, transaction-backed queue. Credentials deliberately never enter it.
class PersistentSyncOutbox {
  PersistentSyncOutbox(this._database, {SyncEventCodec? codec})
    : _codec = codec ?? const SyncEventCodec();

  final AppDatabase _database;
  final SyncEventCodec _codec;

  List<SyncEvent> get pending =>
      _database.syncOutbox.map(_codec.decode).toList();

  Future<void> enqueue(SyncEvent event) async {
    final report = const SyncWhitelistPolicy().inspect(event.toJson());
    if (!report.isSafeToUpload) {
      throw ArgumentError.value(
        report.issues,
        'event',
        'Contains forbidden sync data',
      );
    }
    await _database.transaction((next) {
      final outbox = List<Object?>.from(next['syncOutbox']! as List);
      if (!outbox.whereType<Map>().any(
        (row) => row['eventId'] == event.eventId,
      )) {
        outbox.add(event.toJson());
      }
      next['syncOutbox'] = outbox;
    });
  }

  Future<void> markUploaded(String eventId) => _database.transaction((next) {
    next['syncOutbox'] = (next['syncOutbox']! as List)
        .where((row) => row is! Map || row['eventId'] != eventId)
        .toList();
  });

  Future<void> markApplied(String eventId) => _database.transaction((next) {
    final ids = List<Object?>.from(next['syncAppliedEventIds']! as List);
    if (!ids.contains(eventId)) ids.add(eventId);
    next['syncAppliedEventIds'] = ids;
  });
}
