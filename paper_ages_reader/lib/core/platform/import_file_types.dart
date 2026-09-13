import 'package:file_selector/file_selector.dart';

/// Extensions serve Android/desktop; iOS requires explicit Uniform Types.
abstract final class ImportFileTypes {
  static const books = XTypeGroup(
    label: '书籍文件',
    extensions: ['txt', 'pdf'],
    uniformTypeIdentifiers: ['public.plain-text', 'com.adobe.pdf'],
  );
  static const text = XTypeGroup(
    label: 'TXT',
    extensions: ['txt'],
    uniformTypeIdentifiers: ['public.plain-text'],
  );
  static const sources = XTypeGroup(
    label: 'Legado JSON',
    extensions: ['json'],
    uniformTypeIdentifiers: ['public.json'],
  );
  static const fonts = XTypeGroup(
    label: '字体',
    extensions: ['ttf', 'otf'],
    uniformTypeIdentifiers: ['public.truetype-font', 'public.opentype-font'],
  );
}
