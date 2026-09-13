import 'package:flutter/material.dart';

import '../../../core/storage/app_database.dart';
import '../application/legado_source_importer.dart';
import '../data/local_source_repository.dart';
import '../data/persistent_source_binding_store.dart';
import '../domain/source_engine.dart';
import '../domain/source_switch_service.dart';

/// Explicit source mapping: the user chooses the new source and chapter URL,
/// then the screen proves that chapter can be read before committing the CAS
/// binding.  It deliberately never guesses based on a chapter title.
class SourceSwitchScreen extends StatefulWidget {
  const SourceSwitchScreen({super.key, required this.bookId});
  final String bookId;
  @override
  State<SourceSwitchScreen> createState() => _SourceSwitchScreenState();
}

class _SourceSwitchScreenState extends State<SourceSwitchScreen> {
  late final Future<_Dependencies> _dependencies = _open();
  final _chapterUrl = TextEditingController();
  final _chapterKey = TextEditingController();
  StoredBookSource? _source;
  var _submitting = false;

  Future<_Dependencies> _open() async {
    final database = await AppDatabase.defaults();
    final bindings = PersistentSourceBindingStore(database);
    final current = bindings.bindingFor(widget.bookId);
    _chapterUrl.text = current?.locator.toString() ?? '';
    _chapterKey.text = current?.chapterKey ?? '';
    return _Dependencies(LocalSourceRepository(database), bindings, current);
  }

  @override
  void dispose() {
    _chapterUrl.dispose();
    _chapterKey.dispose();
    super.dispose();
  }

  Future<void> _verifyAndSwitch(_Dependencies deps) async {
    final source = _source;
    final key = _chapterKey.text.trim();
    final rawUrl = _chapterUrl.text.trim();
    final current = deps.current;
    if (source == null ||
        key.isEmpty ||
        Uri.tryParse(rawUrl)?.hasScheme != true) {
      _show('请选择安全书源，并填写可访问的章节 URL 与稳定章节标识。');
      return;
    }
    setState(() => _submitting = true);
    final engine = StaticSourceEngine();
    try {
      final preview = await engine.content(
        source: source.configuration,
        chapterUrl: Uri.parse(rawUrl),
      );
      if (preview.trim().isEmpty) throw const ParseFailure('目标章节没有正文');
      final result = await deps.bindings.replaceIfCurrent(
        expectedRevision: current?.revision ?? 0,
        next: SourceBinding(
          bookId: widget.bookId,
          sourceUrl: source.url,
          locator: Uri.parse(rawUrl),
          chapterKey: key,
          revision: (current?.revision ?? 0) + 1,
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
                const Text('先验证新书源的同一章节，再原子替换当前阅读映射。未通过验证不会改动原书源。'),
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
                const SizedBox(height: 12),
                TextField(
                  controller: _chapterUrl,
                  enabled: !_submitting,
                  decoration: const InputDecoration(labelText: '目标章节 URL'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _chapterKey,
                  enabled: !_submitting,
                  decoration: const InputDecoration(labelText: '稳定章节标识'),
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
