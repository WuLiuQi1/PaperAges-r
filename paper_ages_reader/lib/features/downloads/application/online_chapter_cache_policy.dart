enum OnlineChapterWarmReason { shelfAdded, reading, sourceSwitched }

/// Defines the durable online-reading window without coupling cache policy to
/// a particular screen. The loader supplied by the caller must write a
/// successfully fetched chapter to the on-disk [ChapterCache].
class OnlineChapterCachePolicy {
  const OnlineChapterCachePolicy();

  List<int> indexes({
    required OnlineChapterWarmReason reason,
    required int chapterCount,
    int currentIndex = 0,
  }) {
    if (chapterCount <= 0) return const [];
    final current = currentIndex.clamp(0, chapterCount - 1);
    return switch (reason) {
      OnlineChapterWarmReason.shelfAdded => const [0],
      OnlineChapterWarmReason.reading ||
      OnlineChapterWarmReason.sourceSwitched => [
        current,
        if (current + 1 < chapterCount) current + 1,
      ],
    };
  }

  Future<List<OnlineChapterWarmFailure>> warm({
    required OnlineChapterWarmReason reason,
    required int chapterCount,
    required Future<void> Function(int index) loadAndPersist,
    int currentIndex = 0,
  }) async {
    final failures = <OnlineChapterWarmFailure>[];
    for (final index in indexes(
      reason: reason,
      chapterCount: chapterCount,
      currentIndex: currentIndex,
    )) {
      try {
        await loadAndPersist(index);
      } catch (error) {
        failures.add(OnlineChapterWarmFailure(index, error));
      }
    }
    return failures;
  }
}

class OnlineChapterWarmFailure {
  const OnlineChapterWarmFailure(this.chapterIndex, this.error);

  final int chapterIndex;
  final Object error;
}
