import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../core/platform/import_file_types.dart';

import '../../../core/storage/app_database.dart';
import '../application/legado_source_importer.dart';
import '../data/local_source_repository.dart';
import 'all_sources_search_screen.dart';
import 'source_search_screen.dart';

enum _SourceFilter { all, enabled, disabled, runnable }

extension on _SourceFilter {
  String get label => switch (this) {
    _SourceFilter.all => '全部',
    _SourceFilter.enabled => '已启用',
    _SourceFilter.disabled => '已停用',
    _SourceFilter.runnable => '可运行',
  };
}

class SourceManagementScreen extends StatefulWidget {
  const SourceManagementScreen({super.key, this.database});

  final AppDatabase? database;

  @override
  State<SourceManagementScreen> createState() => _SourceManagementScreenState();
}

class _SourceManagementScreenState extends State<SourceManagementScreen> {
  late final Future<LocalSourceRepository> _repository;
  final _query = TextEditingController();
  final _selected = <String>{};
  var _importing = false;
  var _filter = _SourceFilter.all;
  var _selectionMode = false;
  String? _group;

  @override
  void initState() {
    super.initState();
    _repository = widget.database == null
        ? AppDatabase.defaults().then(LocalSourceRepository.new)
        : Future.value(LocalSourceRepository(widget.database!));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<StoredBookSource> _visible(List<StoredBookSource> sources) {
    final query = _query.text.trim().toLowerCase();
    return sources
        .where((source) {
          final stateMatches = switch (_filter) {
            _SourceFilter.all => true,
            _SourceFilter.enabled => source.enabled,
            _SourceFilter.disabled => !source.enabled,
            _SourceFilter.runnable => source.state == SourceImportState.ready,
          };
          if (!stateMatches) return false;
          if (_group != null && !source.groups.contains(_group)) return false;
          if (query.isEmpty) return true;
          return source.name.toLowerCase().contains(query) ||
              source.url.toLowerCase().contains(query) ||
              source.group.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  Future<void> _remove(
    LocalSourceRepository repository,
    StoredBookSource source,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除书源？'),
        content: Text('将删除“${source.name}”及其配置。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await repository.remove(source.url);
      if (mounted) setState(() => _selected.remove(source.url));
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message.toString())));
      }
    }
  }

