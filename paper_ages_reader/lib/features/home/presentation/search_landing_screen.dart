import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/storage/app_database.dart';
import '../../source_engine/data/local_source_repository.dart';
import '../../source_engine/presentation/all_sources_search_screen.dart';
import '../../source_engine/presentation/source_management_screen.dart';

/// Main Search tab: aggregated online search. Local filtering stays in Library.
class SearchLandingScreen extends StatefulWidget {
  const SearchLandingScreen({super.key, this.active = true, this.database});

  final AppDatabase? database;
  final bool active;

  @override
  State<SearchLandingScreen> createState() => _SearchLandingScreenState();
}

class _SearchLandingScreenState extends State<SearchLandingScreen> {
  Future<AppDatabase> _load() => widget.database == null
      ? AppDatabase.defaults()
      : Future.value(widget.database);

  late Future<AppDatabase> _database = _load();

  @override
  void didUpdateWidget(SearchLandingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _database = _load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AppDatabase>(
    future: _database,
    builder: (context, ready) {
      if (ready.hasError) {
        return const Scaffold(body: Center(child: Text('无法读取书源')));
      }
      if (!ready.hasData) {
        return const Scaffold(
          body: Center(child: CupertinoActivityIndicator()),
        );
      }
      final database = ready.data!;
      return StreamBuilder<List<StoredBookSource>>(
        stream: LocalSourceRepository(database).watchSources(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Scaffold(body: Center(child: Text('无法读取书源')));
          }
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CupertinoActivityIndicator()),
            );
          }
          return AllSourcesSearchScreen(
            sources: snapshot.data!,
            onManageSources: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SourceManagementScreen(database: database),
              ),
            ),
          );
        },
      );
    },
  );
}
