import 'dart:convert';

import 'package:crypto/crypto.dart';

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
    this.schemaVersion = 1,
    this.deviceId = '',
    this.deviceSeq = 0,
    this.payload = const {},
    this.payloadHash = '',
  });

  final String eventId;
  final String entityKey;
  final Set<String> parentEventIds;
  final SyncEventType type;
  final int schemaVersion;
  final String deviceId;
  final int deviceSeq;
  final Map<String, Object?> payload;
  final String payloadHash;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'eventId': eventId,
    'deviceId': deviceId,
    'deviceSeq': deviceSeq,
    'entityKey': entityKey,
    'parentEventIds': parentEventIds.toList()..sort(),
    'type': type.name,
    'payload': payload,
    'payloadHash': payloadHash,
  };
}

enum SyncEventType { positionUpdated, shelfUpdated, bookRemoved }

/// Validates an event before it can be applied or uploaded. Hashes are over a
/// canonical JSON payload, not over transport bytes or wall-clock metadata.
class SyncEventCodec {
  const SyncEventCodec();

  static const schemaVersion = 1;

  String payloadHash(Map<String, Object?> payload) =>
      sha256.convert(utf8.encode(_canonical(payload))).toString();

  SyncEvent create({
    required String eventId,
    required String deviceId,
    required int deviceSeq,
    required String entityKey,
    required Set<String> parentEventIds,
    required SyncEventType type,
    required Map<String, Object?> payload,
  }) => SyncEvent(
    eventId: eventId,
    deviceId: deviceId,
    deviceSeq: deviceSeq,
    entityKey: entityKey,
    parentEventIds: Set.unmodifiable(parentEventIds),
    type: type,
    payload: Map.unmodifiable(payload),
    payloadHash: payloadHash(payload),
  );

  SyncEvent decode(Map<String, Object?> json) {
    if (json['schemaVersion'] != schemaVersion) {
      throw const FormatException('Unsupported sync event schema');
    }
    final payload = json['payload'];
    final parents = json['parentEventIds'];
    final typeName = json['type'];
    if (payload is! Map || parents is! List || typeName is! String) {
      throw const FormatException('Malformed sync event');
    }
    final type = SyncEventType.values.where((value) => value.name == typeName);
    if (type.isEmpty ||
        json['eventId'] is! String ||
        json['deviceId'] is! String ||
        json['deviceSeq'] is! int ||
        json['entityKey'] is! String ||
        json['payloadHash'] is! String ||
        !parents.every((value) => value is String)) {
      throw const FormatException('Malformed sync event');
    }
    final event = SyncEvent(
      eventId: json['eventId']! as String,
      deviceId: json['deviceId']! as String,
      deviceSeq: json['deviceSeq']! as int,
      entityKey: json['entityKey']! as String,
      parentEventIds: Set<String>.from(parents),
      type: type.single,
      payload: Map<String, Object?>.from(payload),
      payloadHash: json['payloadHash']! as String,
    );
    if (event.payloadHash != payloadHash(event.payload)) {
      throw const FormatException('Sync event payload hash mismatch');
    }
    return event;
  }

  String _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return '{${keys.map((key) => '${jsonEncode(key)}:${_canonical(value[key])}').join(',')}}';
    }
    if (value is List) return '[${value.map(_canonical).join(',')}]';
    return jsonEncode(value);
  }
}

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