  Future<void> _removeSelected(LocalSourceRepository repository) async {
    final count = _selected.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除 $count 个书源？'),
        content: const Text('正在被网络书架使用的书源不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await repository.removeAll(_selected);
      if (mounted) {
        setState(() {
          _selected.clear();
          _selectionMode = false;
        });
      }
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message.toString())));
      }
    }
  }

  Future<void> _setSelectedEnabled(
    LocalSourceRepository repository,
    bool enabled,
  ) async {
    await repository.setEnabledAll(_selected, enabled);
    if (mounted) {
      setState(() {
        _selected.clear();
        _selectionMode = false;
      });
    }
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
                  (source) =>
                      source.enabled && source.state == SourceImportState.ready,
                );
                return Row(
                  children: [
                    IconButton(
                      tooltip: _selectionMode ? '退出批量管理' : '批量管理',
                      icon: Icon(
                        _selectionMode ? Icons.close : Icons.checklist_rounded,
                      ),
                      onPressed: sources.isEmpty
                          ? null
                          : () => setState(() {
                              _selectionMode = !_selectionMode;
                              _selected.clear();
                            }),
                    ),
                    IconButton(
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
                    ),
                  ],
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
            final visible = _visible(sources);
            final groups =
                sources.expand((source) => source.groups).toSet().toList()
                  ..sort();
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: SearchBar(
                    controller: _query,
                    hintText: '搜索名称、分组或地址',
                    leading: const Icon(Icons.search),
                    trailing: [
                      if (_query.text.isNotEmpty)
                        IconButton(
                          tooltip: '清除',
                          onPressed: () {
                            _query.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close),
                        ),
                    ],
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                SizedBox(
                  height: 46,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final filter in _SourceFilter.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            selected: _filter == filter,
                            label: Text(filter.label),
                            onSelected: (_) => setState(() => _filter = filter),
                          ),
                        ),
                      if (groups.isNotEmpty)
                        PopupMenuButton<String>(
                          tooltip: '按分组筛选',
                          initialValue: _group ?? '',
                          onSelected: (group) => setState(
                            () => _group = group.isEmpty ? null : group,
                          ),
                          itemBuilder: (_) => [
                            const PopupMenuItem<String>(
                              value: '',
                              child: Text('全部分组'),
                            ),
                            for (final group in groups)
                              PopupMenuItem<String>(
                                value: group,
                                child: Text(group),
                              ),
                          ],
                          child: Chip(
                            avatar: const Icon(Icons.folder_outlined, size: 18),
                            label: Text(_group ?? '全部分组'),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_selectionMode)
                  _BulkSourceBar(
                    selected: _selected.length,
                    allSelected:
                        visible.isNotEmpty &&
                        visible.every(
                          (source) => _selected.contains(source.url),
                        ),
                    onSelectAll: () => setState(() {
                      final urls = visible.map((source) => source.url).toSet();
                      if (_selected.containsAll(urls)) {
                        _selected.removeAll(urls);
                      } else {
                        _selected.addAll(urls);
                      }
                    }),
                    onEnable: _selected.isEmpty
                        ? null
                        : () => _setSelectedEnabled(repository, true),
                    onDisable: _selected.isEmpty
                        ? null
                        : () => _setSelectedEnabled(repository, false),
                    onDelete: _selected.isEmpty
                        ? null
                        : () => _removeSelected(repository),
                  ),
                Expanded(
                  child: visible.isEmpty
                      ? const Center(child: Text('没有符合条件的书源'))
                      : ListView.separated(
                          itemCount: visible.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final source = visible[index];
                            final unsafe =
                                source.state ==
                                SourceImportState.disabledUnsafeRule;
                            return ListTile(
                              leading: _selectionMode
                                  ? Checkbox(
                                      value: _selected.contains(source.url),
                                      onChanged: (_) => setState(() {
                                        if (!_selected.add(source.url)) {
                                          _selected.remove(source.url);
                                        }
                                      }),
                                    )
                                  : Icon(
                                      unsafe
                                          ? Icons.shield_outlined
                                          : Icons.public_outlined,
                                      color: unsafe
                                          ? Theme.of(context).colorScheme.error
                                          : null,
                                    ),
                              title: Text(source.name),
                              subtitle: Text(
                                unsafe
                                    ? '依赖尚未实现的原生扩展'
                                    : [
                                        if (source.group.isNotEmpty)
                                          source.group,
                                        source.url,
                                      ].join(' · '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: _selectionMode
                                  ? () => setState(() {
                                      if (!_selected.add(source.url)) {
                                        _selected.remove(source.url);
                                      }
                                    })
                                  : unsafe || !source.enabled
                                  ? null
                                  : () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            SourceSearchScreen(source: source),
                                      ),
                                    ),
                              trailing: _selectionMode
                                  ? null
                                  : unsafe
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
                                              onPressed: () =>
                                                  Navigator.of(context).pop(),
                                              child: const Text('知道了'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Switch(
                                          value: source.enabled,
                                          onChanged: (enabled) => repository
                                              .setEnabled(source.url, enabled),
                                        ),
                                        PopupMenuButton<String>(
                                          tooltip: '书源操作',
                                          onSelected: (value) {
                                            if (value == 'search') {
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      SourceSearchScreen(
                                                        source: source,
                                                      ),
                                                ),
                                              );
                                            } else if (value == 'delete') {
                                              _remove(repository, source);
                                            }
                                          },
                                          itemBuilder: (_) => const [
                                            PopupMenuItem(
                                              value: 'search',
                                              child: Text('搜索此书源'),
                                            ),
                                            PopupMenuItem(
                                              value: 'delete',
                                              child: Text('删除'),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                            );
                          },
                        ),
                ),
              ],
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

class _BulkSourceBar extends StatelessWidget {
  const _BulkSourceBar({
    required this.selected,
    required this.allSelected,
    required this.onSelectAll,
    required this.onEnable,
    required this.onDisable,
    required this.onDelete,
  });

  final int selected;
  final bool allSelected;
  final VoidCallback onSelectAll;
  final VoidCallback? onEnable;
  final VoidCallback? onDisable;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: onSelectAll,
            icon: Icon(
              allSelected
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
            ),
            label: Text('已选择 $selected'),
          ),
          const Spacer(),
          TextButton(onPressed: onEnable, child: const Text('启用')),
          TextButton(onPressed: onDisable, child: const Text('停用')),
          IconButton(
            tooltip: '删除所选书源',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    ),
  );
}
