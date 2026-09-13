import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/storage/app_database.dart';
import '../../reader_document/presentation/pdf_reader_screen.dart';
import '../../reader_document/presentation/reader_document_screen.dart';
import '../../downloads/presentation/downloads_screen.dart';
import '../../source_engine/presentation/source_management_screen.dart';
import '../../source_engine/presentation/network_shelf_screen.dart';
import '../../statistics/presentation/reading_statistics_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../application/document_decoder.dart';
import '../data/file_selector_book_picker.dart';
import '../data/local_library_repository.dart';
import '../domain/library_book.dart';
import 'book_cover.dart';

class LocalLibraryScreen extends StatefulWidget {
  const LocalLibraryScreen({
    super.key,
    this.repository,
    this.initialSearch = false,
  });
  final bool initialSearch;
  final LocalLibraryRepository? repository;
  @override
  State<LocalLibraryScreen> createState() => _LocalLibraryScreenState();
}

class _LocalLibraryScreenState extends State<LocalLibraryScreen> {
  late final Future<LocalLibraryRepository> _repositoryFuture;
  final _searchController = TextEditingController();
  var _importing = false;
  var _searching = false;
  var _listMode = false;

  @override
  void initState() {
    super.initState();
    _searching = widget.initialSearch;
    _repositoryFuture = widget.repository != null
        ? Future.value(widget.repository)
        : AppDatabase.defaults().then(LocalLibraryRepository.new);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
      title: _searching
          ? TextField(
              key: const Key('library-search-field'),
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '搜索本地书库',
                border: InputBorder.none,
              ),
              onChanged: (_) => setState(() {}),
            )
          : const Text('书库'),
      actions: [
        IconButton(
          tooltip: _searching ? '取消搜索' : (_listMode ? '网格视图' : '列表视图'),
          onPressed: () => setState(() {
            if (_searching) {
              _searching = false;
              _searchController.clear();
            } else {
              _listMode = !_listMode;
            }
          }),
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
          ),
          icon: Icon(
            _searching
                ? Icons.close
                : (_listMode
                      ? Icons.grid_view_rounded
                      : Icons.format_list_bulleted),
          ),
        ),
        PopupMenuButton<String>(
          tooltip: '书库更多操作',
          icon: const Icon(Icons.more_horiz),
          onSelected: (value) async {
            if (value == 'search') {
              setState(() => _searching = true);
              return;
            }
            if (value == 'import') {
              final repository = await _repositoryFuture;
              if (mounted && !_importing) await _importBook(repository);
              return;
            }
            final Widget page = switch (value) {
              'sources' => const SourceManagementScreen(),
              'downloads' => const DownloadsScreen(),
              'network' => const NetworkShelfScreen(),
              'statistics' => const ReadingStatisticsScreen(),
              _ => const SettingsScreen(),
            };
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'import', child: Text('导入书籍')),
            PopupMenuItem(value: 'search', child: Text('搜索本地书库')),
            PopupMenuItem(value: 'network', child: Text('网络书架')),
            PopupMenuItem(value: 'sources', child: Text('书源管理')),
            PopupMenuItem(value: 'downloads', child: Text('下载任务')),
            PopupMenuItem(value: 'statistics', child: Text('阅读统计')),
            PopupMenuItem(value: 'settings', child: Text('设置')),
          ],
        ),
        const SizedBox(width: 8),
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
            final query = _searchController.text.trim().toLowerCase();
            final books = snapshot.data!
                .where(
                  (book) =>
                      query.isEmpty || book.title.toLowerCase().contains(query),
                )
                .toList(growable: false);
            if (books.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.menu_book_outlined,
                      size: 44,
                      color: Color(0xFFC5C5C7),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      query.isEmpty ? '你的书库' : '没有匹配的本地书籍',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (query.isEmpty) ...[
                      const SizedBox(height: 8),
                      const Text('添加 TXT 或 PDF，开始阅读'),
                      TextButton(
                        key: const Key('pick-book-button'),
                        onPressed: _importing
                            ? null
                            : () => _importBook(repository),
                        child: Text(_importing ? '正在导入…' : '导入书籍'),
                      ),
                    ],
                    const SizedBox(height: 100),
                  ],
                ),
              );
            }
            if (_listMode) {
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(32, 24, 32, 130),
                itemCount: books.length,
                separatorBuilder: (_, _) => const Divider(height: 32),
                itemBuilder: (context, index) {
                  final book = books[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: SizedBox(width: 42, child: BookCover(book: book)),
                    title: Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(repository.progressLabel(book.id)),
                    trailing: IconButton(
                      tooltip: '${book.title}的更多操作',
                      icon: const Icon(Icons.more_horiz),
                      onPressed: () => showBookActions(
                        context,
                        book,
                        () => _openBook(book, repository),
                      ),
                    ),
                    onTap: () => _openBook(book, repository),
                  );
                },
              );
            }
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(32, 28, 32, 0),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisExtent:
                          (MediaQuery.sizeOf(context).width - 90) / 1.4 + 44,
                      crossAxisSpacing: 26,
                      mainAxisSpacing: 24,
                    ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final book = books[index];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () => _openBook(book, repository),
                            onLongPress: () => showBookActions(
                              context,
                              book,
                              () => _openBook(book, repository),
                            ),
                            child: Semantics(
                              button: true,
                              label: book.title,
                              child: BookCover(book: book),
                            ),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  repository.progressLabel(book.id),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 44,
                                height: 36,
                                child: IconButton(
                                  tooltip: '${book.title}的更多操作',
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(Icons.more_horiz, size: 22),
                                  onPressed: () => showBookActions(
                                    context,
                                    book,
                                    () => _openBook(book, repository),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    }, childCount: books.length),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(32, 38, 32, 130),
                    child: Text(
                      '${books.length} 本书',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    ),
  );
}
