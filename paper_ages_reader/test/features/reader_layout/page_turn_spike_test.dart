import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/features/reader_layout/presentation/page_turn_spike.dart';

void main() {
  testWidgets('short horizontal drag keeps the current page', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PageTurnSpike()));

    await tester.drag(
      find.byKey(const Key('page-turn-surface')),
      const Offset(-30, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('第 1 页'), findsOneWidget);
  });

  testWidgets('completed horizontal drag advances exactly one page', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PageTurnSpike()));

    await tester.drag(
      find.byKey(const Key('page-turn-surface')),
      const Offset(-250, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('第 2 页'), findsOneWidget);
  });

  testWidgets('page-curl mode exposes a drag-reactive paint surface', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PageTurnSpike()));

    await tester.tap(find.text('仿真卷页'));
    await tester.pump();
    await tester.drag(
      find.byKey(const Key('page-curl-surface')),
      const Offset(-60, 0),
    );
    await tester.pump();

    expect(find.byKey(const Key('page-curl-paint')), findsOneWidget);
  });

  testWidgets('glass menu opens and closes without changing page content', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PageTurnSpike()));

    await tester.tap(find.byKey(const Key('reader-menu-toggle')));
    await tester.pump();
    expect(find.text('目录'), findsOneWidget);
    expect(find.text('第 1 页'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader-menu-dismiss')));
    await tester.pump();
    expect(find.text('目录'), findsNothing);
    expect(find.text('第 1 页'), findsOneWidget);
  });
}
