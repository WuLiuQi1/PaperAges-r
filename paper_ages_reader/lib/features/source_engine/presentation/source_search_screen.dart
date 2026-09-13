// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:flutter/material.dart';

import '../../../core/storage/app_database.dart';
import '../../downloads/data/chapter_cache.dart';
import '../data/local_source_repository.dart';
import '../data/network_shelf_repository.dart';
import '../domain/source_engine.dart';

class SourceSearchScreen extends StatefulWidget {
  const SourceSearchScreen({super.key, required this.source});
  final StoredBookSource source;
  @override
  State<SourceSearchScreen> createState() => _SourceSearchScreenState();
}

class _SourceSearchScreenState extends State<SourceSearchScreen> {
  final _query = TextEditingController();
  final _engine = StaticSourceEngine();
  SourceCancellationToken? _token;
  List<NetworkBook> _results = const [];
  String? _message;
  var _loading = false;

  @override
  void dispose() {
    _token?.cancel();
    _engine.close();
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
      _message = null;
      _results = const [];
    });
    try {
      final results = await _engine.search(
        source: widget.source.configuration,
        query: query,
        cancellationToken: token,
      );
      if (!mounted || !identical(token, _token)) return;
      setState(() {
        _results = results;
        _message = results.isEmpty ? '没有匹配结果。' : null;
      });
    } on CancelledFailure {
      // Replaced queries have no user-visible failure.
    } on SourceEngineFailure catch (error) {
      if (mounted && identical(token, _token))
        setState(() => _message = error.message);
    } finally {
      if (mounted && identical(token, _token)) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.source.name)),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SearchBar(
            controller: _query,
            hintText: '搜索书名',
            onSubmitted: (_) => _search(),
            trailing: [
              IconButton(
                onPressed: _loading ? null : _search,
                icon: const Icon(Icons.search),
              ),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_message case final message?)
          Padding(padding: const EdgeInsets.all(24), child: Text(message)),
        Expanded(
          child: ListView.separated(
            itemCount: _results.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final book = _results[index];
              return ListTile(
                title: Text(book.title),
                subtitle: Text(book.author ?? widget.source.name),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        NetworkBookScreen(source: widget.source, book: book),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class NetworkBookScreen extends StatefulWidget {
  const NetworkBookScreen({
    super.key,
    required this.source,
    required this.book,
  });
  final StoredBookSource source;
  final NetworkBook book;
  @override
  State<NetworkBookScreen> createState() => _NetworkBookScreenState();
}

class _NetworkBookScreenState extends State<NetworkBookScreen> {
  final _engine = StaticSourceEngine();
  Future<List<SourceChapter>>? _chapters;
  String? _error;
  @override
  void initState() {
    super.initState();
    _chapters = _load();
  }

  @override
  void dispose() {
    _engine.close();
    super.dispose();
  }

  Future<List<SourceChapter>> _load() async {
    try {
      final details = await _engine.details(
        source: widget.source.configuration,
        book: widget.book,
      );
      return await _engine.chapters(
        source: widget.source.configuration,
        tocUrl: details.tocUrl,
      );
    } on SourceEngineFailure catch (error) {
      _error = error.message;
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.book.title),
      actions: [
        IconButton(
          tooltip: '加入书架',
          icon: const Icon(Icons.library_add_outlined),
          onPressed: () async {
            final database = await AppDatabase.defaults();
            await NetworkShelfRepository(database)
                .add(book: widget.book, sourceUrl: widget.source.url);
            if (!mounted) return;
            ScaffoldMessenger.of(this.context)
                .showSnackBar(const SnackBar(content: Text('已加入网络书架')));
          },
        ),
      ],
    ),
    body: FutureBuilder<List<SourceChapter>>(
      future: _chapters,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text(_error ?? '目录加载失败'));
        final chapters = snapshot.data!;
        return ListView.builder(
          itemCount: chapters.length,
          itemBuilder: (context, index) => ListTile(
            title: Text(chapters[index].title),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => NetworkChapterScreen(
                  source: widget.source,
                  chapter: chapters[index],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class NetworkChapterScreen extends StatefulWidget {
  const NetworkChapterScreen({
    super.key,
    required this.source,
    required this.chapter,
  });
  final StoredBookSource source;
  final SourceChapter chapter;
  @override
  State<NetworkChapterScreen> createState() => _NetworkChapterScreenState();
}

class _NetworkChapterScreenState extends State<NetworkChapterScreen> {
  late final StaticSourceEngine _engine = StaticSourceEngine();
  late final Future<String> _content = _load();
  @override
  void dispose() {
    _engine.close();
    super.dispose();
  }

  Future<String> _load() async {
    final cache = await ChapterCache.defaults();
    final key = ChapterCacheKey(
      sourceUrl: widget.source.url,
      sourceVersion: 'v1',
      locator: widget.chapter.locator,
      chapterKey: widget.chapter.key,
      contentRevision: 'v1',
    );
    final cached = await cache.read(key);
    if (cached != null) return cached;
    final content = await _engine.content(
      source: widget.source.configuration,
      chapterUrl: widget.chapter.locator,
    );
    await cache.write(key, content);
    return content;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.chapter.title)),
    body: FutureBuilder<String>(
      future: _content,
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError)
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('正文不可用：${snapshot.error}'),
            ),
          );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: SelectableText(
              snapshot.data!,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(height: 1.8),
            ),
          ),
        );
      },
    ),
  );
}
