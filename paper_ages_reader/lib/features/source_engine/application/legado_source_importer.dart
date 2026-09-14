import 'dart:convert';

import '../domain/rule_safety_policy.dart';

/// Imports the portable JSON shape without ever interpreting source rules.
/// JS rules remain eligible; unsupported native-library dependencies are retained
/// with an explicit unavailable state. Import is not a runtime compatibility test.
class LegadoSourceImporter {
  const LegadoSourceImporter({this.policy = const RuleSafetyPolicy()});

  final RuleSafetyPolicy policy;

  SourceImportReport importJson(String source) {
    final text = source.replaceFirst('\ufeff', '').trim();
    if (text.isEmpty) throw const FormatException('书源 JSON 为空');
    final decoded = jsonDecode(text);
    final entries = switch (decoded) {
      List value => value,
      Map value when value.containsKey('bookSourceUrl') => [value],
      Map value => _wrappedEntries(value),
      _ => throw const FormatException('书源必须是 JSON 对象或数组'),
    };
    if (entries.length > 10000) {
      throw const FormatException('书源数量超过 10000 个');
    }
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
          enabled: _enabled(config['enabled']),
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

  static List _wrappedEntries(Map decoded) {
    for (final key in const ['bookSourceList', 'sources', 'data']) {
      final value = decoded[key];
      if (value is List) return value;
    }
    throw const FormatException('未找到 bookSourceList、sources 或 data 书源列表');
  }

  static bool _enabled(Object? value) => switch (value) {
    bool enabled => enabled,
    num enabled => enabled != 0,
    String enabled => enabled.toLowerCase() != 'false' && enabled != '0',
    _ => true,
  };
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
    required this.enabled,
    required this.rawConfiguration,
    required this.state,
    required this.unsafePaths,
  });
  final String name;
  final String url;
  final bool enabled;
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
