import 'dart:convert';
import 'dart:io';

import 'package:flutter_js/flutter_js.dart';

typedef SourceScriptEvaluator = Object? Function(
  String code,
  Object? result,
  Map<String, Object?> variables,
  String? Function(String) getString,
);

/// Explicit source-rule scripts only. HTML script tags are never auto-executed.
Object? evaluateSourceScript(
  String code,
  Object? result,
  Map<String, Object?> variables,
  String? Function(String) getString,
) {
  final JavascriptRuntime runtime = Platform.isIOS || Platform.isMacOS
      ? getJavascriptRuntime(xhr: false)
      : QuickJsRuntime2(timeout: 1000);
  try {
    runtime.onMessage(
      'getString',
      (dynamic args) => getString(args.toString()),
    );
    final setup = runtime.evaluate('''
var result = ${jsonEncode(result)};
var key = ${jsonEncode(variables['key'] ?? '')};
var page = ${jsonEncode(variables['page'] ?? 1)};
var baseUrl = ${jsonEncode(variables['baseUrl'] ?? '')};
var java = {
  getString: function(rule) { return sendMessage('getString', JSON.stringify(rule)); },
  get: function(key) { return this._values[key] || ''; },
  put: function(key, value) { this._values[key] = String(value); return value; },
  _values: {}
};
''');
    if (setup.isError) throw FormatException(setup.stringResult);
    final evaluated = runtime.evaluate(
      'JSON.stringify((0,eval)(${jsonEncode(code)}))',
    );
    if (evaluated.isError) throw FormatException(evaluated.stringResult);
    if (evaluated.stringResult == 'undefined') return null;
    return jsonDecode(evaluated.stringResult);
  } finally {
    runtime.dispose();
  }
}
