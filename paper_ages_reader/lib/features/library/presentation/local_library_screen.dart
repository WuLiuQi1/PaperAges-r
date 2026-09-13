import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/storage/app_database.dart';
import '../../reader_document/presentation/pdf_reader_screen.dart';
import '../../reader_document/presentation/reader_document_screen.dart';
import '../../reader_layout/presentation/page_turn_spike.dart';
import '../application/document_decoder.dart';
import '../data/file_selector_book_picker.dart';
import '../data/local_library_repository.dart';
import '../domain/library_book.dart';

class LocalLibraryScreen extends StatefulWidget {
  const LocalLibraryScreen({super.key, this.repository});
  final LocalLibraryRepository? repository;
  @override
  State<LocalLibraryScreen> createState() => _LocalLibraryScreenState();
}

class _LocalLibraryScreenState extends State<LocalLibraryScreen> {
  late final Future<LocalLibraryRepository> _repositoryFuture;
  var _importing = false;

  @override
  void initState() {
    super.initState();
    _repositoryFuture = widget.repository != null
        ? Future.value(widget.repository)
        : AppDatabase.defaults().then(LocalLibraryRepository.new);
  }

  Future<void> _importBook(LocalLibraryRepository repository) async {
    setState(() => _importing = true);
    try {
      final file = await const FileSelectorBookPicker().pick();
      if (file == null) return;
      final kind = file.isPdf ? LibraryBookKind.pdf : LibraryBookKind.text;
      String? encoding;
      var storedBytes = file.bytes;
      if (kind == LibraryBookKind.text) {
        final decoded = await const DocumentDecoder().decodeText(file.bytes);
        encoding = decoded.encoding;
        storedBytes = utf8.encode(decoded.text);
      }
      final book = await repository.importFile(
        title: file.name.replaceFirst(
          RegExp(r'\.(txt|pdf)$', caseSensitive: false),
          '',
        ),
        kind: kind,
        bytes: storedBytes,
        encoding: encoding,
      );
      if (mounted) await _openBook(book, repository);
    } on FormatException {
      if (mounted) _show('无法识别文本编码：请转换为 UTF-8、GB18030、GBK 或 Big5 后重试。');
    } catch (error) {
      if (mounted) _show('导入失败：$error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _openBook(LibraryBook book, LocalLibraryRepository repository) =>
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => book.kind == LibraryBookKind.pdf
              ? PdfReaderScreen(book: book)
              : ReaderDocumentScreen(book: book, repository: repository),
        ),
      );
  void _show(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Paper Ages'),
      actions: [
        IconButton(
          tooltip: '交互样板',
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const PageTurnSpike())),
          icon: const Icon(Icons.science_outlined),
        ),
      ],
    ),
    body: FutureBuilder<LocalLibraryRepository>(
      future: _repositoryFuture,
      builder: (context, ready) {
        if (!ready.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final repository = ready.data!;
        return StreamBuilder<List<LibraryBook>>(
          stream: repository.watchBooks(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('书库无法读取：${snapshot.error}'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final books = snapshot.data!;
            if (books.isEmpty) {
              return const Center(child: Text('导入 TXT 或 PDF 开始阅读'));
            }
            return GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: .72,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: books.length,
              itemBuilder: (context, index) {
                final book = books[index];
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _openBook(book, repository),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Center(
                              child: Icon(
                                book.kind == LibraryBookKind.pdf
                                    ? Icons.picture_as_pdf_outlined
                                    : Icons.menu_book_outlined,
                                size: 62,
                              ),
                            ),
                          ),
                          Text(
                            book.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            book.kind == LibraryBookKind.pdf
                                ? '原版 PDF'
                                : 'TXT · ${book.encoding ?? 'UTF-8'}',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    ),
    floatingActionButton: FutureBuilder<LocalLibraryRepository>(
      future: _repositoryFuture,
      builder: (context, ready) => FloatingActionButton.extended(
        key: const Key('pick-book-button'),
        onPressed: _importing || !ready.hasData
            ? null
            : () => _importBook(ready.data!),
        icon: _importing
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: const Text('导入书籍'),
      ),
    ),
  );
}
