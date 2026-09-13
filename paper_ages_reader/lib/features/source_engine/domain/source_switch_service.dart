class SourceBinding {
  const SourceBinding({
    required this.bookId,
    required this.sourceUrl,
    required this.locator,
    required this.chapterKey,
    required this.revision,
  });
  final String bookId;
  final String sourceUrl;
  final Uri locator;
  final String chapterKey;
  final int revision;
}

sealed class SourceSwitchResult {
  const SourceSwitchResult();
}

class SourceSwitchCommitted extends SourceSwitchResult {
  const SourceSwitchCommitted(this.binding);
  final SourceBinding binding;
}

class SourceSwitchRejected extends SourceSwitchResult {
  const SourceSwitchRejected(this.reason);
  final String reason;
}

abstract interface class SourceBindingRepository {
  SourceBinding? bindingFor(String bookId);
  SourceSwitchResult replaceIfCurrent({
    required SourceBinding next,
    required int expectedRevision,
  });
}

/// Keeps source changes all-or-nothing: a caller must first fetch a readable
/// candidate chapter and supply its stable key. This service cannot infer a
/// mapping merely from chapter ordinal or title.
class SourceSwitchService {
  const SourceSwitchService(this._repository);
  final SourceBindingRepository _repository;

  SourceSwitchResult switchTo({
    required String bookId,
    required Uri locator,
    required String sourceUrl,
    required String verifiedChapterKey,
    required int expectedRevision,
  }) {
    if (verifiedChapterKey.trim().isEmpty) {
      return const SourceSwitchRejected('目标章节尚未验证可读');
    }
    return _repository.replaceIfCurrent(
      next: SourceBinding(
        bookId: bookId,
        sourceUrl: sourceUrl,
        locator: locator,
        chapterKey: verifiedChapterKey,
        revision: expectedRevision + 1,
      ),
      expectedRevision: expectedRevision,
    );
  }
}

class InMemorySourceBindingRepository implements SourceBindingRepository {
  final Map<String, SourceBinding> _bindings = {};
  @override
  SourceBinding? bindingFor(String bookId) => _bindings[bookId];
  @override
  SourceSwitchResult replaceIfCurrent({
    required SourceBinding next,
    required int expectedRevision,
  }) {
    final current = _bindings[next.bookId];
    if ((current?.revision ?? 0) != expectedRevision) {
      return const SourceSwitchRejected('书源已被其他操作更新');
    }
    _bindings[next.bookId] = next;
    return SourceSwitchCommitted(next);
  }
}
