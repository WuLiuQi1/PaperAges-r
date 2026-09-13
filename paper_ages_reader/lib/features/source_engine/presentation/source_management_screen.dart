import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../core/platform/import_file_types.dart';

import '../../../core/storage/app_database.dart';
import '../application/legado_source_importer.dart';
import '../data/local_source_repository.dart';
import 'all_sources_search_screen.dart';
import 'source_search_screen.dart';

class SourceManagementScreen extends StatefulWidget {
  const SourceManagementScreen({super.key});

  @override
  State<SourceManagementScreen> createState() => _SourceManagementScreenState();
}

class _SourceManagementScreenState extends State<SourceManagementScreen> {
  late final Future<LocalSourceRepository> _repository;
  var _importing = false;

  @override
  void initState() {
    super.initState();
    _repository = AppDatabase.defaults().then(LocalSourceRepository.new);
  }

  Future<void> _import(LocalSourceRepository repository) async {
    setState(() => _importing = true);
    try {
      final file = await openFile(
        acceptedTypeGroups: const [ImportFileTypes.sources],
      );
      if (file == null) {
        return;
      }
      final report = await repository.importJson(await file.readAsString());
      if (!mounted) {
        return;
      }
      final disabled = report.imported
          .where(
            (source) => source.state == SourceImportState.disabledUnsafeRule,
          )
          .length;
      final text = disabled > 0
          ? '已导入 ${report.imported.length} 个书源；$disabled 个依赖原生扩展，暂不支持。'
          : '已导入 ${report.imported.length} 个书源，含 JS 的书源也可尝试使用。';
      final retained = report.retainedBoundUrls.isEmpty
          ? ''
          : ' ${report.retainedBoundUrls.length} 个正在使用的书源保留原配置。';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$text$retained')));
    } on FormatException {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('不是有效的 Legado JSON 文件。')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('书源管理'),
      actions: [
        FutureBuilder<LocalSourceRepository>(
          future: _repository,
          builder: (context, ready) {
            if (!ready.hasData) return const SizedBox.shrink();
            return StreamBuilder<List<StoredBookSource>>(
              stream: ready.data!.watchSources(),
              builder: (context, snapshot) {
                final sources = snapshot.data ?? const <StoredBookSource>[];
                final hasSafe = sources.any(
                  (source) => source.state == SourceImportState.ready,
                );
                return IconButton(
                  tooltip: '搜索全部书源',
                  icon: const Icon(Icons.manage_search_outlined),
                  onPressed: hasSafe
                      ? () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                AllSourcesSearchScreen(sources: sources),
                          ),
                        )
                      : null,
                );
              },
            );
          },
        ),
      ],
    ),
    body: FutureBuilder<LocalSourceRepository>(
      future: _repository,
      builder: (context, ready) {
        if (!ready.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final repository = ready.data!;
        return StreamBuilder<List<StoredBookSource>>(
          stream: repository.watchSources(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final sources = snapshot.data!;
            if (sources.isEmpty) {
              return const Center(
                child: Text(
                  '导入一份 Legado JSON 书源。\n支持基础 JS 规则，兼容情况以搜索和阅读结果为准。',
                  textAlign: TextAlign.center,
                ),
              );
            }
            return ListView.separated(
              itemCount: sources.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final source = sources[index];
                final unsafe =
                    source.state == SourceImportState.disabledUnsafeRule;
                return ListTile(
                  leading: Icon(
                    unsafe ? Icons.shield_outlined : Icons.public_outlined,
                    color: unsafe ? Theme.of(context).colorScheme.error : null,
                  ),
                  title: Text(source.name),
                  subtitle: Text(unsafe ? '依赖尚未实现的原生扩展' : source.url),
                  onTap: unsafe
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SourceSearchScreen(source: source),
                          ),
                        ),
                  trailing: unsafe
                      ? IconButton(
                          icon: const Icon(Icons.info_outline),
                          tooltip: '查看原因',
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('书源已安全导入但不可启用'),
                              content: Text(
                                '检测到原生扩展依赖：\n${source.unsafePaths.join('\n')}\n\nJS 不再整体禁用，但原生库扩展尚未实现。',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('知道了'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : null,
                );
              },
            );
          },
        );
      },
    ),
    floatingActionButton: FutureBuilder<LocalSourceRepository>(
      future: _repository,
      builder: (context, ready) => FloatingActionButton.extended(
        onPressed: _importing || !ready.hasData
            ? null
            : () => _import(ready.data!),
        icon: _importing
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.file_open_outlined),
        label: const Text('导入 JSON'),
      ),
    ),
  );
}
