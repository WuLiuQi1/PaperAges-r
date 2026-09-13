import 'package:flutter/material.dart';

import '../../../core/storage/app_database.dart';
import '../../library/presentation/local_library_screen.dart';
import '../../source_engine/presentation/source_management_screen.dart';
import '../../statistics/data/reading_statistics_repository.dart';

/// Top-level three-tab shell specified by D02. Individual tabs retain their
/// widget state with IndexedStack rather than recreating searches on each tap.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  var _index = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: _index,
      children: const [
        _HomeDashboard(),
        LocalLibraryScreen(),
        SourceManagementScreen(),
      ],
    ),
    bottomNavigationBar: SafeArea(
      minimum: const EdgeInsets.fromLTRB(24, 8, 24, 12),
      child: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '主页',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books),
            label: '书库',
          ),
          NavigationDestination(icon: Icon(Icons.search), label: '搜索'),
        ],
      ),
    ),
  );
}

class _HomeDashboard extends StatelessWidget {
  const _HomeDashboard();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Paper Ages')),
    body: FutureBuilder<AppDatabase>(
      future: AppDatabase.defaults(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final database = snapshot.data!;
        final statistics = ReadingStatisticsRepository(database);
        final today = DateTime.now().toIso8601String().substring(0, 10);
        final value = statistics.daily[today] ?? Duration.zero;
        final goal = statistics.dailyGoal;
        final books = database.books;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('继续阅读', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(
                  books.isEmpty
                      ? '还没有书籍'
                      : books.first['title'] as String? ?? '最近阅读',
                ),
                subtitle: Text(books.isEmpty ? '前往书库导入 TXT 或 PDF' : '在书库中继续阅读'),
              ),
            ),
            const SizedBox(height: 24),
            Text('阅读目标', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(
                      value: (value.inMicroseconds / goal.inMicroseconds).clamp(
                        0.0,
                        1.0,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('${value.inMinutes} / ${goal.inMinutes} 分钟'),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
