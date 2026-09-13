import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/features/source_engine/domain/source_switch_service.dart';

void main() {
  test(
    'commits a verified source mapping once and preserves a stale binding',
    () {
      final repository = InMemorySourceBindingRepository();
      final service = SourceSwitchService(repository);
      final initial = service.switchTo(
        bookId: 'b',
        sourceUrl: 'https://one.test',
        locator: Uri.parse('https://one.test/1'),
        verifiedChapterKey: 'one-1',
        expectedRevision: 0,
      );
      expect(initial, isA<SourceSwitchCommitted>());
      final stale = service.switchTo(
        bookId: 'b',
        sourceUrl: 'https://two.test',
        locator: Uri.parse('https://two.test/1'),
        verifiedChapterKey: 'two-1',
        expectedRevision: 0,
      );
      expect(stale, isA<SourceSwitchRejected>());
      expect(repository.bindingFor('b')!.sourceUrl, 'https://one.test');
    },
  );

  test('does not replace a readable binding with an unverified mapping', () {
    final repository = InMemorySourceBindingRepository();
    final service = SourceSwitchService(repository);
    service.switchTo(
      bookId: 'b',
      sourceUrl: 'https://one.test',
      locator: Uri.parse('https://one.test/1'),
      verifiedChapterKey: 'one-1',
      expectedRevision: 0,
    );
    final result = service.switchTo(
      bookId: 'b',
      sourceUrl: 'https://two.test',
      locator: Uri.parse('https://two.test/1'),
      verifiedChapterKey: '',
      expectedRevision: 1,
    );
    expect(result, isA<SourceSwitchRejected>());
    expect(repository.bindingFor('b')!.sourceUrl, 'https://one.test');
  });
}
