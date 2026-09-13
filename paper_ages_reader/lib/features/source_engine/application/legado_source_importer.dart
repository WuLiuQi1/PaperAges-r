import 'dart:convert';

import '../domain/rule_safety_policy.dart';

/// Imports the portable JSON shape without ever interpreting source rules.
/// JS rules remain eligible; unsupported native-library dependencies are retained
/// with an explicit unavailable state. Import is not a runtime compatibility test.
class LegadoSourceImporter {
  const LegadoSourceImporter({this.policy = const RuleSafetyPolicy()});

  final RuleSafetyPolicy policy;

  SourceImportReport importJson(String source) {
    final decoded = jsonDecode(source);
    final entries = decoded is List ? decoded : [decoded];
    final imported = <ImportedBookSource>[];
    final rejected = <SourceImportFailure>[];
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      if (entry is! Map) {
        rejected.add(SourceImportFailure(index, '书源条目必须是 JSON 对象'));
        continue;
      }
      final config = Map<String, Object?>.from(entry);
      final name = config['bookSourceName'];
      final url = config['bookSourceUrl'];
      if (name is! String ||
          name.trim().isEmpty ||
          url is! String ||
          url.trim().isEmpty) {
        rejected.add(SourceImportFailure(index, '缺少书源名称或地址'));
        continue;
      }
      final report = policy.inspect(config);
      imported.add(
        ImportedBookSource(
          name: name,
          url: url,
          rawConfiguration: Map.unmodifiable(config),
          state: report.canExecute
              ? SourceImportState.ready
              : SourceImportState.disabledUnsafeRule,
          unsafePaths: List.unmodifiable(
            report.issues.map((issue) => issue.path),
          ),
        ),
      );
    }
    return SourceImportReport(
      imported: List.unmodifiable(imported),
      failures: List.unmodifiable(rejected),
    );
  }
}

class SourceImportReport {
  const SourceImportReport({
    required this.imported,
    required this.failures,
    this.retainedBoundUrls = const <String>[],
  });
  final List<ImportedBookSource> imported;
  final List<SourceImportFailure> failures;

  /// Configuration identities that were accepted as input but deliberately
  /// retained their stored revision because a book currently binds to them.
  final List<String> retainedBoundUrls;
}

class ImportedBookSource {
  const ImportedBookSource({
    required this.name,
    required this.url,
    required this.rawConfiguration,
    required this.state,
    required this.unsafePaths,
  });
  final String name;
  final String url;
  final Map<String, Object?> rawConfiguration;
  final SourceImportState state;
  final List<String> unsafePaths;
}

enum SourceImportState { ready, disabledUnsafeRule }

class SourceImportFailure {
  const SourceImportFailure(this.index, this.message);
  final int index;
  final String message;
}
