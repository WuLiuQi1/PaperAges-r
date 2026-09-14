import 'package:flutter/material.dart';

import '../application/legado_source_importer.dart';
import '../data/local_source_repository.dart';
import '../domain/source_engine.dart';
import 'source_search_screen.dart';

class AllSourcesSearchScreen extends StatefulWidget {
  const AllSourcesSearchScreen({
    super.key,
    required this.sources,
    this.initialQuery = '',
    this.onManageSources,
  });
  final List<StoredBookSource> sources;
  final String initialQuery;
  final VoidCallback? onManageSources;
  @override
  State<AllSourcesSearchScreen> createState() => _AllSourcesSearchScreenState();
}

class _AllSourcesSearchScreenState extends State<AllSourcesSearchScreen> {
  static const _maxConcurrentSearches = 8;
  static const _maxSources = 300;
  final _query = TextEditingController();
  SourceCancellationToken? _token;
  final _results = <_SourceSearchResult>[];
  var _loading = false;
  String? _selectedSourceUrl;
  var _page = 1;
  var _hasMore = false;

  @override
  void initState() {
    super.initState();
    _query.text = widget.initialQuery;
    if (_query.text.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  List<StoredBookSource> get _safeSources => widget.sources
      .where(
        (source) => source.enabled && source.state == SourceImportState.ready,
      )
      .take(_maxSources)
      .toList(growable: false);

  List<StoredBookSource> get _selectedSources => _selectedSourceUrl == null
      ? _safeSources
      : _safeSources
            .where((source) => source.url == _selectedSourceUrl)
            .toList(growable: false);

  void _changeScope(String? sourceUrl) {
    if (_selectedSourceUrl == sourceUrl) return;
    _token?.cancel();
    setState(() {
      _selectedSourceUrl = sourceUrl;
      _results.clear();
      _page = 1;
      _hasMore = false;
      _loading = false;
    });
    if (_query.text.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  List<({StoredBookSource source, NetworkBook book})> get _books {
    final query = _query.text.trim().toLowerCase();
    final seen = <String>{};
    final books = <({StoredBookSource source, NetworkBook book})>[];
    for (final result in _results) {
      for (final book in result.books) {
        final key = '${result.source.url}|${book.locator}';
        if (seen.add(key)) books.add((source: result.source, book: book));
      }
    }
    int score(NetworkBook book) {
      final title = book.title.toLowerCase();
      final author = (book.author ?? '').toLowerCase();
      if (title == query) return 0;
      if (title.startsWith(query)) return 1;
      if (title.contains(query)) return 2;
      if (author.contains(query)) return 3;
      return 4;
    }

    books.sort((left, right) {
      final relevance = score(left.book).compareTo(score(right.book));
      return relevance != 0
          ? relevance
          : left.book.title.compareTo(right.book.title);
    });
    return books;
  }

  @override
  void dispose() {
    _token?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _search({bool loadMore = false}) async {
    final query = _query.text.trim();
    if (query.isEmpty) return;
    _token?.cancel();
    final token = SourceCancellationToken();
    _token = token;
    setState(() {
      _loading = true;
      if (loadMore) {
        _page += 1;
      } else {
        _page = 1;
        _results.clear();
      }
      _hasMore = false;
    });
    final sources = _selectedSources;
    var nextIndex = 0;
    Future<void> worker() async {
      while (true) {
        if (token != _token) return;
        if (nextIndex >= sources.length) return;
        final source = sources[nextIndex++];
        final engine = StaticSourceEngine(
          limits: const SourceEngineLimits(timeout: Duration(seconds: 6)),
        );
        try {
          final books = await engine.search(
            source: source.configuration,
            query: query,
            page: _page,
            cancellationToken: token,
          );
          if (mounted && identical(token, _token)) {
            setState(() {
              _results.add(_SourceSearchResult(source, books));
              if (books.isNotEmpty) _hasMore = true;
            });
          }
        } on CancelledFailure {
          return;
        } on SourceEngineFailure catch (error) {
          if (mounted && identical(token, _token)) {
            setState(
              () => _results.add(
                _SourceSearchResult(source, const [], error.message),
              ),
            );
          }
        } finally {
          engine.close();
        }
      }
    }

    if (sources.isEmpty) {
      if (mounted && identical(token, _token)) setState(() => _loading = false);
      return;
    }
    await Future.wait(
      List.generate(
        _maxConcurrentSearches < sources.length
            ? _maxConcurrentSearches
            : sources.length,
        (_) => worker(),
      ),
    );
    if (mounted && identical(token, _token)) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 72,
      title: const Text(
        '搜索',
        style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
      ),
      actions: [
        if (widget.onManageSources != null)
          IconButton(
            tooltip: '书源管理',
            onPressed: widget.onManageSources,
            icon: const Icon(Icons.public_outlined),
          ),
        const SizedBox(width: 8),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    key: const Key('online-search-field'),
                    controller: _query,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _search(),
                    decoration: InputDecoration(
                      hintText: '书名或作者',
                      prefixIcon: const Icon(Icons.search_rounded, size: 22),
                      suffixIcon: _query.text.isEmpty
                          ? const Icon(Icons.mic_none_rounded, size: 22)
                          : IconButton(
                              tooltip: '清空',
                              onPressed: () {
                                _token?.cancel();
                                setState(() {
                                  _query.clear();
                                  _results.clear();
                                  _loading = false;
                                  _page = 1;
                                });
                              },
                              icon: const Icon(Icons.cancel, size: 19),
                            ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _loading || _query.text.trim().isEmpty
                    ? null
                    : _search,
                child: const Text('搜索'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            child: PopupMenuButton<String>(
              tooltip: '选择搜索书源',
              position: PopupMenuPosition.under,
              onSelected: (value) => _changeScope(value.isEmpty ? null : value),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: '',
                  child: Text('全部已启用书源（${_safeSources.length}）'),
                ),
                for (final source in _safeSources)
                  PopupMenuItem(value: source.url, child: Text(source.name)),
              ],
              child: SizedBox(
                height: 52,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.public_rounded, size: 22),
                      const SizedBox(width: 12),
                      const Text(
                        '书源',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Flexible(
                        child: Text(
                          _selectedSourceUrl == null
                              ? '全部已启用 · ${_safeSources.length}'
                              : _safeSources
                                        .where(
                                          (source) =>
                                              source.url == _selectedSourceUrl,
                                        )
                                        .map((source) => source.name)
                                        .firstOrNull ??
                                    '全部已启用',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_results.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '第 $_page 页 · ${_books.length} 项',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        Expanded(
          child: _results.isEmpty && !_loading
              ? Center(
                  child: Text(
                    _safeSources.isEmpty
                        ? '请先从右上角导入并启用书源。'
                        : '输入书名后，已启用书源会逐步返回结果。',
                  ),
                )
              : _books.isEmpty && !_loading
              ? Center(
                  child: Text(
                    _results.any((result) => result.error != null)
                        ? '未找到结果，部分书源请求失败'
                        : '没有找到匹配结果',
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: _books.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final result = _books[index];
                    return ListTile(
                      title: Text(result.book.title),
                      subtitle: Text(
                        [
                          if (result.book.author?.isNotEmpty ?? false)
                            result.book.author!,
                          result.source.name,
                        ].join(' · '),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => NetworkBookScreen(
                            source: result.source,
                            book: result.book,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (!_loading && _books.isNotEmpty && _hasMore)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _search(loadMore: true),
                  child: const Text('加载下一页'),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _SourceSearchResult {
  const _SourceSearchResult(this.source, this.books, [this.error]);
  final StoredBookSource source;
  final List<NetworkBook> books;
  final String? error;
}
