import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../../../core/storage/app_database.dart';
import '../../library/presentation/local_library_screen.dart';
import 'search_landing_screen.dart';
import '../../statistics/data/reading_statistics_repository.dart';
import '../../settings/presentation/settings_screen.dart';

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
      children: [
        _HomeDashboard(onLibrary: () => setState(() => _index = 1)),
        const LocalLibraryScreen(),
        const SearchLandingScreen(),
      ],
    ),
    bottomNavigationBar: SafeArea(
      minimum: const EdgeInsets.fromLTRB(32, 8, 32, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: NavigationBar(
            height: 64,
            labelTextStyle: const WidgetStatePropertyAll(
              TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
            backgroundColor: Theme.of(context).colorScheme.surfaceContainer
                .withValues(alpha: .88),
            indicatorColor: Theme.of(context).colorScheme.onSurface
                .withValues(alpha: .08),
            selectedIndex: _index,
            onDestinationSelected: (value) => setState(() => _index = value),
            destinations: const [
              NavigationDestination(
                icon: Icon(CupertinoIcons.house),
                selectedIcon: Icon(CupertinoIcons.house_fill),
                label: '主页',
              ),
              NavigationDestination(
                icon: Icon(CupertinoIcons.book),
                selectedIcon: Icon(CupertinoIcons.book_fill),
                label: '书库',
              ),
              NavigationDestination(
                icon: Icon(CupertinoIcons.search),
                label: '搜索',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _HomeDashboard extends StatelessWidget {
  const _HomeDashboard({required this.onLibrary});
  final VoidCallback onLibrary;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('主页'),
      actions: [
        IconButton(
          tooltip: '设置',
          icon: const Icon(CupertinoIcons.person_crop_circle, size: 32),
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
        ),
        const SizedBox(width: 12),
      ],
    ),
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
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                onTap: onLibrary,
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(
                  books.isEmpty
                      ? '还没有书籍'
                      : books.first['title'] as String? ?? '最近阅读',
                ),
                subtitle: Text(books.isEmpty ? '前往书库导入 TXT 或 PDF' : '在书库中继续阅读'),
              ),
            ),
            const SizedBox(height: 44),
            Text(
              '阅读目标',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            const Text('每天留一点时间，读你喜欢的书。', textAlign: TextAlign.center),
            const SizedBox(height: 32),
            SizedBox(
              height: 210,
              child: CustomPaint(
                painter: _GoalArc(
                  progress: (value.inMicroseconds / goal.inMicroseconds).clamp(
                    0.0,
                    1.0,
                  ),
                  track: Theme.of(context).colorScheme.surfaceContainer,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 32),
                      const Text('今日阅读进度'),
                      Text(
                        '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontSize: 64,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -2,
                        ),
                      ),
                      Text('目标 ${goal.inMinutes} 分钟'),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.tonal(
              onPressed: onLibrary,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: Text(books.isEmpty ? '前往书库' : '继续阅读'),
            ),
          ],
        );
      },
    ),
  );
}

class _GoalArc extends CustomPainter {
  const _GoalArc({
    required this.progress,
    required this.track,
    required this.color,
  });
  final double progress;
  final Color track;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width / 2 - 8, size.height - 8);
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height - 8),
      radius: radius,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi, false, paint..color = track);
    if (progress > 0) {
      canvas.drawArc(
        rect,
        math.pi,
        math.pi * progress,
        false,
        paint..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_GoalArc oldDelegate) =>
      progress != oldDelegate.progress ||
      track != oldDelegate.track ||
      color != oldDelegate.color;
}
