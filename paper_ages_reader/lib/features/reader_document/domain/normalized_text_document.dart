import 'package:characters/characters.dart';

const textNormalizationVersion = 1;

class NormalizedTextDocument {
  const NormalizedTextDocument({
    required this.normalizationVersion,
    required this.blocks,
  });

  final int normalizationVersion;
  final List<TextBlock> blocks;
}

class TextBlock {
  const TextBlock({required this.id, required this.text, required this.hash});

  final String id;
  final String text;
  final String hash;
}

/// Normalizes only transport artifacts shared by TXT import, layout and TTS.
/// It does not strip content, collapse paragraphs or make display-only changes.
class TextNormalizer {
  const TextNormalizer();

  NormalizedTextDocument normalize(String rawText) {
    var normalized = rawText;
    if (normalized.startsWith('\uFEFF')) {
      normalized = normalized.substring(1);
    }
    normalized = normalized.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rawBlocks = normalized.split('\n');
    final blocks = <TextBlock>[];
    for (var index = 0; index < rawBlocks.length; index++) {
      final text = rawBlocks[index];
      final hash = _stableHash(text);
      blocks.add(TextBlock(id: 'b$index-$hash', text: text, hash: hash));
    }
    return NormalizedTextDocument(
      normalizationVersion: textNormalizationVersion,
      blocks: List.unmodifiable(blocks),
    );
  }
}

class TextAnchor {
  const TextAnchor({
    required this.editionId,
    required this.blockId,
    required this.offsetUtf16,
    required this.contextHash,
    required this.normalizationVersion,
  });

  final String editionId;
  final String blockId;
  final int offsetUtf16;
  final String contextHash;
  final int normalizationVersion;
}

class TextAnchorResolver {
  const TextAnchorResolver();

  TextAnchor create({
    required String editionId,
    required NormalizedTextDocument document,
    required int blockIndex,
    required int requestedOffsetUtf16,
  }) {
    final block = document.blocks[blockIndex];
    final offset = _snapToClusterBoundary(block.text, requestedOffsetUtf16);
    return TextAnchor(
      editionId: editionId,
      blockId: block.id,
      offsetUtf16: offset,
      contextHash: _contextHash(block.text, offset),
      normalizationVersion: document.normalizationVersion,
    );
  }

  int _snapToClusterBoundary(String text, int requestedOffsetUtf16) {
    final target = requestedOffsetUtf16.clamp(0, text.length);
    var offset = 0;
    for (final cluster in text.characters) {
      final next = offset + cluster.length;
      if (target < next) return offset;
      offset = next;
    }
    return offset;
  }

  String _contextHash(String text, int offset) {
    final start = (offset - 16).clamp(0, text.length);
    final end = (offset + 16).clamp(0, text.length);
    return _stableHash(text.substring(start, end));
  }
}

/// Splits text into logical pieces no longer than [maxUtf16] without splitting
/// a user-visible character. Layout uses these only as work units; it still
/// determines visual line/page boundaries with its actual viewport and font.
class GraphemeSafeChunker {
  const GraphemeSafeChunker();

  List<String> split(String text, {required int maxUtf16}) {
    if (maxUtf16 <= 0) {
      throw ArgumentError.value(maxUtf16, 'maxUtf16', 'must be positive');
    }
    if (text.isEmpty) return const [''];

    final chunks = <String>[];
    var buffer = StringBuffer();
    var length = 0;
    for (final cluster in text.characters) {
      if (length > 0 && length + cluster.length > maxUtf16) {
        chunks.add(buffer.toString());
        buffer = StringBuffer();
        length = 0;
      }
      buffer.write(cluster);
      length += cluster.length;
    }
    if (length > 0) chunks.add(buffer.toString());
    return List.unmodifiable(chunks);
  }
}

String _stableHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
