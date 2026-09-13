import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/core/storage/app_database.dart';
import 'package:paper_ages_reader/features/statistics/data/reading_statistics_repository.dart';

void main() {
  test('persists day totals and the default five minute goal', () async {
    final dir = await Directory.systemTemp.createTemp('paper-ages-stats-');
    addTearDown(() => dir.delete(recursive: true));
    final database = await AppDatabase.openFile(File('${dir.path}/state.json'));
    addTearDown(database.close);
    final repository = ReadingStatisticsRepository(database);
    await repository.add('2026-09-13', const Duration(minutes: 2));
    await repository.add('2026-09-13', const Duration(minutes: 1));
    expect(repository.daily['2026-09-13'], const Duration(minutes: 3));
    expect(repository.dailyGoal, const Duration(minutes: 5));
  });
}
