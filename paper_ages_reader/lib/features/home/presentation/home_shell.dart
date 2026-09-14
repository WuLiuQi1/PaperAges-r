import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/ui/books_navigation.dart';
import '../../../core/storage/app_database.dart';
import '../../library/presentation/local_library_screen.dart';
import '../../library/presentation/book_cover.dart';
import '../../library/data/local_library_repository.dart';
import '../../library/domain/library_book.dart';
import '../../reader_document/presentation/reader_document_screen.dart';
import '../../reader_document/presentation/pdf_reader_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../statistics/data/reading_statistics_repository.dart';
import 'search_landing_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.database});
  final AppDatabase? database;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  var _index = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    extendBody: true,
    body: IndexedStack(
      index: _index,
      children: [
        _HomeDashboard(
          active: _index == 0,
          database: widget.database,
          onLibrary: () => setState(() => _index = 1),
        ),
        LocalLibraryScreen(
          repository: widget.database == null
              ? null
              : LocalLibraryRepository(widget.database!),
        ),
        SearchLandingScreen(active: _index == 2, database: widget.database),
      ],
    ),
    bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom > 0
        ? null
        : BooksNavigation(
            index: _index,
            onChanged: (value) {
              FocusScope.of(context).unfocus();
              setState(() => _index = value);
            },
          ),
  );
}

