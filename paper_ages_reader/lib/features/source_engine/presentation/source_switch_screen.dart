import 'package:flutter/material.dart';

import '../../../core/storage/app_database.dart';
import '../../downloads/application/online_chapter_cache_policy.dart';
import '../../downloads/data/chapter_cache.dart';
import '../application/legado_source_importer.dart';
import '../data/local_source_repository.dart';
import '../data/persistent_source_binding_store.dart';
import '../domain/source_engine.dart';
import '../domain/source_switch_service.dart';

/// Explicit source mapping: the user chooses the new source and chapter URL,
/// then the screen proves that chapter can be read before committing the CAS
/// binding.  It deliberately never guesses based on a chapter title.
class SourceSwitchScreen extends StatefulWidget {
  const SourceSwitchScreen({
    super.key,
    required this.bookId,
    this.bookTitle = '',
    this.currentChapterIndex = 0,
    this.currentChapterTitle = '',
  });
  final String bookId;
  final String bookTitle;
  final int currentChapterIndex;
  final String currentChapterTitle;
  @override
  State<SourceSwitchScreen> createState() => _SourceSwitchScreenState();
}

class _SourceSwitchScreenState extends State<SourceSwitchScreen> {
  late final Future<_Dependencies> _dependencies = _open();
  StoredBookSource? _source;
  var _submitting = false;

  Future<_Dependencies> _open() async {
    final database = await AppDatabase.defaults();
    final bindings = PersistentSourceBindingStore(database);
    final current = bindings.bindingFor(widget.bookId);
    return _Dependencies(LocalSourceRepository(database), bindings, current);
  }

  Future<void> _verifyAndSwitch(_Dependencies deps) async {
    final source = _source;
    final current = deps.current;
    if (source == null) {
      _show('请选择新书源。');
      return;
    }
    if (widget.bookTitle.trim().isEmpty) {
      _show('请从书籍阅读页打开换源，以便自动匹配书名和当前章节。');
      return;
    }
    setState(() => _submitting = true);
    final engine = StaticSourceEngine();
    try {
      final results = await engine.search(
        source: source.configuration,
        query: widget.bookTitle,
      );
      if (results.isEmpty) throw const ParseFailure('新书源没有找到同名书籍');
      final normalizedTitle = widget.bookTitle.trim().toLowerCase();
      final candidate = results.firstWhere(
        (book) => book.title.trim().toLowerCase() == normalizedTitle,
        orElse: () => results.first,
      );
      final details = await engine.details(
        source: source.configuration,
        book: candidate,
      );
      final chapters = await engine.chapters(
        source: source.configuration,
        tocUrl: details.tocUrl,
      );
      if (chapters.isEmpty) throw const ParseFailure('新书源目录为空');
      final normalizedChapter = widget.currentChapterTitle.trim();
      final titleIndex = normalizedChapter.isEmpty
          ? -1
          : chapters.indexWhere(
              (chapter) => chapter.title.trim() == normalizedChapter,
            );
      final targetIndex =
          (titleIndex >= 0 ? titleIndex : widget.currentChapterIndex).clamp(
            0,
            chapters.length - 1,
          );
      final cache = await ChapterCache.defaults();
      final loaded = <int, String>{};
      final failures = await const OnlineChapterCachePolicy().warm(
        reason: OnlineChapterWarmReason.sourceSwitched,
        chapterCount: chapters.length,
        currentIndex: targetIndex,
        loadAndPersist: (index) async {
          final chapter = chapters[index];
          final key = ChapterCacheKey(
            sourceUrl: source.url,
            sourceVersion: 'v1',
            locator: chapter.locator,
            chapterKey: chapter.key,
            contentRevision: 'v1',
          );
          final cached = await cache.read(key);
          final content =
              cached ??
              await engine.content(
                source: source.configuration,
                chapterUrl: chapter.locator,
                bookUrl: candidate.locator,
              );
          if (content.trim().isEmpty) throw const ParseFailure('章节正文为空');
          if (cached == null) await cache.write(key, content);
          loaded[index] = content;
        },
      );
      if (!loaded.containsKey(targetIndex)) {
        throw ParseFailure('目标章节加载失败：${failures.first.error}');
      }
      if (failures.isNotEmpty) {
        throw ParseFailure('后一章预加载失败：${failures.first.error}');
      }
      await cache.writeCatalog(
        '${widget.bookId}|${source.url}|${candidate.locator}',
        chapters
            .map(
              (chapter) => CachedChapterRecord(
                key: chapter.key,
                title: chapter.title,
                locator: chapter.locator,
                ordinal: chapter.ordinal,
                bookLocator: candidate.locator,
              ),
            )
            .toList(growable: false),
      );
      final target = chapters[targetIndex];
      final result = await deps.bindings.replaceIfCurrent(
        expectedRevision: current?.revision ?? 0,
        next: SourceBinding(
          bookId: widget.bookId,
          sourceUrl: source.url,
          locator: target.locator,
          chapterKey: target.key,
          revision: (current?.revision ?? 0) + 1,
          bookLocator: candidate.locator,
        ),
      );
      if (!mounted) return;
      if (result is SourceSwitchCommitted) {
        Navigator.of(context).pop(true);
      } else {
        _show((result as SourceSwitchRejected).reason);
      }
    } on SourceEngineFailure catch (error) {
      if (mounted) _show('未切换：目标章节验证失败（${error.message}）');
    } finally {
      engine.close();
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _show(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('映射并切换书源')),
    body: FutureBuilder<_Dependencies>(
      future: _dependencies,
      builder: (context, ready) {
        if (!ready.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final deps = ready.data!;
        return StreamBuilder<List<StoredBookSource>>(
          stream: deps.sources.watchSources(),
          builder: (context, snapshot) {
            final safe = (snapshot.data ?? const <StoredBookSource>[])
                .where((item) => item.state == SourceImportState.ready)
                .toList(growable: false);
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  '选择书源后会自动搜索同名书籍、匹配当前章节，并把目标章节及后一章写入本地缓存。验证失败不会改动原书源。',
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<StoredBookSource>(
                  // ignore: deprecated_member_use
                  value: safe.contains(_source) ? _source : null,
                  items: safe
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(item.name),
                        ),
                      )
                      .toList(),
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _source = value),
                  decoration: const InputDecoration(labelText: '新书源'),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _submitting ? null : () => _verifyAndSwitch(deps),
                  icon: _submitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified_outlined),
                  label: const Text('验证正文并切换'),
                ),
              ],
            );
          },
        );
      },
    ),
  );
}

class _Dependencies {
  const _Dependencies(this.sources, this.bindings, this.current);
  final LocalSourceRepository sources;
  final PersistentSourceBindingStore bindings;
  final SourceBinding? current;
}
