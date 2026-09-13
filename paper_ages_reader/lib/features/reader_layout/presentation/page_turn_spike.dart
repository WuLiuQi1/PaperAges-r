import 'dart:ui';

import 'package:flutter/material.dart';

import '../domain/page_turn_policy.dart';

enum PageTurnMode { slide, curl, fade, scroll }

/// G1-only interaction harness. It deliberately uses two fixed text pages;
/// production pagination and anchors are separate work.
class PageTurnSpike extends StatefulWidget {
  const PageTurnSpike({super.key});

  @override
  State<PageTurnSpike> createState() => _PageTurnSpikeState();
}

class _PageTurnSpikeState extends State<PageTurnSpike> {
  static const _policy = PageTurnPolicy();
  static const _pages = [
    '第一页\n\n这是分页和手势样板。拖动未越过阈值时，只回弹，不提交阅读位置。',
    '第二页\n\n完成拖动或快速甩动后，只产生一次目标页变更。',
  ];

  var _mode = PageTurnMode.slide;
  var _pageIndex = 0;
  var _dragDistance = 0.0;
  var _menuVisible = false;

  void _finishDrag(DragEndDetails details, double width) {
    final outcome = _policy.resolve(
      dragDistance: _dragDistance,
      horizontalVelocity: details.velocity.pixelsPerSecond.dx,
      viewportWidth: width,
    );
    setState(() {
      _dragDistance = 0;
      switch (outcome) {
        case PageTurnOutcome.previous:
          _pageIndex = (_pageIndex - 1).clamp(0, _pages.length - 1);
        case PageTurnOutcome.next:
          _pageIndex = (_pageIndex + 1).clamp(0, _pages.length - 1);
        case PageTurnOutcome.stay:
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('G1 阅读交互样板')),
      floatingActionButton: FloatingActionButton.small(
        key: const Key('reader-menu-toggle'),
        onPressed: () => setState(() => _menuVisible = !_menuVisible),
        child: Icon(_menuVisible ? Icons.close : Icons.more_horiz),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(12),
                child: SegmentedButton<PageTurnMode>(
                  segments: const [
                    ButtonSegment(value: PageTurnMode.slide, label: Text('滑动')),
                    ButtonSegment(
                      value: PageTurnMode.curl,
                      label: Text('仿真卷页'),
                    ),
                    ButtonSegment(
                      value: PageTurnMode.fade,
                      label: Text('淡入淡出'),
                    ),
                    ButtonSegment(
                      value: PageTurnMode.scroll,
                      label: Text('连续滚动'),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (selection) => setState(() {
                    _mode = selection.single;
                    _dragDistance = 0;
                  }),
                ),
              ),
              Expanded(child: _buildModeSurface(colors)),
            ],
          ),
          if (_menuVisible)
            Positioned(
              right: 20,
              bottom: 88,
              child: _GlassReaderMenu(
                onDismiss: () => setState(() => _menuVisible = false),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModeSurface(ColorScheme colors) {
    if (_mode == PageTurnMode.scroll) {
      return _ScrollSample(pages: _pages, colors: colors);
    }
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        key: Key(
          _mode == PageTurnMode.curl
              ? 'page-curl-surface'
              : 'page-turn-surface',
        ),
        onHorizontalDragUpdate: (details) => setState(() {
          _dragDistance += details.delta.dx;
        }),
        onHorizontalDragCancel: () => setState(() => _dragDistance = 0),
        onHorizontalDragEnd: (details) =>
            _finishDrag(details, constraints.maxWidth),
        child: _mode == PageTurnMode.curl
            ? _PageCurlSurface(
                text: _pages[_pageIndex],
                pageNumber: _pageIndex + 1,
                dragDistance: _dragDistance,
                colors: colors,
              )
            : Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    if (_mode == PageTurnMode.fade) {
                      return FadeTransition(opacity: animation, child: child);
                    }
                    return SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.12, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    );
                  },
                  child: _TextPage(
                    key: ValueKey(_pageIndex),
                    text: _pages[_pageIndex],
                    pageNumber: _pageIndex + 1,
                    colors: colors,
                  ),
                ),
              ),
      ),
    );
  }
}

