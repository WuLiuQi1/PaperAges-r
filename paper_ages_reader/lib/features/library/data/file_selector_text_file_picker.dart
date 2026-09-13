import 'package:file_selector/file_selector.dart';

import '../../../core/platform/import_file_types.dart';

import '../application/text_import_service.dart';

class FileSelectorTextFilePicker implements TextFilePicker {
  const FileSelectorTextFilePicker();

  @override
  Future<PickedTextFile?> pickTxt() async {
    final file = await openFile(
      acceptedTypeGroups: const [ImportFileTypes.text],
    );
    if (file == null) return null;
    return PickedTextFile(name: file.name, bytes: await file.readAsBytes());
  }
}
