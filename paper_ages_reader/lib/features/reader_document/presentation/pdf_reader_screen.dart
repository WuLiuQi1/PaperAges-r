import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../library/domain/library_book.dart';

class PdfReaderScreen extends StatelessWidget {
  const PdfReaderScreen({super.key, required this.book});

  final LibraryBook book;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(book.title)),
    body: File(book.filePath).existsSync()
        ? PdfViewer.file(book.filePath)
        : const Center(child: Text('原始 PDF 文件不存在，请重新导入此书文件。')),
  );
}
