import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/core/storage/app_database.dart';
import 'package:paper_ages_reader/features/sync/data/persistent_sync_outbox.dart';
import 'package:paper_ages_reader/features/sync/domain/immutable_event_merge.dart';

void main() {
  test(
    'persists a whitelisted event and removes it only after confirmation',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'paper-ages-sync-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final database = await AppDatabase.openFile(
        File('${directory.path}/state.json'),
      );
      addTearDown(database.close);
      final codec = const SyncEventCodec();
      final event = codec.create(
        eventId: 'event-a',
        deviceId: 'device-a',
        deviceSeq: 1,
        entityKey: 'book:a',
        parentEventIds: const {},
        type: SyncEventType.shelfUpdated,
        payload: {'bookId': 'a', 'shelfState': 'joined'},
      );
      final outbox = PersistentSyncOutbox(database);
      await outbox.enqueue(event);
      await outbox.enqueue(event);
      expect(outbox.pending.single.eventId, 'event-a');
      await outbox.markUploaded('event-a');
      expect(outbox.pending, isEmpty);
    },
  );

  test('refuses an event with body content before persistence', () async {
    final directory = await Directory.systemTemp.createTemp('paper-ages-sync-');
    addTearDown(() => directory.delete(recursive: true));
    final database = await AppDatabase.openFile(
      File('${directory.path}/state.json'),
    );
    addTearDown(database.close);
    final event = const SyncEventCodec().create(
      eventId: 'event-b',
      deviceId: 'device-a',
      deviceSeq: 2,
      entityKey: 'book:b',
      parentEventIds: const {},
      type: SyncEventType.positionUpdated,
      payload: {'bodyText': 'must never leave device'},
    );
    expect(PersistentSyncOutbox(database).enqueue(event), throwsArgumentError);
  });
}
