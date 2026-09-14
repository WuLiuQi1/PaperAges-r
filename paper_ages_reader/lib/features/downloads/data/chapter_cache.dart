import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

class ChapterCacheKey {
  const ChapterCacheKey({
    required this.sourceUrl,
    required this.sourceVersion,
    required this.locator,
    required this.chapterKey,
    required this.contentRevision,
  });
  final String sourceUrl;
  final String sourceVersion;
  final Uri locator;
  final String chapterKey;
  final String contentRevision;
  String get fingerprint => sha256
      .convert(
        utf8.encode(
          '$sourceUrl\n$sourceVersion\n$locator\n$chapterKey\n$contentRevision',
        ),
      )
      .toString();
}

/// Network chapter bodies only. It never shares a folder with imported TXT/PDF
/// or user fonts, so a cache cleanup cannot erase user-owned files.
class ChapterCache {
  ChapterCache(this._directory);
  final Directory _directory;

  static Future<ChapterCache> defaults() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}chapter_cache',
    );
    await directory.create(recursive: true);
    return ChapterCache(directory);
  }

  Future<String?> read(ChapterCacheKey key) async {
    final file = File(
      '${_directory.path}${Platform.pathSeparator}${key.fingerprint}.txt',
    );
    return await file.exists() ? file.readAsString() : null;
  }

  Future<void> write(ChapterCacheKey key, String content) async {
    final file = File(
      '${_directory.path}${Platform.pathSeparator}${key.fingerprint}.txt',
    );
    final temporary = File('${file.path}.part');
    await temporary.writeAsString(content, flush: true);
    await temporary.rename(file.path);
  }

  Future<List<CachedChapterRecord>?> readCatalog(String bookId) async {
    final file = File(
      '${_directory.path}${Platform.pathSeparator}catalog-${_catalogFingerprint(bookId)}.json',
    );
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return null;
      return decoded
          .whereType<Map>()
          .map(
            (row) => CachedChapterRecord.fromJson(
              row.map((key, value) => MapEntry('$key', value)),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeCatalog(
    String bookId,
    List<CachedChapterRecord> chapters,
  ) async {
    final file = File(
      '${_directory.path}${Platform.pathSeparator}catalog-${_catalogFingerprint(bookId)}.json',
    );
    final temporary = File('${file.path}.part');
    await temporary.writeAsString(
      jsonEncode(chapters.map((chapter) => chapter.toJson()).toList()),
      flush: true,
    );
    await temporary.rename(file.path);
  }

  String _catalogFingerprint(String bookId) =>
      sha256.convert(utf8.encode(bookId)).toString();

  Future<void> clearNetworkCache() async {
    if (!(await _directory.exists())) return;
    await for (final entity in _directory.list()) {
      if (entity is File &&
          (entity.path.endsWith('.txt') ||
              entity.path.endsWith('.json') ||
              entity.path.endsWith('.part'))) {
        await entity.delete();
      }
    }
  }
}

class CachedChapterRecord {
  const CachedChapterRecord({
    required this.key,
    required this.title,
    required this.locator,
    required this.ordinal,
    this.bookLocator,
  });

  final String key;
  final String title;
  final Uri locator;
  final int ordinal;
  final Uri? bookLocator;

  Map<String, Object?> toJson() => {
    'key': key,
    'title': title,
    'locator': locator.toString(),
    'ordinal': ordinal,
    if (bookLocator != null) 'bookLocator': bookLocator.toString(),
  };

  factory CachedChapterRecord.fromJson(Map<String, Object?> row) =>
      CachedChapterRecord(
        key: row['key']! as String,
        title: row['title']! as String,
        locator: Uri.parse(row['locator']! as String),
        ordinal: row['ordinal']! as int,
        bookLocator: row['bookLocator'] == null
            ? null
            : Uri.tryParse(row['bookLocator']! as String),
      );
}
