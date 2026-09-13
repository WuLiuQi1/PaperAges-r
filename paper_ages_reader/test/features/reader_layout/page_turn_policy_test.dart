import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/features/reader_layout/domain/page_turn_policy.dart';

void main() {
  const policy = PageTurnPolicy();

  test('does not commit a short slow drag', () {
    expect(
      policy.resolve(
        dragDistance: -100,
        horizontalVelocity: 0,
        viewportWidth: 600,
      ),
      PageTurnOutcome.stay,
    );
  });

  test('commits direction once a drag crosses the distance threshold', () {
    expect(
      policy.resolve(
        dragDistance: -150,
        horizontalVelocity: 0,
        viewportWidth: 600,
      ),
      PageTurnOutcome.next,
    );
  });

  test('allows a fast fling to commit without a long drag', () {
    expect(
      policy.resolve(
        dragDistance: 20,
        horizontalVelocity: 720,
        viewportWidth: 600,
      ),
      PageTurnOutcome.previous,
    );
  });

  test('does not commit if viewport geometry is unavailable', () {
    expect(
      policy.resolve(
        dragDistance: -300,
        horizontalVelocity: -900,
        viewportWidth: 0,
      ),
      PageTurnOutcome.stay,
    );
  });
}
