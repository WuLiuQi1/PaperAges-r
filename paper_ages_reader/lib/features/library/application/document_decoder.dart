import 'dart:convert';
import 'dart:typed_data';

import 'package:charset_converter/charset_converter.dart';

class DecodedText {
  const DecodedText({required this.text, required this.encoding});

  final String text;
  final String encoding;
}

/// Prefer a strict UTF-8 decode. The Chinese legacy fallbacks intentionally
/// stay explicit and are recorded with the book, so a later renderer does not
/// guess a different encoding for the same file.
class DocumentDecoder {
  const DocumentDecoder();

  Future<DecodedText> decodeText(List<int> bytes) async {
    try {
      return DecodedText(text: utf8.decode(bytes), encoding: 'utf-8');
    } on FormatException {
      final data = Uint8List.fromList(bytes);
      for (final charset in const ['GB18030', 'GBK', 'Big5']) {
        try {
          final decoded = await CharsetConverter.decode(charset, data);
          if (_looksLikeText(decoded)) {
            return DecodedText(text: decoded, encoding: charset.toLowerCase());
          }
        } catch (_) {
          // A platform codec can be unavailable; try the next documented
          // fallback rather than replacing content with U+FFFD.
        }
      }
      throw const FormatException('Unsupported or damaged text encoding');
    }
  }

  bool _looksLikeText(String value) {
    if (value.trim().isEmpty) return true;
    final controls = value.runes
        .where((rune) => rune < 32 && rune != 9 && rune != 10 && rune != 13)
        .length;
    return controls * 100 < value.runes.length * 2;
  }
}
