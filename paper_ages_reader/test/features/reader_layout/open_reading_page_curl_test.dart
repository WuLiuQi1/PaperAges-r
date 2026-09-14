import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/features/reader_layout/domain/reader_page_turn_geometry.dart';
import 'package:paper_ages_reader/features/reader_layout/presentation/open_reading_page_curl.dart';

void main() {
  testWidgets('programmatic curl settles once and commits the next page', (
    tester,
  ) async {
    final controller = ReaderPageCurlController();
    var turns = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 700,
          child: ReaderShaderPageCurl(
            controller: controller,
            currentPage: _snapshot('current'),
            forwardPage: _snapshot('next'),
            onTurnForward: () => turns++,
            onTurnBackward: () {},
            paperColor: Colors.white,
          ),
        ),
      ),
    );
    await tester.pump();

    final turn = controller.turnForward();
    await tester.pumpAndSettle();
    await turn;
    expect(turns, 1);
  });

  testWidgets('backward curl uses an incoming physical sheet', (tester) async {
    final controller = ReaderPageCurlController();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 700,
          child: ReaderShaderPageCurl(
            controller: controller,
            currentPage: _snapshot('current'),
            backwardPage: _snapshot('previous'),
            onTurnForward: () {},
            onTurnBackward: () {},
            paperColor: Colors.white,
          ),
        ),
      ),
    );
    await tester.pump();

    final turn = controller.turnBackward();
    await tester.pump();
    expect(controller.debugMotion, ReaderPageTurnMotion.incoming);
    await tester.pumpAndSettle();
    await turn;
  });

  testWidgets('cancelled curl drag springs back without committing', (
    tester,
  ) async {
    var turns = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 700,
          child: ReaderShaderPageCurl(
            currentPage: _snapshot('current'),
            forwardPage: _snapshot('next'),
            onTurnForward: () => turns++,
            onTurnBackward: () {},
            paperColor: Colors.white,
          ),
        ),
      ),
    );
    await tester.pump();
    final rect = tester.getRect(find.byType(ReaderShaderPageCurl));
    final gesture = await tester.startGesture(rect.center);
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(turns, 0);
    expect(find.text('current'), findsOneWidget);
  });
}

ReaderPageSnapshot _snapshot(String id) => ReaderPageSnapshot(
  key: ReaderPageSnapshotKey(
    pageIdentity: id,
    layoutFingerprint: 'layout',
    themeId: 'day',
  ),
  contentRevision: 0,
  child: ColoredBox(color: Colors.white, child: Text(id)),
);
