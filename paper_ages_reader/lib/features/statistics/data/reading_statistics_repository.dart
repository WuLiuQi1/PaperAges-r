import '../../../core/storage/app_database.dart';

class ReadingStatisticsRepository {
  ReadingStatisticsRepository(this._database);

  final AppDatabase _database;
  static const defaultGoal = Duration(minutes: 5);

  Map<String, Duration> get daily => {
    for (final entry in _database.readingStatistics.entries)
      entry.key: Duration(microseconds: entry.value as int? ?? 0),
  };

  Duration get dailyGoal => Duration(
    seconds:
        int.tryParse(
          _database.preference('statistics.dailyGoalSeconds') ?? '',
        ) ??
        defaultGoal.inSeconds,
  );

  Future<void> add(String dayKey, Duration amount) => _database.transaction((
    next,
  ) {
    final values = Map<String, Object?>.from(next['readingStatistics']! as Map);
    values[dayKey] = (values[dayKey] as int? ?? 0) + amount.inMicroseconds;
    next['readingStatistics'] = values;
  });

  Future<void> setDailyGoal(Duration goal) => _database.transaction((next) {
    final preferences = Map<String, Object?>.from(next['preferences']! as Map)
      ..['statistics.dailyGoalSeconds'] = goal.inSeconds.toString();
    next['preferences'] = preferences;
  });
}
