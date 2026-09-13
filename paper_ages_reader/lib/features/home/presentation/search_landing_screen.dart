import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/storage/app_database.dart';
import '../../library/data/local_library_repository.dart';
import '../../library/domain/library_book.dart';
import '../../library/presentation/book_cover.dart';
import '../../reader_document/presentation/reader_document_screen.dart';
import '../../reader_document/presentation/pdf_reader_screen.dart';
import '../../source_engine/application/legado_source_importer.dart';
import '../../source_engine/data/local_source_repository.dart';
import '../../source_engine/presentation/all_sources_search_screen.dart';
import '../../source_engine/presentation/source_management_screen.dart';

class SearchLandingScreen extends StatefulWidget {
  const SearchLandingScreen({super.key, this.active = true, this.database});
  final AppDatabase? database;
  final bool active;
  @override
  State<SearchLandingScreen> createState() => _SearchLandingScreenState();
}

class _SearchLandingScreenState extends State<SearchLandingScreen> {
  final _controller = TextEditingController();
  Future<AppDatabase> _load() => widget.database == null
      ? AppDatabase.defaults()
      : Future.value(widget.database);
  late Future<AppDatabase> _database = _load();
  bool _loading = false;
  @override
  void didUpdateWidget(SearchLandingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _database = _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _online() async {
    setState(() => _loading = true);
    try {
      final database = await AppDatabase.defaults();
      final sources = await LocalSourceRepository(database)
          .watchSources()
          .first;
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              sources.any((source) => source.state == SourceImportState.ready)
              ? AllSourcesSearchScreen(sources: sources)
              : const SourceManagementScreen(),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法读取书源，请稍后重试。')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('搜索'),
      actions: [
        PopupMenuButton<String>(
          tooltip: '搜索选项',
          icon: const Icon(CupertinoIcons.ellipsis_circle),
          onSelected: (value) {
            if (value == 'online') {
              if (!_loading) _online();
            } else {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SourceManagementScreen(),
                ),
              );
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'online',
              enabled: !_loading,
              child: const Text('搜索在线书源'),
            ),
            const PopupMenuItem(value: 'sources', child: Text('书源管理')),
          ],
        ),
        const SizedBox(width: 22),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 6, 32, 0),
          child: CupertinoSearchTextField(
            key: const Key('main-library-search'),
            controller: _controller,
            placeholder: '你的书库',
            style: TextStyle(
              fontSize: 17,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF232323)
                : const Color(0xFFEEEEF0),
            borderRadius: BorderRadius.circular(26),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            onChanged: (_) => setState(() {}),
            onSuffixTap: () => setState(_controller.clear),
          ),
        ),
        Expanded(
          child: _controller.text.trim().isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.search,
                        size: 44,
                        color: Color(0xFFC5C5C7),
                      ),
                      SizedBox(height: 28),
                      Text(
                        '搜索书库',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 100),
                    ],
                  ),
                )
              : FutureBuilder<AppDatabase>(
                  future: _database,
                  builder: (context, ready) {
                    if (ready.hasError) {
                      return const Center(child: Text('无法读取书库'));
                    }
                    if (!ready.hasData) {
                      return const Center(child: CupertinoActivityIndicator());
                    }
                    final repository = LocalLibraryRepository(ready.data!);
                    final query = _controller.text.trim().toLowerCase();
                    final books = repository.recentBooks
                        .where(
                          (book) => book.title.toLowerCase().contains(query),
                        )
                        .toList();
                    if (books.isEmpty) {
                      return const Center(child: Text('没有找到相关书籍'));
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(32, 26, 32, 120),
                      itemCount: books.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 20),
                      itemBuilder: (context, index) {
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
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => book.kind == LibraryBookKind.pdf
                                  ? PdfReaderScreen(book: book)
                                  : ReaderDocumentScreen(
                                      book: book,
                                      repository: repository,
                                    ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    ),
  );
}
