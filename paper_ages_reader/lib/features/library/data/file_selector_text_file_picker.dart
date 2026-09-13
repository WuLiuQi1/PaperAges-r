import 'package:file_selector/file_selector.dart';

import '../application/text_import_service.dart';

class FileSelectorTextFilePicker implements TextFilePicker {
  const FileSelectorTextFilePicker();

  @override
  Future<PickedTextFile?> pickTxt() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'TXT', extensions: ['txt']),
      ],
    );
    if (file == null) return null;
    return PickedTextFile(name: file.name, bytes: await file.readAsBytes());
  }
}
