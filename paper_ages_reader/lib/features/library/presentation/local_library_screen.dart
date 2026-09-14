import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/storage/app_database.dart';
import '../../reader_document/presentation/pdf_reader_screen.dart';
import '../../reader_document/presentation/reader_document_screen.dart';
import '../../downloads/presentation/downloads_screen.dart';
import '../../source_engine/presentation/source_management_screen.dart';
import '../../source_engine/presentation/network_shelf_screen.dart';
import '../../source_engine/data/local_source_repository.dart';
import '../../source_engine/data/network_shelf_repository.dart';
import '../../source_engine/data/persistent_source_binding_store.dart';
import '../../source_engine/domain/source_engine.dart';
import '../../source_engine/presentation/source_search_screen.dart';
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

  Future<void> _openNetworkBook(
    NetworkShelfBook book,
    AppDatabase database,
  ) async {
    final bookId = NetworkShelfRepository.bookIdFor(
      sourceUrl: book.sourceUrl,
      locator: book.locator,
    );
    final binding = PersistentSourceBindingStore(database).bindingFor(bookId);
    final source = await LocalSourceRepository(database)
        .findByUrl(binding?.sourceUrl ?? book.sourceUrl);
    if (!mounted) return;
    if (source == null) {
      _show('此书源未配置，无法打开网络书籍。');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => binding == null
            ? NetworkBookScreen(
                source: source,
                book: NetworkBook(
                  sourceUrl: book.sourceUrl,
                  title: book.title,
                  author: book.author,
                  locator: book.locator,
                ),
              )
            : NetworkChapterScreen(
                source: source,
                bookTitle: book.title,
                bookId: bookId,
                chapter: SourceChapter(
                  key: binding.chapterKey,
                  title: book.title,
                  locator: binding.locator,
                  ordinal: 0,
                  bookLocator: book.locator,
                ),
              ),
      ),
    );
  }

  void _show(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Future<String> _networkSourceName(
    NetworkShelfBook book,
    AppDatabase database,
  ) async {
    final bookId = NetworkShelfRepository.bookIdFor(
      sourceUrl: book.sourceUrl,
      locator: book.locator,
    );
    final binding = PersistentSourceBindingStore(database).bindingFor(bookId);
    final source = await LocalSourceRepository(database)
        .findByUrl(binding?.sourceUrl ?? book.sourceUrl);
    return source?.name ?? Uri.tryParse(book.sourceUrl)?.host ?? '在线书源';
  }

  Future<bool> _confirmDelete(String title, {required bool localFile}) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(localFile ? '删除本地书籍？' : '移出书库？'),
          content: Text(
            localFile
                ? '“$title”及其导入文件和阅读进度将从此设备删除。'
                : '“$title”将从书库移除，已下载的章节缓存不会立即清除。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(localFile ? '删除' : '移出'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _deleteLocal(
    LibraryBook book,
    LocalLibraryRepository repository,
  ) async {
    if (!await _confirmDelete(book.title, localFile: true)) return;
    try {
      await repository.removeBook(book);
      if (mounted) _show('已删除“${book.title}”');
    } catch (error) {
      if (mounted) _show('删除失败：$error');
    }
  }

  Future<void> _deleteNetwork(
    NetworkShelfBook book,
    AppDatabase database,
  ) async {
    if (!await _confirmDelete(book.title, localFile: false)) return;
    try {
      await NetworkShelfRepository(database).remove(book);
      if (mounted) _show('已将“${book.title}”移出书库');
    } catch (error) {
      if (mounted) _show('移出失败：$error');
    }
  }

  Future<void> _showNetworkActions(
    NetworkShelfBook book,
    AppDatabase database,
  ) => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(book.title, maxLines: 2),
            subtitle: FutureBuilder<String>(
              future: _networkSourceName(book, database),
              builder: (_, source) => Text(source.data ?? '在线书籍'),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('继续阅读'),
            onTap: () {
              Navigator.pop(sheetContext);
              _openNetworkBook(book, database);
            },
          ),
          ListTile(
            leading: Icon(
              Icons.delete_outline_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              '移出书库',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () {
              Navigator.pop(sheetContext);
              _deleteNetwork(book, database);
            },
          ),
        ],
      ),
    ),
  );

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
        return StreamBuilder<List<NetworkShelfBook>>(
          stream: NetworkShelfRepository(repository.database).watchBooks(),
          builder: (context, networkSnapshot) {
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
                          query.isEmpty ||
                          book.title.toLowerCase().contains(query),
                    )
                    .toList(growable: false);
                final networkBooks =
                    (networkSnapshot.data ?? const <NetworkShelfBook>[])
                        .where(
                          (book) =>
                              query.isEmpty ||
                              book.title.toLowerCase().contains(query),
                        )
                        .toList(growable: false);
                if (books.isEmpty && networkBooks.isEmpty) {
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
                    itemCount: networkBooks.length + books.length,
                    separatorBuilder: (_, _) => const Divider(height: 32),
                    itemBuilder: (context, index) {
                      if (index < networkBooks.length) {
                        final book = networkBooks[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: SizedBox(
                            width: 42,
                            child: FutureBuilder<String>(
                              future: _networkSourceName(
                                book,
                                repository.database,
                              ),
                              builder: (_, source) => ShelfBookCover(
                                title: book.title,
                                identity: '${book.sourceUrl}|${book.locator}',
                                badge: source.data ?? '在线',
                              ),
                            ),
                          ),
                          title: Text(book.title),
                          subtitle: FutureBuilder<String>(
                            future: _networkSourceName(
                              book,
                              repository.database,
                            ),
                            builder: (_, source) => Text(
                              [
                                if (book.author?.isNotEmpty ?? false)
                                  book.author!,
                                source.data ?? '在线书籍',
                              ].join(' · '),
                            ),
                          ),
                          trailing: IconButton(
                            tooltip: '${book.title}的更多操作',
                            icon: const Icon(Icons.more_horiz),
                            onPressed: () =>
                                _showNetworkActions(book, repository.database),
                          ),
                          onTap: () =>
                              _openNetworkBook(book, repository.database),
                        );
                      }
                      index -= networkBooks.length;
                      final book = books[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: SizedBox(
                          width: 42,
                          child: BookCover(book: book),
                        ),
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
                            () => _deleteLocal(book, repository),
                          ),
                        ),
                        onTap: () => _openBook(book, repository),
                      );
                    },
                  );
                }
                final total = networkBooks.length + books.length;
                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(32, 28, 32, 0),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisExtent:
                              (MediaQuery.sizeOf(context).width - 90) / 1.4 +
                              50,
                          crossAxisSpacing: 26,
                          mainAxisSpacing: 24,
                        ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          if (index < networkBooks.length) {
                            final book = networkBooks[index];
                            return FutureBuilder<String>(
                              future: _networkSourceName(
                                book,
                                repository.database,
                              ),
                              builder: (context, source) => Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  GestureDetector(
                                    onTap: () => _openNetworkBook(
                                      book,
                                      repository.database,
                                    ),
                                    onLongPress: () => _showNetworkActions(
                                      book,
                                      repository.database,
                                    ),
                                    child: ShelfBookCover(
                                      title: book.title,
                                      identity:
                                          '${book.sourceUrl}|${book.locator}',
                                      badge: source.data ?? '在线',
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          source.data ?? '在线书籍',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: '${book.title}的更多操作',
                                        padding: EdgeInsets.zero,
                                        icon: const Icon(
                                          Icons.more_horiz,
                                          size: 22,
                                        ),
                                        onPressed: () => _showNetworkActions(
                                          book,
                                          repository.database,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }
                          final book = books[index - networkBooks.length];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: () => _openBook(book, repository),
                                onLongPress: () => showBookActions(
                                  context,
                                  book,
                                  () => _openBook(book, repository),
                                  () => _deleteLocal(book, repository),
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
                                  IconButton(
                                    tooltip: '${book.title}的更多操作',
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(
                                      Icons.more_horiz,
                                      size: 22,
                                    ),
                                    onPressed: () => showBookActions(
                                      context,
                                      book,
                                      () => _openBook(book, repository),
                                      () => _deleteLocal(book, repository),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        }, childCount: total),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(32, 38, 32, 130),
                        child: Text(
                          '$total 本书',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    ),
  );
}
