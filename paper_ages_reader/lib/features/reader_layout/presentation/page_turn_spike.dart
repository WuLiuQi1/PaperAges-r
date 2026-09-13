import 'package:flutter/material.dart';

import '../domain/page_turn_policy.dart';

enum PageTurnMode { slide, fade, scroll }

/// G1-only interaction harness. It deliberately uses two fixed text pages;
/// production pagination, anchors and page-curl rendering are separate work.
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
      appBar: AppBar(title: const Text('G1 翻页手势样板')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<PageTurnMode>(
              segments: const [
                ButtonSegment(value: PageTurnMode.slide, label: Text('滑动')),
                ButtonSegment(value: PageTurnMode.fade, label: Text('淡入淡出')),
                ButtonSegment(value: PageTurnMode.scroll, label: Text('连续滚动')),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) => setState(() {
                _mode = selection.single;
              }),
            ),
          ),
          Expanded(
            child: _mode == PageTurnMode.scroll
                ? _ScrollSample(pages: _pages, colors: colors)
                : LayoutBuilder(
                    builder: (context, constraints) => GestureDetector(
                      key: const Key('page-turn-surface'),
                      onHorizontalDragUpdate: (details) => setState(() {
                        _dragDistance += details.delta.dx;
                      }),
                      onHorizontalDragCancel: () => setState(() {
                        _dragDistance = 0;
                      }),
                      onHorizontalDragEnd: (details) =>
                          _finishDrag(details, constraints.maxWidth),
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 240),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) {
                            if (_mode == PageTurnMode.fade) {
                              return FadeTransition(
                                opacity: animation,
                                child: child,
                              );
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
                  ),
          ),
        ],
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
