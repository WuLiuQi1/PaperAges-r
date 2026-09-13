import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/features/sync/domain/sync_whitelist_policy.dart';

void main() {
  const policy = SyncWhitelistPolicy();

  Map<String, Object?> eventWith(Map<String, Object?> payload) => {
    'schemaVersion': 1,
    'eventId': 'event-1',
    'deviceId': 'device-a',
    'deviceSeq': 1,
    'entityKey': 'book:book-1',
    'parentEventIds': <String>[],
    'type': 'position.updated',
    'payloadHash': 'sha256:fixture',
    'payload': payload,
  };

  test('allows shelf metadata and a content anchor only', () {
    final report = policy.inspect(
      eventWith({
        'bookId': 'book-1',
        'kind': 'txt',
        'title': 'Fixture',
        'author': 'Test',
        'shelfState': 'active',
        'anchor': {
          'editionId': 'edition-1',
          'chapterKey': 'chapter-1',
          'blockId': 'block-1',
          'offsetUtf16': 42,
          'contextHash': 'hash',
          'normalizationVersion': 1,
        },
      }),
    );

    expect(report.isSafeToUpload, isTrue);
  });

  test('rejects local files, body text, fonts, audio and credentials', () {
    final report = policy.inspect(
      eventWith({
        'bookId': 'book-1',
        'localPath': 'C:/private/book.txt',
        'chapterBody': 'must never upload',
        'fontFile': 'font.ttf',
        'audioCache': 'speech.m4a',
        'password': 'secret',
      }),
    );

    expect(report.isSafeToUpload, isFalse);
    expect(
      report.issues.where(
        (issue) => issue.code == SyncWhitelistCode.forbiddenField,
      ),
      hasLength(5),
    );
  });

  test('rejects private token-bearing source locators', () {
    final report = policy.inspect(
      eventWith({
        'bookId': 'book-1',
        'sourceLocator': 'https://reader.example/book?id=1&token=private',
      }),
    );

    expect(report.isSafeToUpload, isFalse);
    expect(report.issues.single.code, SyncWhitelistCode.sensitiveLocator);
  });

  test('rejects unknown anchor fields instead of silently syncing them', () {
    final report = policy.inspect(
      eventWith({
        'bookId': 'book-1',
        'anchor': {'chapterKey': 'one', 'screenPage': 72},
      }),
    );

    expect(report.isSafeToUpload, isFalse);
    expect(report.issues.single.path, r'$.payload.anchor.screenPage');
  });
}
