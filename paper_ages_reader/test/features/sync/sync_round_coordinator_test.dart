import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/core/storage/app_database.dart';
import 'package:paper_ages_reader/features/sync/application/sync_round_coordinator.dart';
import 'package:paper_ages_reader/features/sync/data/persistent_sync_outbox.dart';
import 'package:paper_ages_reader/features/sync/domain/immutable_event_merge.dart';

void main() {
  late AppDatabase database;
  late PersistentSyncOutbox outbox;
  final codec = const SyncEventCodec();

  setUp(() async {
    final directory = await Directory.systemTemp.createTemp(
      'paper-ages-round-',
    );
    addTearDown(() => directory.delete(recursive: true));
    database = await AppDatabase.openFile(File('${directory.path}/state.json'));
    outbox = PersistentSyncOutbox(database);
    addTearDown(database.close);
  });

  SyncEvent event(String id, {Set<String> parents = const {}}) => codec.create(
    eventId: id,
    deviceId: 'device_a',
    deviceSeq: id.codeUnitAt(0),
    entityKey: 'book:a',
    parentEventIds: parents,
    type: SyncEventType.positionUpdated,
    payload: {'bookId': 'a'},
  );

  test(
    'retries dependent remote events after their parent is applied',
    () async {
      final parent = event('parent');
      final child = event('child', parents: {'parent'});
      final applied = <String>[];
      final result = await SyncRoundCoordinator(
        outbox: outbox,
        loadRemote: () async => [child, parent],
        applyRemote: (value) async => applied.add(value.eventId),
        upload: (_) async {},
      ).run();
      expect(applied, ['parent', 'child']);
      expect(result.deferredRemoteIds, isEmpty);
    },
  );

  test(
    'keeps dependency-missing events deferred instead of guessing order',
    () async {
      final result = await SyncRoundCoordinator(
        outbox: outbox,
        loadRemote: () async => [
          event('child', parents: {'missing'}),
        ],
        applyRemote: (_) async => fail('must not apply'),
        upload: (_) async {},
      ).run();
      expect(result.deferredRemoteIds, {'child'});
    },
  );

  test('only removes local outbox records after upload succeeds', () async {
    await outbox.enqueue(event('local'));
    final result = await SyncRoundCoordinator(
      outbox: outbox,
      loadRemote: () async => const [],
      applyRemote: (_) async {},
      upload: (_) async => throw StateError('offline'),
    ).run();
    expect(result.uploadFailures.keys, {'local'});
    expect(outbox.pending.single.eventId, 'local');
  });
}
