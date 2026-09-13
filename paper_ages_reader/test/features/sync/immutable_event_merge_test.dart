import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/features/sync/domain/immutable_event_merge.dart';

void main() {
  const merger = ImmutableEventMerger();

  SyncEvent event(
    String id, {
    Set<String> parents = const {},
    SyncEventType type = SyncEventType.positionUpdated,
  }) => SyncEvent(
    eventId: id,
    entityKey: 'book:fixture',
    parentEventIds: parents,
    type: type,
  );

  test('replaces a head only when the incoming event cites it as a parent', () {
    final first = merger.apply(const SyncMergeState(), event('a'));
    final second = merger.apply(first.state, event('b', parents: {'a'}));

    expect(second.conflict, isNull);
    expect(second.state.headsByEntity['book:fixture']!.single.eventId, 'b');
  });

  test('keeps concurrent reading positions as explicit branches', () {
    final first = merger.apply(const SyncMergeState(), event('a'));
    final deviceA = merger.apply(first.state, event('b', parents: {'a'}));
    final deviceB = merger.apply(deviceA.state, event('c', parents: {'a'}));

    expect(deviceB.conflict, isNotNull);
    expect(
      deviceB.state.headsByEntity['book:fixture']!.map(
        (entry) => entry.eventId,
      ),
      unorderedEquals(['b', 'c']),
    );
  });

  test('is idempotent for a repeated remote event', () {
    final first = merger.apply(const SyncMergeState(), event('a'));
    final duplicate = merger.apply(first.state, event('a'));

    expect(duplicate.status, SyncMergeStatus.duplicate);
    expect(duplicate.state, same(first.state));
  });

  test(
    'does not silently discard a concurrent deletion or older read event',
    () {
      final first = merger.apply(const SyncMergeState(), event('a'));
      final deletion = merger.apply(
        first.state,
        event('deleted', parents: {'a'}, type: SyncEventType.bookRemoved),
      );
      final oldRead = merger.apply(
        first.state,
        event('old-read', parents: {'a'}),
      );
      final merged = merger.apply(
        deletion.state,
        oldRead.state.headsByEntity['book:fixture']!.single,
      );

      expect(merged.conflict, isNotNull);
      expect(
        merged.state.headsByEntity['book:fixture']!.map((entry) => entry.type),
        containsAll(<SyncEventType>[
          SyncEventType.bookRemoved,
          SyncEventType.positionUpdated,
        ]),
      );
    },
  );
}
