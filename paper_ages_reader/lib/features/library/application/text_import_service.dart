import 'dart:convert';

import '../../reader_document/domain/normalized_text_document.dart';

class PickedTextFile {
  const PickedTextFile({required this.name, required this.bytes});

  final String name;
  final List<int> bytes;
}

abstract interface class TextFilePicker {
  Future<PickedTextFile?> pickTxt();
}

sealed class TextImportResult {
  const TextImportResult();
}

class TextImportCancelled extends TextImportResult {
  const TextImportCancelled();
}

class TextImportSucceeded extends TextImportResult {
  const TextImportSucceeded({required this.fileName, required this.document});

  final String fileName;
  final NormalizedTextDocument document;
}

class TextImportUnsupportedEncoding extends TextImportResult {
  const TextImportUnsupportedEncoding(this.fileName);

  final String fileName;
}

/// Import boundary. Persisting the picked original file and book record is the
/// repository adapter's responsibility; decoding is intentionally explicit so
/// malformed input cannot be silently presented as complete text.
class TextImportService {
  factory TextImportService({required TextFilePicker picker}) =>
      TextImportService._(picker);

  const TextImportService._(this._picker);

  final TextFilePicker _picker;

  Future<TextImportResult> pickAndNormalize() async {
    final file = await _picker.pickTxt();
    if (file == null) return const TextImportCancelled();
    try {
      return TextImportSucceeded(
        fileName: file.name,
        document: const TextNormalizer().normalize(utf8.decode(file.bytes)),
      );
    } on FormatException {
      return TextImportUnsupportedEncoding(file.name);
    }
  }
}
