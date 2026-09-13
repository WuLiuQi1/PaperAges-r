import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/features/reader_document/domain/normalized_text_document.dart';
import 'package:paper_ages_reader/features/reader_document/domain/reading_position_repository.dart';

void main() {
  TextAnchor anchor(int offset) => TextAnchor(
    editionId: 'edition',
    blockId: 'block',
    offsetUtf16: offset,
    contextHash: 'hash',
    normalizationVersion: 1,
  );

  test('commits a single authoritative position with revisions', () {
    final repository = InMemoryReadingPositionRepository();
    final result = repository.commit(
      bookId: 'book',
      anchor: anchor(4),
      expectedLocalRevision: 0,
    );

    expect(result, isA<PositionCommitted>());
    expect(repository.read('book')!.localRevision, 1);
  });

  test('rejects a stale write rather than losing newer reading progress', () {
    final repository = InMemoryReadingPositionRepository();
    repository.commit(
      bookId: 'book',
      anchor: anchor(4),
      expectedLocalRevision: 0,
    );

    final stale = repository.commit(
      bookId: 'book',
      anchor: anchor(1),
      expectedLocalRevision: 0,
    );

    expect(stale, isA<PositionConflict>());
    expect(repository.read('book')!.anchor.offsetUtf16, 4);
  });
}
