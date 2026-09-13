import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/features/library/application/text_import_service.dart';

void main() {
  test('normalizes a selected UTF-8 TXT file', () async {
    final service = TextImportService(
      picker: _FakePicker(
        PickedTextFile(name: 'fixture.txt', bytes: utf8.encode('甲\r\n乙')),
      ),
    );

    final result = await service.pickAndNormalize();

    expect(result, isA<TextImportSucceeded>());
    expect(
      (result as TextImportSucceeded).document.blocks.map(
        (block) => block.text,
      ),
      ['甲', '乙'],
    );
  });

  test('does not treat malformed bytes as a complete import', () async {
    final service = TextImportService(
      picker: _FakePicker(
        const PickedTextFile(name: 'broken.txt', bytes: [0xff]),
      ),
    );

    expect(
      await service.pickAndNormalize(),
      isA<TextImportUnsupportedEncoding>(),
    );
  });

  test('keeps a cancelled picker distinct from import failure', () async {
    final service = TextImportService(picker: _FakePicker(null));

    expect(await service.pickAndNormalize(), isA<TextImportCancelled>());
  });
}

class _FakePicker implements TextFilePicker {
  const _FakePicker(this.file);

  final PickedTextFile? file;

  @override
  Future<PickedTextFile?> pickTxt() async => file;
}
