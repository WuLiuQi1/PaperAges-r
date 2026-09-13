import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/features/statistics/domain/reading_activity_tracker.dart';

void main() {
  test('counts reading and listening as an interval union', () {
    var time = 0;
    final tracker = ReadingActivityTracker(
      elapsedMicros: () => time,
      dayKey: () => '2026-09-13',
    );
    tracker.setReadingActive(true);
    time = 10;
    tracker.setListeningActive(true);
    time = 20;
    tracker.setReadingActive(false);
    time = 30;
    tracker.setListeningActive(false);
    expect(
      tracker.durationForDay('2026-09-13'),
      const Duration(microseconds: 30),
    );
  });

  test('does not create negative duration when monotonic time is invalid', () {
    var time = 100;
    final tracker = ReadingActivityTracker(
      elapsedMicros: () => time,
      dayKey: () => 'day',
    );
    tracker.setReadingActive(true);
    time = 99;
    tracker.setReadingActive(false);
    expect(tracker.durationForDay('day'), Duration.zero);
  });
}
