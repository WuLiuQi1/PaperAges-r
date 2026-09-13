import '../data/persistent_sync_outbox.dart';
import '../domain/immutable_event_merge.dart';

typedef RemoteEventLoader = Future<List<SyncEvent>> Function();
typedef RemoteEventApplier = Future<void> Function(SyncEvent event);
typedef OutboxUploader = Future<void> Function(SyncEvent event);

class SyncRoundResult {
  const SyncRoundResult({
    required this.mergeState,
    required this.appliedRemoteIds,
    required this.deferredRemoteIds,
    required this.conflicts,
    required this.uploadedLocalIds,
    required this.uploadFailures,
  });

  final SyncMergeState mergeState;
  final Set<String> appliedRemoteIds;
  final Set<String> deferredRemoteIds;
  final List<SyncConflict> conflicts;
  final Set<String> uploadedLocalIds;
  final Map<String, Object> uploadFailures;
}

/// Runs one recoverable synchronization pass. Ordering is based solely on
/// immutable parents, never device wall clocks or reading-position magnitude.
class SyncRoundCoordinator {
  SyncRoundCoordinator({
    required this.outbox,
    required this.loadRemote,
    required this.applyRemote,
    required this.upload,
    ImmutableEventMerger? merger,
  }) : _merger = merger ?? const ImmutableEventMerger();

  final PersistentSyncOutbox outbox;
  final RemoteEventLoader loadRemote;
  final RemoteEventApplier applyRemote;
  final OutboxUploader upload;
  final ImmutableEventMerger _merger;

  Future<SyncRoundResult> run({
    SyncMergeState initial = const SyncMergeState(),
  }) async {
    var state = initial;
    final pending = {
      for (final event in await loadRemote()) event.eventId: event,
    };
    final knownIds = {...initial.appliedEventIds, ...outbox.appliedEventIds};
    final applied = <String>{};
    final conflicts = <SyncConflict>[];

    var progressed = true;
    while (progressed) {
      progressed = false;
      for (final event in pending.values.toList()) {
        if (knownIds.contains(event.eventId)) {
          pending.remove(event.eventId);
          progressed = true;
          continue;
        }
        if (!event.parentEventIds.every(knownIds.contains)) continue;
        final merged = _merger.apply(state, event);
        state = merged.state;
        await applyRemote(event);
        await outbox.markApplied(event.eventId);
        knownIds.add(event.eventId);
        applied.add(event.eventId);
        if (merged.conflict != null) conflicts.add(merged.conflict!);
        pending.remove(event.eventId);
        progressed = true;
      }
    }

    final uploaded = <String>{};
    final failures = <String, Object>{};
    for (final event in outbox.pending) {
      try {
        await upload(event);
        await outbox.markUploaded(event.eventId);
        uploaded.add(event.eventId);
      } catch (error) {
        failures[event.eventId] = error;
      }
    }
    return SyncRoundResult(
      mergeState: state,
      appliedRemoteIds: Set.unmodifiable(applied),
      deferredRemoteIds: Set.unmodifiable(pending.keys),
      conflicts: List.unmodifiable(conflicts),
      uploadedLocalIds: Set.unmodifiable(uploaded),
      uploadFailures: Map.unmodifiable(failures),
    );
  }
}
