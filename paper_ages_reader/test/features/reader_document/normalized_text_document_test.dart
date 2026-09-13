import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/features/reader_document/domain/normalized_text_document.dart';

void main() {
  const normalizer = TextNormalizer();
  const resolver = TextAnchorResolver();
  const chunker = GraphemeSafeChunker();

  test(
    'removes BOM and normalizes line endings without dropping empty blocks',
    () {
      final document = normalizer.normalize('\uFEFF第一行\r\n\r第二行\n');

      expect(document.blocks.map((block) => block.text), [
        '第一行',
        '',
        '第二行',
        '',
      ]);
      expect(document.normalizationVersion, textNormalizationVersion);
    },
  );

  test('anchor does not land in the middle of an emoji surrogate pair', () {
    final document = normalizer.normalize('甲😀乙');
    final anchor = resolver.create(
      editionId: 'edition-1',
      document: document,
      blockIndex: 0,
      requestedOffsetUtf16: 2,
    );

    expect(anchor.offsetUtf16, 1);
    expect(anchor.contextHash, isNotEmpty);
  });

  test('grapheme chunks round-trip mixed text without splitting clusters', () {
    const text = '中文😀e\u0301https://example.test/very-long-path';
    final chunks = chunker.split(text, maxUtf16: 5);

    expect(chunks.join(), text);
    expect(chunks, everyElement(isNotEmpty));
    expect(chunks.where((chunk) => chunk.contains('😀')), hasLength(1));
    expect(chunks.where((chunk) => chunk.contains('e\u0301')), hasLength(1));
  });

  test('empty input remains a recoverable empty block', () {
    final document = normalizer.normalize('');

    expect(document.blocks, hasLength(1));
    expect(document.blocks.single.text, isEmpty);
  });
}
