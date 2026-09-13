import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/features/source_engine/application/legado_source_importer.dart';

void main() {
  const importer = LegadoSourceImporter();

  test('imports a static Legado source as ready without evaluating a rule', () {
    final result = importer.importJson(
      '[{"bookSourceName":"static","bookSourceUrl":"https://example.test","ruleSearch":{"name":".title@text"}}]',
    );
    expect(result.failures, isEmpty);
    expect(result.imported.single.state, SourceImportState.ready);
  });

  test('keeps a JavaScript-bearing source visible but disabled', () {
    final result = importer.importJson(
      '[{"bookSourceName":"legacy","bookSourceUrl":"https://example.test","ruleSearch":{"cover":"@js: result"}}]',
    );
    final source = result.imported.single;
    expect(source.state, SourceImportState.disabledUnsafeRule);
    expect(source.unsafePaths, contains(r'$.ruleSearch.cover'));
    expect(source.rawConfiguration['bookSourceName'], 'legacy');
  });

  test('reports malformed entries without losing valid neighboring sources', () {
    final result = importer.importJson(
      '[false,{"bookSourceName":"ok","bookSourceUrl":"https://example.test"}]',
    );
    expect(result.failures.single.index, 0);
    expect(result.imported.single.name, 'ok');
  });
}
