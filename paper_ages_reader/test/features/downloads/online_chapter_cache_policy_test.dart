import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/features/downloads/application/online_chapter_cache_policy.dart';
import 'package:paper_ages_reader/features/downloads/data/chapter_cache.dart';

void main() {
  const policy = OnlineChapterCachePolicy();

  test('first shelf add warms only the first chapter', () {
    expect(
      policy.indexes(
        reason: OnlineChapterWarmReason.shelfAdded,
        chapterCount: 30,
      ),
      [0],
    );
  });

  test('reading chapter 24 keeps chapter 24 and 25 available', () {
    expect(
      policy.indexes(
        reason: OnlineChapterWarmReason.reading,
        chapterCount: 30,
        currentIndex: 23,
      ),
      [23, 24],
    );
  });

  test('source switch warms mapped target and its successor', () {
    expect(
      policy.indexes(
        reason: OnlineChapterWarmReason.sourceSwitched,
        chapterCount: 30,
        currentIndex: 23,
      ),
      [23, 24],
    );
  });

  test('last chapter does not request an out-of-range successor', () {
    expect(
      policy.indexes(
        reason: OnlineChapterWarmReason.reading,
        chapterCount: 24,
        currentIndex: 23,
      ),
      [23],
    );
  });

  test('one failed warm does not prevent the remaining disk write', () async {
    final loaded = <int>[];
    final failures = await policy.warm(
      reason: OnlineChapterWarmReason.reading,
      chapterCount: 4,
      currentIndex: 1,
      loadAndPersist: (index) async {
        if (index == 1) throw StateError('offline');
        loaded.add(index);
      },
    );
    expect(failures.single.chapterIndex, 1);
    expect(loaded, [2]);
  });

  test('reading window survives a cache object restart', () async {
    final directory = await Directory.systemTemp.createTemp('chapter-window-');
    addTearDown(() => directory.delete(recursive: true));
    ChapterCacheKey keyFor(int index) => ChapterCacheKey(
      sourceUrl: 'https://source.test',
      sourceVersion: 'v1',
      locator: Uri.parse('https://source.test/chapter/${index + 1}'),
      chapterKey: '${index + 1}',
      contentRevision: 'v1',
    );
    final writer = ChapterCache(directory);
    await policy.warm(
      reason: OnlineChapterWarmReason.reading,
      chapterCount: 30,
      currentIndex: 23,
      loadAndPersist: (index) => writer.write(keyFor(index), '第${index + 1}章'),
    );

    final reopened = ChapterCache(directory);
    expect(await reopened.read(keyFor(23)), '第24章');
    expect(await reopened.read(keyFor(24)), '第25章');
  });
}
