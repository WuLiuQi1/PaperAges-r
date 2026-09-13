import 'package:flutter/material.dart';

import '../../../core/storage/app_database.dart';
import '../../statistics/data/reading_statistics_repository.dart';
import '../../sync/data/webdav_sync_settings_repository.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final Future<AppDatabase> _database = AppDatabase.defaults();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('设置')),
    body: FutureBuilder<AppDatabase>(
      future: _database,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final statistics = ReadingStatisticsRepository(snapshot.data!);
        final sync = WebDavSyncSettingsRepository(snapshot.data!);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('每日阅读目标'),
                subtitle: Text('${statistics.dailyGoal.inMinutes} 分钟'),
                onTap: () => _editGoal(statistics),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.cloud_outlined),
                title: const Text('WebDAV 同步'),
                subtitle: Text(sync.endpoint?.toString() ?? '尚未配置'),
                onTap: () => _editEndpoint(sync),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('WebDAV 凭据仅保存至系统安全存储，不会出现在同步事件或本地书库数据中。'),
            ),
          ],
        );
      },
    ),
  );

  Future<void> _editEndpoint(WebDavSyncSettingsRepository repository) async {
    final controller = TextEditingController(
      text: repository.endpoint?.toString(),
    );
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('WebDAV 地址'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://dav.example/reader/',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await repository.setEndpoint(Uri.parse(controller.text));
                if (context.mounted) {
                  Navigator.pop(context);
                }
                if (mounted) {
                  setState(() {});
                }
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请输入不含凭据或查询参数的 HTTPS 地址')),
                  );
                }
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _editGoal(ReadingStatisticsRepository repository) async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('每日阅读目标')),
            for (final minutes in [5, 15, 30, 60])
              ListTile(
                title: Text('$minutes 分钟'),
                trailing: repository.dailyGoal.inMinutes == minutes
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(context, minutes),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    await repository.setDailyGoal(Duration(minutes: selected));
    if (mounted) setState(() {});
  }
}
