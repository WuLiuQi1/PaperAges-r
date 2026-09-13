import '../data/reading_statistics_repository.dart';
import '../domain/reading_activity_tracker.dart';

/// Binds foreground reading activity to monotonic accounting and durable days.
class ReadingSessionRecorder {
  ReadingSessionRecorder(
    this._repository, {
    Stopwatch? stopwatch,
    String Function()? dayKey,
  }) : _clock = stopwatch ?? (Stopwatch()..start()) {
    _tracker = ReadingActivityTracker(
      elapsedMicros: () => _clock.elapsedMicroseconds,
      dayKey: dayKey ?? _localDayKey,
    );
  }

  final ReadingStatisticsRepository _repository;
  final Stopwatch _clock;
  late final ReadingActivityTracker _tracker;
  var _foreground = false;

  void resumeReading() {
    if (_foreground) return;
    _foreground = true;
    _tracker.setReadingActive(true);
  }

  Future<void> pauseReading() async {
    if (!_foreground) return;
    _foreground = false;
    _tracker.setReadingActive(false);
    await _flush();
  }

  Future<void> _flush() async {
    for (final entry in _tracker.takeDailyDurations().entries) {
      await _repository.add(entry.key, entry.value);
    }
  }

  static String _localDayKey() =>
      DateTime.now().toIso8601String().substring(0, 10);
}
