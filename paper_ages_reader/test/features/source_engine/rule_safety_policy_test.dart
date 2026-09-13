import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/features/source_engine/domain/rule_safety_policy.dart';

void main() {
  const policy = RuleSafetyPolicy();

  test('accepts a static CSS-style source configuration', () {
    final report = policy.inspect({
      'bookSourceUrl': 'https://example.test/search?q={{key}}',
      'ruleSearch': {'bookList': '.book', 'name': 'a.title@text'},
    });

    expect(report.isSafe, isTrue);
    expect(report.issues, isEmpty);
  });

  test('rejects explicit JavaScript directives before execution', () {
    final report = policy.inspect({'ruleSearch': '@js: fetch(key)'});

    expect(report.isSafe, isFalse);
    expect(report.issues.single.code, RuleSafetyCode.javaScriptDirective);
  });

  test('rejects nested script markup and JavaScript keys', () {
    final report = policy.inspect({
      'ruleContent': {
        'steps': [
          {'JavaScript': 'return document.body.innerText'},
          '<script>fetch("https://example.test")</script>',
        ],
      },
    });

    expect(report.isSafe, isFalse);
    expect(
      report.issues.map((issue) => issue.code),
      containsAll(<RuleSafetyCode>[
        RuleSafetyCode.javaScriptKey,
        RuleSafetyCode.scriptMarkup,
      ]),
    );
  });

  test('rejects dynamic libraries and execution bridges at any depth', () {
    final report = policy.inspect({
      'ruleContent': [
        {'parser': 'loadLibrary("unsafe")'},
        {'webViewBridge': 'enabled'},
        {'next': 'javascript:alert(1)'},
      ],
    });

    expect(report.isSafe, isFalse);
    expect(
      report.issues.map((issue) => issue.code),
      containsAll(<RuleSafetyCode>[
        RuleSafetyCode.dynamicLibraryOrBridge,
        RuleSafetyCode.executionBridgeKey,
        RuleSafetyCode.javaScriptExpression,
      ]),
    );
  });
}
