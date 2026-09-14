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
          'enabled': source.enabled,
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

  Future<void> setEnabled(String url, bool enabled) =>
      _updateSources((sources, _) {
        for (final row in sources.whereType<Map>()) {
          if (row['url'] == url) row['enabled'] = enabled;
        }
      });

  Future<void> setEnabledAll(Iterable<String> urls, bool enabled) {
    final targets = urls.toSet();
    return _updateSources((sources, _) {
      for (final row in sources.whereType<Map>()) {
        if (targets.contains(row['url'])) row['enabled'] = enabled;
      }
    });
  }

  Future<void> remove(String url) => _updateSources((sources, bindings) {
    final isBound = bindings.values.any(
      (row) => row is Map && row['sourceUrl'] == url,
    );
    if (isBound) {
      throw StateError('该书源正在被网络书架使用，请先为相关书籍换源');
    }
    sources.removeWhere((row) => row is Map && row['url'] == url);
  });

  Future<void> removeAll(Iterable<String> urls) async {
    final targets = urls.toSet();
    await _updateSources((sources, bindings) {
      final bound = bindings.values
          .whereType<Map>()
          .map((row) => row['sourceUrl'])
          .whereType<String>()
          .where(targets.contains)
          .toSet();
      if (bound.isNotEmpty) {
        throw StateError('所选书源中有 ${bound.length} 个正在被网络书架使用，请先为相关书籍换源');
      }
      sources.removeWhere((row) => row is Map && targets.contains(row['url']));
    });
  }

  Future<void> _updateSources(
    void Function(List<Object?> sources, Map<String, Object?> bindings) change,
  ) => _database.transaction((next) {
    final sources = List<Object?>.from(next['sources']! as List)
        .map<Object?>(
          (row) => row is Map ? Map<String, Object?>.from(row) : row,
        )
        .toList();
    final bindings = Map<String, Object?>.from(
      next['sourceBindings'] as Map? ?? const <String, Object?>{},
    );
    change(sources, bindings);
    next['sources'] = sources;
  });
}

class StoredBookSource {
  const StoredBookSource({
    required this.name,
    required this.url,
    required this.enabled,
    required this.state,
    required this.unsafePaths,
    required this.configuration,
  });
  factory StoredBookSource.fromRow(Map<String, Object?> row) =>
      StoredBookSource(
        name: row['name']! as String,
        url: row['url']! as String,
        enabled: row['enabled'] as bool? ?? true,
        state:
            const LegadoSourceImporter()
                    .importJson(row['configuration']! as String)
                    .imported
                    .first
                    .state ==
                SourceImportState.ready
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
  final bool enabled;
  final SourceImportState state;
  final List<String> unsafePaths;
  final Map<String, Object?> configuration;

  String get group => '${configuration['bookSourceGroup'] ?? ''}'.trim();
  List<String> get groups => group
      .split(RegExp(r'[,，;；\n]'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList(growable: false);
}
