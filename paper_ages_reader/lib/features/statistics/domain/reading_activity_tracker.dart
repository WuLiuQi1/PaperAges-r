/// Counts active reading/listening as a union of monotonic-time intervals.
/// A caller supplies elapsed microseconds, making wall-clock changes harmless.
class ReadingActivityTracker {
  ReadingActivityTracker({required this.elapsedMicros, required this.dayKey});

  final int Function() elapsedMicros;
  final String Function() dayKey;
  int? _readingStarted;
  int? _listeningStarted;
  int? _unionStarted;
  final Map<String, int> _microsByDay = {};

  void setReadingActive(bool active) => _setMode(active, reading: true);
  void setListeningActive(bool active) => _setMode(active, reading: false);

  void _setMode(bool active, {required bool reading}) {
    final now = elapsedMicros();
    final wasActive = _readingStarted != null || _listeningStarted != null;
    if (reading) {
      _readingStarted = active ? (_readingStarted ?? now) : null;
    } else {
      _listeningStarted = active ? (_listeningStarted ?? now) : null;
    }
    final isActive = _readingStarted != null || _listeningStarted != null;
    if (!wasActive && isActive) _unionStarted = now;
    if (wasActive && !isActive) _close(now);
  }

  void checkpoint() {
    if (_unionStarted == null) return;
    final now = elapsedMicros();
    _close(now);
    _unionStarted = now;
  }

  void _close(int now) {
    final start = _unionStarted;
    if (start == null || now <= start) return;
    _microsByDay.update(
      dayKey(),
      (value) => value + now - start,
      ifAbsent: () => now - start,
    );
    _unionStarted = null;
  }

  Duration durationForDay(String key) =>
      Duration(microseconds: _microsByDay[key] ?? 0);
  Map<String, Duration> get dailyDurations => Map.unmodifiable({
    for (final entry in _microsByDay.entries)
      entry.key: Duration(microseconds: entry.value),
  });

  Map<String, Duration> takeDailyDurations() {
    checkpoint();
    final result = dailyDurations;
    _microsByDay.clear();
    return result;
  }
}
