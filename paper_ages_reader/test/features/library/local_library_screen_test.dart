import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/features/library/application/text_import_service.dart';
import 'package:paper_ages_reader/features/library/presentation/local_library_screen.dart';

void main() {
  testWidgets('opens a preview for an imported TXT document', (tester) async {
    final service = TextImportService(
      picker: _Picker(
        PickedTextFile(name: 'fixture.txt', bytes: utf8.encode('可阅读正文')),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: LocalLibraryScreen(importService: service)),
    );

    await tester.tap(find.byKey(const Key('pick-txt-button')));
    await tester.pumpAndSettle();

    expect(find.text('fixture.txt'), findsOneWidget);
    expect(find.text('可阅读正文'), findsOneWidget);
  });

  testWidgets('shows a clear result when the picker is cancelled', (
    tester,
  ) async {
    final service = TextImportService(picker: _Picker(null));
    await tester.pumpWidget(
      MaterialApp(home: LocalLibraryScreen(importService: service)),
    );

    await tester.tap(find.byKey(const Key('pick-txt-button')));
    await tester.pumpAndSettle();

    expect(find.text('未选择文件'), findsOneWidget);
  });
}

class _Picker implements TextFilePicker {
  const _Picker(this.file);

  final PickedTextFile? file;

  @override
  Future<PickedTextFile?> pickTxt() async => file;
}
