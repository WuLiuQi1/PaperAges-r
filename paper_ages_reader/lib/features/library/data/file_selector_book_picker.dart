import 'package:file_selector/file_selector.dart';

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
      acceptedTypeGroups: const [
        XTypeGroup(label: '书籍文件', extensions: ['txt', 'pdf']),
      ],
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
      acceptedTypeGroups: const [
        XTypeGroup(label: '字体', extensions: ['ttf', 'otf']),
      ],
    );
    if (file == null) return null;
    return PickedBookFile(
      name: file.name,
      bytes: await file.readAsBytes(),
      isPdf: false,
    );
  }
}
