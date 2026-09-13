import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/features/sync/domain/immutable_event_merge.dart';

void main() {
  const codec = SyncEventCodec();
  test('round trips a canonical event with a verifiable payload hash', () {
    final event = codec.create(
      eventId: 'event-1',
      deviceId: 'device-a',
      deviceSeq: 1,
      entityKey: 'book:1',
      parentEventIds: const {},
      type: SyncEventType.positionUpdated,
      payload: {
        'bookId': '1',
        'anchor': {'chapterKey': 'a'},
      },
    );
    expect(codec.decode(event.toJson()).payload['bookId'], '1');
  });

  test('rejects a modified payload before it can be applied', () {
    final event = codec.create(
      eventId: 'event-1',
      deviceId: 'device-a',
      deviceSeq: 1,
      entityKey: 'book:1',
      parentEventIds: const {},
      type: SyncEventType.positionUpdated,
      payload: {'bookId': '1'},
    );
    final modified = event.toJson()..['payload'] = {'bookId': 'other'};
    expect(() => codec.decode(modified), throwsFormatException);
  });
}
