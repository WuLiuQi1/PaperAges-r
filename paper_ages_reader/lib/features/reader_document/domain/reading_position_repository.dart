import 'normalized_text_document.dart';

class ReadingPosition {
  const ReadingPosition({
    required this.bookId,
    required this.anchor,
    required this.localRevision,
  });

  final String bookId;
  final TextAnchor anchor;
  final int localRevision;
}

sealed class CommitPositionResult {
  const CommitPositionResult();
}

class PositionCommitted extends CommitPositionResult {
  const PositionCommitted(this.position);

  final ReadingPosition position;
}

class PositionConflict extends CommitPositionResult {
  const PositionConflict(this.current);

  final ReadingPosition? current;
}

abstract interface class ReadingPositionRepository {
  ReadingPosition? read(String bookId);
  CommitPositionResult commit({
    required String bookId,
    required TextAnchor anchor,
    required int expectedLocalRevision,
  });
}

/// Test implementation of the one-authority repository contract. The durable
/// database adapter must preserve this compare-and-swap behavior in a
/// transaction rather than allowing page widgets to write their own copies.
class InMemoryReadingPositionRepository implements ReadingPositionRepository {
  final _positions = <String, ReadingPosition>{};

  @override
  ReadingPosition? read(String bookId) => _positions[bookId];

  @override
  CommitPositionResult commit({
    required String bookId,
    required TextAnchor anchor,
    required int expectedLocalRevision,
  }) {
    final current = _positions[bookId];
    final actualRevision = current?.localRevision ?? 0;
    if (actualRevision != expectedLocalRevision) {
      return PositionConflict(current);
    }
    final next = ReadingPosition(
      bookId: bookId,
      anchor: anchor,
      localRevision: actualRevision + 1,
    );
    _positions[bookId] = next;
    return PositionCommitted(next);
  }
}
