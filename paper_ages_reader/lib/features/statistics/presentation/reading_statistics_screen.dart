import 'package:flutter/material.dart';

import '../../../core/storage/app_database.dart';
import '../data/reading_statistics_repository.dart';

class ReadingStatisticsScreen extends StatelessWidget {
  const ReadingStatisticsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('阅读统计')),
    body: FutureBuilder<AppDatabase>(
      future: AppDatabase.defaults(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final statistics = ReadingStatisticsRepository(snapshot.data!);
        final today = DateTime.now().toIso8601String().substring(0, 10);
        final todayValue = statistics.daily[today] ?? Duration.zero;
        final goal = statistics.dailyGoal;
        final progress = goal.inMicroseconds == 0
            ? 0.0
            : (todayValue.inMicroseconds / goal.inMicroseconds).clamp(0.0, 1.0);
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('今日阅读', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 12),
              Text('${_format(todayValue)} / ${_format(goal)}'),
              const SizedBox(height: 28),
              const Text('视读与听书同时发生时仅按时间并集计入。暂停、正文等待和声音准备不计时。'),
            ],
          ),
        );
      },
    ),
  );

  static String _format(Duration value) =>
      '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
}
