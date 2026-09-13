/// A small, transport-independent immutable event merge model for WebDAV.
///
/// It intentionally has no wall-clock conflict rule: a user may legitimately
/// read backwards, so a numerically greater position cannot win by itself.
class SyncEvent {
  const SyncEvent({
    required this.eventId,
    required this.entityKey,
    required this.parentEventIds,
    required this.type,
  });

  final String eventId;
  final String entityKey;
  final Set<String> parentEventIds;
  final SyncEventType type;
}

enum SyncEventType { positionUpdated, shelfUpdated, bookRemoved }

class SyncMergeState {
  const SyncMergeState({
    this.appliedEventIds = const {},
    this.headsByEntity = const {},
  });

  final Set<String> appliedEventIds;
  final Map<String, List<SyncEvent>> headsByEntity;
}

class SyncMergeResult {
  const SyncMergeResult({
    required this.state,
    required this.status,
    this.conflict,
  });

  final SyncMergeState state;
  final SyncMergeStatus status;
  final SyncConflict? conflict;
}

enum SyncMergeStatus { applied, duplicate, stale }

class SyncConflict {
  const SyncConflict({required this.entityKey, required this.headEventIds});

  final String entityKey;
  final Set<String> headEventIds;
}

class ImmutableEventMerger {
  const ImmutableEventMerger();

  SyncMergeResult apply(SyncMergeState state, SyncEvent incoming) {
    if (state.appliedEventIds.contains(incoming.eventId)) {
      return SyncMergeResult(state: state, status: SyncMergeStatus.duplicate);
    }

    final previousHeads = List<SyncEvent>.of(
      state.headsByEntity[incoming.entityKey] ?? const [],
    );
    final previousIds = previousHeads.map((event) => event.eventId).toSet();
    final isDescendantOfAllHeads =
        previousIds.isNotEmpty &&
        previousIds.every(incoming.parentEventIds.contains);
    final isOlderThanCurrent = previousHeads.any(
      (head) => head.parentEventIds.contains(incoming.eventId),
    );

    final appliedIds = {...state.appliedEventIds, incoming.eventId};
    if (isOlderThanCurrent) {
      return SyncMergeResult(
        state: SyncMergeState(
          appliedEventIds: Set.unmodifiable(appliedIds),
          headsByEntity: state.headsByEntity,
        ),
        status: SyncMergeStatus.stale,
      );
    }

    final nextHeads = <SyncEvent>[];
    SyncConflict? conflict;
    if (previousHeads.isEmpty || isDescendantOfAllHeads) {
      nextHeads.add(incoming);
    } else {
      nextHeads.addAll(previousHeads);
      nextHeads.add(incoming);
      conflict = SyncConflict(
        entityKey: incoming.entityKey,
        headEventIds: Set.unmodifiable(
          nextHeads.map((event) => event.eventId).toSet(),
        ),
      );
    }

    final nextByEntity = Map<String, List<SyncEvent>>.of(state.headsByEntity)
      ..[incoming.entityKey] = List.unmodifiable(nextHeads);
    return SyncMergeResult(
      state: SyncMergeState(
        appliedEventIds: Set.unmodifiable(appliedIds),
        headsByEntity: Map.unmodifiable(nextByEntity),
      ),
      status: SyncMergeStatus.applied,
      conflict: conflict,
    );
  }
}
