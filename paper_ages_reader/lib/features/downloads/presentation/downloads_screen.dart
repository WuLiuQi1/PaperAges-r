import 'package:flutter/material.dart';

import '../../../core/storage/app_database.dart';
import '../../source_engine/data/local_source_repository.dart';
import '../../source_engine/data/persistent_source_binding_store.dart';
import '../../source_engine/presentation/source_switch_screen.dart';
import '../application/download_manager.dart';
import '../data/chapter_cache.dart';
import '../data/persistent_download_task_repository.dart';
import '../domain/download_task.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});
  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  late final Future<_DownloadsDependencies> _dependencies = _open();

  Future<_DownloadsDependencies> _open() async {
    final database = await AppDatabase.defaults();
    final tasks = PersistentDownloadTaskRepository(database);
    return _DownloadsDependencies(
      tasks: tasks,
      sources: LocalSourceRepository(database),
      bindings: PersistentSourceBindingStore(database),
      manager: DownloadManager(tasks, await ChapterCache.defaults()),
    );
  }

  Future<void> _run(_DownloadsDependencies deps, DownloadTask task) async {
    final source = await deps.sources.findByUrl(task.sourceUrl);
    final binding = deps.bindings.bindingFor(task.bookId);
    if (source == null || binding == null) {
      if (mounted) _show('原书源或阅读映射不存在，无法继续下载。');
      return;
    }
    await deps.manager.run(
      taskId: task.id,
      currentBindingRevision: binding.revision,
      source: source.configuration,
    );
  }

  void _show(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _clearCache(_DownloadsDependencies deps) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理网络缓存？'),
        content: const Text('已下载章节将需要重新下载。导入的 TXT、PDF、字体和阅读进度不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    try {
      await deps.tasks.resetForCacheClear();
      await (await ChapterCache.defaults()).clearNetworkCache();
      if (mounted) _show('网络章节缓存已清理，下载任务已重置。');
    } catch (error) {
      if (mounted) _show('缓存清理未完成：$error');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('下载'),
      actions: [
        FutureBuilder<_DownloadsDependencies>(
          future: _dependencies,
          builder: (context, ready) => IconButton(
            tooltip: '清理网络缓存',
            icon: const Icon(Icons.cleaning_services_outlined),
            onPressed: ready.hasData ? () => _clearCache(ready.data!) : null,
          ),
        ),
      ],
    ),
    body: FutureBuilder<_DownloadsDependencies>(
      future: _dependencies,
      builder: (context, ready) {
        if (!ready.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final deps = ready.data!;
        return StreamBuilder<List<DownloadTask>>(
          stream: deps.tasks.watchTasks(),
          builder: (context, snapshot) {
            final tasks = snapshot.data ?? const <DownloadTask>[];
            if (tasks.isEmpty) return const Center(child: Text('还没有下载任务'));
            return ListView.separated(
              itemCount: tasks.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final task = tasks[index];
                final label =
                    '${task.completedKeys.length}/${task.chapterKeys.length} 章';
                final canRun =
                    task.status == DownloadStatus.queued ||
                    task.status == DownloadStatus.failed ||
                    task.status == DownloadStatus.cancelled;
                return ListTile(
                  title: Text(task.bookId),
                  subtitle: Text(
                    '${task.status.name} · $label${task.lastError == null ? '' : '\n${task.lastError}'}',
                  ),
                  isThreeLine: task.lastError != null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (task.status == DownloadStatus.running)
                        IconButton(
                          tooltip: '取消',
                          icon: const Icon(Icons.cancel_outlined),
                          onPressed: () =>
                              deps.manager.cancelPersisted(task.id),
                        )
                      else if (canRun)
                        IconButton(
                          tooltip: '继续',
                          icon: const Icon(Icons.play_arrow_outlined),
                          onPressed: () async {
                            await deps.manager.retry(task.id);
                            final retry = deps.tasks.byId(task.id);
                            if (retry != null) {
                              await _run(deps, retry);
                            }
                          },
                        )
                      else
                        const Icon(Icons.check_circle_outline),
                      IconButton(
                        tooltip: '换源',
                        icon: const Icon(Icons.swap_horiz_outlined),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                SourceSwitchScreen(bookId: task.bookId),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    ),
  );
}

class _DownloadsDependencies {
  const _DownloadsDependencies({
    required this.tasks,
    required this.sources,
    required this.bindings,
    required this.manager,
  });
  final PersistentDownloadTaskRepository tasks;
  final LocalSourceRepository sources;
  final PersistentSourceBindingStore bindings;
  final DownloadManager manager;
}
