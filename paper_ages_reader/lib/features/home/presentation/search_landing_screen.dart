import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/storage/app_database.dart';
import '../../library/presentation/local_library_screen.dart';
import '../../source_engine/application/legado_source_importer.dart';
import '../../source_engine/data/local_source_repository.dart';
import '../../source_engine/presentation/all_sources_search_screen.dart';
import '../../source_engine/presentation/source_management_screen.dart';

class SearchLandingScreen extends StatefulWidget {
  const SearchLandingScreen({super.key});
  @override
  State<SearchLandingScreen> createState() => _SearchLandingScreenState();
}

class _SearchLandingScreenState extends State<SearchLandingScreen> {
  bool _loading = false;

  Future<void> _online() async {
    setState(() => _loading = true);
    try {
      final database = await AppDatabase.defaults();
      final sources = await LocalSourceRepository(database)
          .watchSources()
          .first;
      if (!mounted) return;
      if (!sources.any((source) => source.state == SourceImportState.ready)) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const SourceManagementScreen(),
          ),
        );
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AllSourcesSearchScreen(sources: sources),
          ),
        );
      }
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
        IconButton(
          tooltip: '书源管理',
          icon: const Icon(CupertinoIcons.slider_horizontal_3),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const SourceManagementScreen(),
            ),
          ),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('查找你想读的书', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 20),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 12,
            ),
            leading: const Icon(CupertinoIcons.book),
            title: const Text('搜索书库'),
            subtitle: const Text('查找已导入的本地书籍'),
            trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const LocalLibraryScreen(initialSearch: true),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 12,
            ),
            leading: const Icon(CupertinoIcons.globe),
            title: const Text('搜索在线书源'),
            subtitle: const Text('首次使用请导入 JSON 书源'),
            trailing: _loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(CupertinoIcons.chevron_right, size: 16),
            onTap: _loading ? null : _online,
          ),
        ),
      ],
    ),
  );
}
