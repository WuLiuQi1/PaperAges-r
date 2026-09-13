import 'dart:math' as math;

import 'package:characters/characters.dart';
import 'package:flutter/painting.dart';

import '../domain/normalized_text_document.dart';

class TextPage {
  const TextPage(this.start, this.end, this.text);
  final int start;
  final int end;
  final String text;
}

/// Layout only a bounded window around the reading anchor, never an entire novel.
/// Offsets are UTF-16 offsets into the normalized document, not page numbers.
class ViewportPaginator {
  ViewportPaginator(NormalizedTextDocument document)
    : text = document.blocks.map((block) => block.text).join('\n') {
    var offset = 0;
    for (final block in document.blocks) {
      blockStarts.add(offset);
      offset += block.text.length + 1;
    }
  }

  final String text;
  final List<int> blockStarts = [];
  static const window = 16384;

  int offsetFor(int block, int offset) {
    final index = block.clamp(0, blockStarts.length - 1);
    final end = index + 1 < blockStarts.length
        ? blockStarts[index + 1] - 1
        : text.length;
    return (blockStarts[index] + offset).clamp(blockStarts[index], end);
  }

  ({int block, int offset}) anchorFor(int offset) {
    var low = 0;
    var high = blockStarts.length - 1;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (blockStarts[middle] <= offset) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return (block: low, offset: offset - blockStarts[low]);
  }

  TextPage page(int start, Size size, TextStyle style, TextScaler scaler) {
    final end = math.min(text.length, start + window);
    var candidate = text.substring(start, end);
    // Discard the final cluster when the window cuts through a grapheme.
    if (end < text.length) {
      candidate = candidate.characters.skipLast(1).toString();
    }
    if (candidate.isEmpty && start < text.length) {
      candidate = text.substring(start).characters.first;
    }
    final boundaries = [0];
    for (final cluster in candidate.characters) {
      boundaries.add(boundaries.last + cluster.length);
    }
    final count = _fit(candidate, boundaries, size, style, scaler);
    final length = boundaries[count];
    return TextPage(start, start + length, candidate.substring(0, length));
  }

  TextPage previous(int end, Size size, TextStyle style, TextScaler scaler) {
    var start = math.max(0, end - window);
    var candidate = text.substring(start, end);
    if (start > 0) {
      final first = candidate.characters.first.length;
      start += first;
      candidate = candidate.substring(first);
    }
    final boundaries = [0];
    for (final cluster in candidate.characters) {
      boundaries.add(boundaries.last + cluster.length);
    }
    final count = _fit(
      candidate,
      boundaries,
      size,
      style,
      scaler,
      suffix: true,
    );
    final from = boundaries[boundaries.length - 1 - count];
    return TextPage(start + from, end, candidate.substring(from));
  }

  int _fit(
    String value,
    List<int> boundaries,
    Size size,
    TextStyle style,
    TextScaler scaler, {
    bool suffix = false,
  }) {
    var low = 0;
    var high = boundaries.length - 1;
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.justify,
      textScaler: scaler,
    );
    try {
      while (low < high) {
        final middle = (low + high + 1) ~/ 2;
        final sample = suffix
            ? value.substring(boundaries[boundaries.length - 1 - middle])
            : value.substring(0, boundaries[middle]);
        painter.text = TextSpan(text: sample, style: style);
        painter.layout(maxWidth: math.max(1, size.width));
        if (painter.height <= size.height) {
          low = middle;
        } else {
          high = middle - 1;
        }
      }
    } finally {
      painter.dispose();
    }
    // Always advance even on an exceptionally small viewport.
    return math.max(low, boundaries.length > 1 ? 1 : 0);
  }
}
