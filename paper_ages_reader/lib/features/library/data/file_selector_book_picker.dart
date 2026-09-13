import 'package:file_selector/file_selector.dart';

import '../../../core/platform/import_file_types.dart';

class PickedBookFile {
  const PickedBookFile({
    required this.name,
    required this.bytes,
    required this.isPdf,
  });

  final String name;
  final List<int> bytes;
  final bool isPdf;
}

class FileSelectorBookPicker {
  const FileSelectorBookPicker();

  Future<PickedBookFile?> pick() async {
    final file = await openFile(
      acceptedTypeGroups: const [ImportFileTypes.books],
    );
    if (file == null) return null;
    return PickedBookFile(
      name: file.name,
      bytes: await file.readAsBytes(),
      isPdf: file.name.toLowerCase().endsWith('.pdf'),
    );
  }

  Future<PickedBookFile?> pickFont() async {
    final file = await openFile(
      acceptedTypeGroups: const [ImportFileTypes.fonts],
    );
    if (file == null) return null;
    return PickedBookFile(
      name: file.name,
      bytes: await file.readAsBytes(),
      isPdf: false,
    );
  }
}