class _TextPage extends StatelessWidget {
  const _TextPage({
    required super.key,
    required this.text,
    required this.pageNumber,
    required this.colors,
  });

  final String text;
  final int pageNumber;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.all(24),
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: colors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('第 $pageNumber 页', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 24),
        Text(text, style: Theme.of(context).textTheme.bodyLarge),
      ],
    ),
  );
}

class _PageCurlSurface extends StatelessWidget {
  const _PageCurlSurface({
    required this.text,
    required this.pageNumber,
    required this.dragDistance,
    required this.colors,
  });

  final String text;
  final int pageNumber;
  final double dragDistance;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: CustomPaint(
      key: const Key('page-curl-paint'),
      painter: _PageCurlPainter(
        progress: (dragDistance.abs() / 320).clamp(0, 0.92),
        foldsFromRight: dragDistance <= 0,
        pageColor: colors.surfaceContainerLowest,
        foldColor: colors.surfaceContainerHigh,
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '第 $pageNumber 页',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 24),
            Text(text, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    ),
  );
}

class _PageCurlPainter extends CustomPainter {
  const _PageCurlPainter({
    required this.progress,
    required this.foldsFromRight,
    required this.pageColor,
    required this.foldColor,
  });

  final double progress;
  final bool foldsFromRight;
  final Color pageColor;
  final Color foldColor;

  @override
  void paint(Canvas canvas, Size size) {
    final page = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(24),
    );
    canvas.drawRRect(page, Paint()..color = pageColor);
    if (progress == 0) return;

    final foldWidth = size.width * progress;
    final startX = foldsFromRight ? size.width - foldWidth : foldWidth;
    final fold = Path()
      ..moveTo(startX, 0)
      ..quadraticBezierTo(
        foldsFromRight ? size.width + foldWidth * .12 : -foldWidth * .12,
        size.height * .48,
        startX,
        size.height,
      )
      ..lineTo(foldsFromRight ? size.width : 0, size.height)
      ..lineTo(foldsFromRight ? size.width : 0, 0)
      ..close();
    canvas.save();
    canvas.clipRRect(page);
    canvas.drawPath(
      fold,
      Paint()
        ..shader = LinearGradient(
          begin: foldsFromRight ? Alignment.centerLeft : Alignment.centerRight,
          end: foldsFromRight ? Alignment.centerRight : Alignment.centerLeft,
          colors: [Colors.black.withValues(alpha: .20), foldColor],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      fold,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.black.withValues(alpha: .20),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PageCurlPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      foldsFromRight != oldDelegate.foldsFromRight ||
      pageColor != oldDelegate.pageColor ||
      foldColor != oldDelegate.foldColor;
}

class _GlassReaderMenu extends StatelessWidget {
  const _GlassReaderMenu({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(28),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .76),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: .16)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _GlassMenuItem(icon: Icons.list_alt_outlined, label: '目录'),
              _GlassMenuItem(icon: Icons.palette_outlined, label: '主题'),
              _GlassMenuItem(icon: Icons.volume_up_outlined, label: '听书'),
              IconButton(
                key: const Key('reader-menu-dismiss'),
                onPressed: onDismiss,
                icon: const Icon(Icons.close),
                tooltip: '关闭菜单',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _GlassMenuItem extends StatelessWidget {
  const _GlassMenuItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon), const SizedBox(height: 3), Text(label)],
    ),
  );
}

class _ScrollSample extends StatelessWidget {
  const _ScrollSample({required this.pages, required this.colors});

  final List<String> pages;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) => ListView.separated(
    key: const Key('continuous-scroll-surface'),
    padding: const EdgeInsets.all(24),
    itemCount: pages.length,
    separatorBuilder: (_, _) => const SizedBox(height: 20),
    itemBuilder: (context, index) => _TextPage(
      key: ValueKey(index),
      text: pages[index],
      pageNumber: index + 1,
      colors: colors,
    ),
  );
}
