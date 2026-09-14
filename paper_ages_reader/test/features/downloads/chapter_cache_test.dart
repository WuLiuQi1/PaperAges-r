import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/features/downloads/data/chapter_cache.dart';

void main() {
  test(
    'atomic chapter cache is source-bound and does not clear unrelated files',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'paper-ages-cache-test-',
      );
      addTearDown(() => root.delete(recursive: true));
      final cache = ChapterCache(
        Directory('${root.path}${Platform.pathSeparator}network')..createSync(),
      );
      final imported = File('${root.path}${Platform.pathSeparator}imported.txt')
        ..writeAsStringSync('keep');
      final key = ChapterCacheKey(
        sourceUrl: 'https://example.test',
        sourceVersion: 'v1',
        locator: Uri.parse('https://example.test/chapter/1'),
        chapterKey: '1',
        contentRevision: 'r1',
      );
      await cache.write(key, '正文');
      await cache.writeCatalog('book|source-a', [
        CachedChapterRecord(
          key: '1',
          title: '第一章',
          locator: Uri.parse('https://example.test/chapter/1'),
          ordinal: 0,
          bookLocator: Uri.parse('https://example.test/book'),
        ),
      ]);
      expect(await cache.read(key), '正文');
      final reopened = ChapterCache(
        Directory('${root.path}${Platform.pathSeparator}network'),
      );
      expect(
        (await reopened.readCatalog('book|source-a'))!.single.title,
        '第一章',
      );
      expect(await reopened.readCatalog('book|source-b'), isNull);
      expect(
        await cache.read(
          ChapterCacheKey(
            sourceUrl: 'https://other.test',
            sourceVersion: 'v1',
            locator: Uri.parse('https://other.test/chapter/1'),
            chapterKey: '1',
            contentRevision: 'r1',
          ),
        ),
        isNull,
      );
      await cache.clearNetworkCache();
      expect(await cache.read(key), isNull);
      expect(await cache.readCatalog('book|source-a'), isNull);
      expect(await imported.readAsString(), 'keep');
    },
  );
}
