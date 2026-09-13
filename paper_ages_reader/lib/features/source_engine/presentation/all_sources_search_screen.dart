import 'package:flutter/material.dart';

import '../application/legado_source_importer.dart';
import '../data/local_source_repository.dart';
import '../domain/source_engine.dart';
import 'source_search_screen.dart';

class AllSourcesSearchScreen extends StatefulWidget {
  const AllSourcesSearchScreen({super.key, required this.sources});
  final List<StoredBookSource> sources;
  @override
  State<AllSourcesSearchScreen> createState() => _AllSourcesSearchScreenState();
}

class _AllSourcesSearchScreenState extends State<AllSourcesSearchScreen> {
  static const _maxConcurrentSearches = 3;
  final _query = TextEditingController();
  SourceCancellationToken? _token;
  final _results = <_SourceSearchResult>[];
  var _loading = false;

  List<StoredBookSource> get _safeSources => widget.sources
      .where((source) => source.state == SourceImportState.ready)
      .toList(growable: false);

  @override
  void dispose() {
    _token?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.isEmpty) return;
    _token?.cancel();
    final token = SourceCancellationToken();
    _token = token;
    setState(() {
      _loading = true;
      _results.clear();
    });
    final sources = _safeSources;
    var nextIndex = 0;
    Future<void> worker() async {
      while (true) {
        if (token != _token) return;
        if (nextIndex >= sources.length) return;
        final source = sources[nextIndex++];
        final engine = StaticSourceEngine();
        try {
          final books = await engine.search(
            source: source.configuration,
            query: query,
            cancellationToken: token,
          );
          if (mounted && identical(token, _token)) {
            setState(() => _results.add(_SourceSearchResult(source, books)));
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
    appBar: AppBar(title: const Text('搜索全部书源')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SearchBar(
            controller: _query,
            hintText: '搜索书名（最多同时查询 $_maxConcurrentSearches 个书源）',
            onSubmitted: (_) => _search(),
            trailing: [
              IconButton(
                tooltip: '搜索',
                onPressed: _loading ? null : _search,
                icon: const Icon(Icons.search),
              ),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: _results.isEmpty && !_loading
              ? const Center(child: Text('输入书名后，安全书源会逐步返回结果。'))
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final result = _results[index];
                    if (result.error case final error?) {
                      return ListTile(
                        leading: const Icon(Icons.error_outline),
                        title: Text(result.source.name),
                        subtitle: Text('此书源不可用：$error'),
                      );
                    }
                    if (result.books.isEmpty) {
                      return ListTile(
                        title: Text(result.source.name),
                        subtitle: const Text('无匹配结果'),
                      );
                    }
                    return ExpansionTile(
                      title: Text(
                        '${result.source.name} · ${result.books.length} 项',
                      ),
                      children: result.books
                          .map(
                            (book) => ListTile(
                              title: Text(book.title),
                              subtitle: Text(book.author ?? result.source.name),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => NetworkBookScreen(
                                    source: result.source,
                                    book: book,
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    );
                  },
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