class _HomeDashboard extends StatefulWidget {
  const _HomeDashboard({
    required this.onLibrary,
    required this.active,
    this.database,
  });
  final AppDatabase? database;
  final VoidCallback onLibrary;
  final bool active;
  @override
  State<_HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<_HomeDashboard> {
  Future<AppDatabase> _load() => widget.database == null
      ? AppDatabase.defaults()
      : Future.value(widget.database);
  late Future<AppDatabase> _future = _load();
  @override
  void didUpdateWidget(_HomeDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _future = _load();
  }

  void _refresh() {
    if (mounted) setState(() => _future = _load());
  }

  Future<void> _read(
    LibraryBook book,
    LocalLibraryRepository repository,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => book.kind == LibraryBookKind.pdf
            ? PdfReaderScreen(book: book)
            : ReaderDocumentScreen(book: book, repository: repository),
      ),
    );
    _refresh();
  }

  Future<void> _settings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FractionallySizedBox(
        heightFactor: .94,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: const SettingsScreen(),
        ),
      ),
    );
    _refresh();
  }

  Widget _card(
    LibraryBook book,
    LocalLibraryRepository repository, {
    bool highlighted = false,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = highlighted
        ? Colors.white
        : Theme.of(context).colorScheme.onSurface;
    return GestureDetector(
      onTap: () => _read(book, repository),
      onLongPress: () =>
          showBookActions(context, book, () => _read(book, repository)),
      child: Container(
        width: MediaQuery.sizeOf(context).width * .62,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: highlighted
              ? null
              : (dark ? const Color(0xFF252525) : Colors.white),
          gradient: highlighted
              ? const LinearGradient(
                  colors: [Color(0xFF17445C), Color(0xFF7C4918)],
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .10),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: [
            SizedBox(width: 44, child: BookCover(book: book)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${book.kind == LibraryBookKind.pdf ? 'PDF' : '图书'} · ${repository.progressLabel(book.id)}',
                    style: TextStyle(
                      color: foreground.withValues(alpha: .65),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 32,
              child: IconButton(
                padding: EdgeInsets.zero,
                tooltip: '${book.title}的更多操作',
                icon: Icon(
                  Icons.more_horiz,
                  color: foreground.withValues(alpha: .7),
                  size: 20,
                ),
                onPressed: () => showBookActions(
                  context,
                  book,
                  () => _read(book, repository),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, Widget child) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Theme.of(context).colorScheme.surface,
          Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF080808)
              : const Color(0xFFF0F0F0),
        ],
      ),
    ),
    padding: const EdgeInsets.fromLTRB(32, 14, 32, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );

  Widget _weekProgress(Map<String, Duration> daily) {
    const labels = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    final now = DateTime.now();
    final diameter = MediaQuery.sizeOf(context).width < 360 ? 32.0 : 39.0;
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday % 7));
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var index = 0; index < 7; index++)
              Builder(
                builder: (context) {
                  final date = start.add(Duration(days: index));
                  final key = date.toIso8601String().substring(0, 10);
                  final read = (daily[key] ?? Duration.zero) > Duration.zero;
                  final current = index == now.weekday % 7;
                  return Container(
                    width: diameter,
                    height: diameter,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: read ? const Color(0xFF20B8DB) : null,
                      border: Border.all(
                        color: current
                            ? const Color(0xFF20B8DB)
                            : Colors.black12,
                        width: current ? 2 : 1,
                      ),
                    ),
                    child: Text(
                      labels[index],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: read
                            ? Colors.white
                            : current
                            ? const Color(0xFF169DBC)
                            : Colors.black38,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 18),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome_rounded, size: 18),
            SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '开启连续阅读新记录 ›',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '每天阅读，创造新记录。',
                  style: TextStyle(fontSize: 12, color: Colors.black45),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AppDatabase>(
    future: _future,
    builder: (context, snapshot) {
      final database = snapshot.data;
      final statistics = database == null
          ? null
          : ReadingStatisticsRepository(database);
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final value = statistics?.daily[today] ?? Duration.zero;
      final daily = statistics?.daily ?? const <String, Duration>{};
      final goal =
          statistics?.dailyGoal ?? ReadingStatisticsRepository.defaultGoal;
      final repository = database == null
          ? null
          : LocalLibraryRepository(database);
      final books = repository?.recentBooks ?? <LibraryBook>[];
      final ratio = goal.inMicroseconds <= 0
          ? 0.0
          : (value.inMicroseconds / goal.inMicroseconds).clamp(0.0, 1.0);
      return Scaffold(
        appBar: AppBar(
          title: const Text('主页'),
          actions: [
            IconButton(
              tooltip: '阅读目标',
              onPressed: _settings,
              icon: SizedBox.square(
                dimension: 42,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: ratio,
                      strokeWidth: 4,
                      backgroundColor: const Color(0xFFDDF5F7),
                      color: const Color(0xFF25C5E7),
                    ),
                    Text(
                      '${value.inMinutes}',
                      style: const TextStyle(
                        color: Color(0xFF00A9CF),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: '设置',
              onPressed: _settings,
              icon: const Icon(CupertinoIcons.person_crop_circle, size: 40),
            ),
            const SizedBox(width: 22),
          ],
        ),
        body: snapshot.hasError
            ? const Center(child: Text('无法读取阅读记录，请稍后重试。'))
            : database == null
            ? const Center(child: CupertinoActivityIndicator())
            : ListView(
                padding: const EdgeInsets.only(bottom: 130),
                children: [
                  _section(
                    '继续阅读',
                    books.isEmpty
                        ? GestureDetector(
                            onTap: widget.onLibrary,
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Row(
                                children: [
                                  Icon(CupertinoIcons.book, size: 30),
                                  SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      '还没有书籍\n前往书库导入 TXT 或 PDF',
                                      style: TextStyle(
                                        fontSize: 14,
                                        height: 1.6,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : SizedBox(
                            height: 76,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              clipBehavior: Clip.none,
                              itemCount: books.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 16),
                              itemBuilder: (_, index) => _card(
                                books[index],
                                repository!,
                                highlighted: true,
                              ),
                            ),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 24, 32, 8),
                    child: Column(
                      children: [
                        const Text(
                          '阅读目标',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '坚持每天阅读，提升你的数据，以激励你读完更多图书。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 28),
                        SizedBox(
                          height:
                              (MediaQuery.sizeOf(context).width - 64) / 2 + 48,
                          child: CustomPaint(
                            painter: _GoalArc(
                              progress: ratio,
                              track: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainer,
                              color: const Color(0xFF25C5E7),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(height: 32),
                                  const Text(
                                    '今日阅读进度',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}',
                                    style: const TextStyle(
                                      fontSize: 62,
                                      height: 1.1,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: -3,
                                    ),
                                  ),
                                  Text(
                                    '（目标 ${goal.inMinutes} 分钟）',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        FilledButton(
                          onPressed: books.isEmpty
                              ? widget.onLibrary
                              : () => _read(books.first, repository!),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(58),
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                            shape: const StadiumBorder(),
                          ),
                          child: Text(books.isEmpty ? '前往书库' : '继续阅读'),
                        ),
                        const SizedBox(height: 22),
                        _weekProgress(daily),
                      ],
                    ),
                  ),
                ],
              ),
      );
    },
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
      ..strokeWidth = 9
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
