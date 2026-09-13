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
}
