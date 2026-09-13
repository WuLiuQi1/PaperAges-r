/// A deliberately conservative preflight for imported source configuration.
///
/// This policy does not parse or execute a book-source rule. Its sole job is to
/// reject known dynamic-execution entry points before an importer can hand a
/// configuration to any network or extraction implementation.
class RuleSafetyPolicy {
  const RuleSafetyPolicy();

  RuleSafetyReport inspect(Object? configuration) {
    final issues = <RuleSafetyIssue>[];
    _inspectNode(configuration, r'$', issues);
    return RuleSafetyReport(List.unmodifiable(issues));
  }

  void _inspectNode(Object? node, String path, List<RuleSafetyIssue> issues) {
    switch (node) {
      case Map<Object?, Object?> values:
        for (final entry in values.entries) {
          final key = entry.key.toString();
          final childPath = '$path.$key';
          final keyIssue = _unsafeKey(key);
          if (keyIssue != null) {
            issues.add(RuleSafetyIssue(childPath, keyIssue));
          }
          _inspectNode(entry.value, childPath, issues);
        }
      case Iterable<Object?> values:
        var index = 0;
        for (final value in values) {
          _inspectNode(value, '$path[$index]', issues);
          index++;
        }
      case String value:
        final valueIssue = _unsafeValue(value);
        if (valueIssue != null) {
          issues.add(RuleSafetyIssue(path, valueIssue));
        }
    }
  }

  RuleSafetyCode? _unsafeKey(String key) {
    final normalized = key.trim().toLowerCase();
    if (normalized.contains('javascript') || normalized == 'js') {
      return RuleSafetyCode.javaScriptKey;
    }
    if (normalized.contains('script')) {
      return RuleSafetyCode.scriptKey;
    }
    if (normalized.contains('webview') || normalized.contains('bridge')) {
      return RuleSafetyCode.executionBridgeKey;
    }
    return null;
  }

  RuleSafetyCode? _unsafeValue(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.contains('@js') || normalized.contains('<js>')) {
      return RuleSafetyCode.javaScriptDirective;
    }
    if (normalized.contains('<script') || normalized.contains('</script')) {
      return RuleSafetyCode.scriptMarkup;
    }
    if (normalized.startsWith('javascript:') || normalized.contains('eval(')) {
      return RuleSafetyCode.javaScriptExpression;
    }
    if (normalized.contains('loadlibrary(') ||
        normalized.contains('nativebridge')) {
      return RuleSafetyCode.dynamicLibraryOrBridge;
    }
    return null;
  }
}

class RuleSafetyReport {
  const RuleSafetyReport(this.issues);

  final List<RuleSafetyIssue> issues;

  bool get isSafe => issues.isEmpty;
}

class RuleSafetyIssue {
  const RuleSafetyIssue(this.path, this.code);

  final String path;
  final RuleSafetyCode code;
}

enum RuleSafetyCode {
  javaScriptKey,
  scriptKey,
  executionBridgeKey,
  javaScriptDirective,
  scriptMarkup,
  javaScriptExpression,
  dynamicLibraryOrBridge,
}
