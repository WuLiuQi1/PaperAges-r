import 'dart:convert';

import '../../../core/storage/app_database.dart';
import '../application/legado_source_importer.dart';

class LocalSourceRepository {
  LocalSourceRepository(this._database);
  final AppDatabase _database;

  Stream<List<StoredBookSource>> watchSources() => _database.watchSources().map(
    (rows) => rows.map(StoredBookSource.fromRow).toList(),
  );

  Future<SourceImportReport> importJson(String json) async {
    final report = const LegadoSourceImporter().importJson(json);
    if (report.imported.isEmpty) return report;
    final retainedBoundUrls = <String>[];
    await _database.transaction((next) {
      final sources = List<Object?>.from(next['sources']! as List);
      final bindings = Map<String, Object?>.from(
        next['sourceBindings'] as Map? ?? const <String, Object?>{},
      );
      for (final source in report.imported) {
        final isBound = bindings.values.any(
          (row) => row is Map && row['sourceUrl'] == source.url,
        );
        final alreadyStored = sources.any(
          (row) => row is Map && row['url'] == source.url,
        );
        if (isBound && alreadyStored) {
          retainedBoundUrls.add(source.url);
          continue;
        }
        sources.removeWhere((row) => row is Map && row['url'] == source.url);
        sources.add({
          'name': source.name,
          'url': source.url,
          'state': source.state.name,
          'unsafePaths': source.unsafePaths,
          'configuration': jsonEncode(source.rawConfiguration),
        });
      }
      next['sources'] = sources;
    });
    return SourceImportReport(
      imported: report.imported,
      failures: report.failures,
      retainedBoundUrls: List.unmodifiable(retainedBoundUrls),
    );
  }

  Future<StoredBookSource?> findByUrl(String url) async {
    for (final source in _database.sources.map(StoredBookSource.fromRow)) {
      if (source.url == url) return source;
    }
    return null;
  }
}

class StoredBookSource {
  const StoredBookSource({
    required this.name,
    required this.url,
    required this.state,
    required this.unsafePaths,
    required this.configuration,
  });
  factory StoredBookSource.fromRow(Map<String, Object?> row) =>
      StoredBookSource(
        name: row['name']! as String,
        url: row['url']! as String,
        state: row['state'] == SourceImportState.ready.name
            ? SourceImportState.ready
            : SourceImportState.disabledUnsafeRule,
        unsafePaths:
            ((row['unsafePaths'] as List<Object?>?) ?? const <Object?>[])
                .whereType<String>()
                .toList(),
        configuration: Map<String, Object?>.from(
          jsonDecode(row['configuration']! as String) as Map,
        ),
      );
  final String name;
  final String url;
  final SourceImportState state;
  final List<String> unsafePaths;
  final Map<String, Object?> configuration;
}
