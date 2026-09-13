import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/main.dart';

void main() {
  testWidgets('G0 bootstrap identifies the app without demo controls', (
    tester,
  ) async {
    await tester.pumpWidget(const PaperAgesApp());

    expect(find.text('Paper Ages'), findsOneWidget);
    expect(find.text('阅读器基础工程已就绪'), findsOneWidget);
  });
}
