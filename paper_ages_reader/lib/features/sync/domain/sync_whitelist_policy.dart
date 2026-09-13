/// Validates an immutable WebDAV event before it enters an upload outbox.
///
/// Validation is deny-by-default: unknown event or payload fields must be
/// modelled intentionally before they can cross a device boundary.
class SyncWhitelistPolicy {
  const SyncWhitelistPolicy();

  static const _eventKeys = {
    'schemaVersion',
    'eventId',
    'deviceId',
    'deviceSeq',
    'entityKey',
    'parentEventIds',
    'type',
    'payloadHash',
    'payload',
  };

  static const _payloadKeys = {
    'bookId',
    'kind',
    'title',
    'author',
    'createdAt',
    'deletedAt',
    'shelfState',
    'bindingRevision',
    'sourceLocator',
    'anchor',
  };

  static const _anchorKeys = {
    'editionId',
    'chapterKey',
    'blockId',
    'offsetUtf16',
    'contextHash',
    'normalizationVersion',
    'documentFingerprint',
    'pageIndex',
    'normalizedViewportPosition',
  };

  SyncWhitelistReport inspect(Map<String, Object?> event) {
    final issues = <SyncWhitelistIssue>[];
    _findUnknownKeys(event, _eventKeys, r'$', issues);

    final payload = event['payload'];
    if (payload is! Map<String, Object?>) {
      issues.add(
        const SyncWhitelistIssue(
          r'$.payload',
          SyncWhitelistCode.invalidPayload,
        ),
      );
    } else {
      _findUnknownKeys(payload, _payloadKeys, r'$.payload', issues);
      final anchor = payload['anchor'];
      if (anchor != null && anchor is! Map<String, Object?>) {
        issues.add(
          const SyncWhitelistIssue(
            r'$.payload.anchor',
            SyncWhitelistCode.invalidAnchor,
          ),
        );
      } else if (anchor case final Map<String, Object?> value) {
        _findUnknownKeys(value, _anchorKeys, r'$.payload.anchor', issues);
      }
      final locator = payload['sourceLocator'];
      if (locator is String && _hasSensitiveLocatorPart(locator)) {
        issues.add(
          const SyncWhitelistIssue(
            r'$.payload.sourceLocator',
            SyncWhitelistCode.sensitiveLocator,
          ),
        );
      }
    }
    return SyncWhitelistReport(List.unmodifiable(issues));
  }

  void _findUnknownKeys(
    Map<String, Object?> values,
    Set<String> allowed,
    String path,
    List<SyncWhitelistIssue> issues,
  ) {
    for (final key in values.keys) {
      if (!allowed.contains(key)) {
        issues.add(
          SyncWhitelistIssue('$path.$key', SyncWhitelistCode.forbiddenField),
        );
      }
    }
  }

  bool _hasSensitiveLocatorPart(String locator) {
    final normalized = locator.toLowerCase();
    return normalized.contains('token=') ||
        normalized.contains('password=') ||
        normalized.contains('cookie=') ||
        normalized.contains('authorization=') ||
        normalized.contains('apikey=') ||
        normalized.contains('api_key=');
  }
}

class SyncWhitelistReport {
  const SyncWhitelistReport(this.issues);

  final List<SyncWhitelistIssue> issues;

  bool get isSafeToUpload => issues.isEmpty;
}

class SyncWhitelistIssue {
  const SyncWhitelistIssue(this.path, this.code);

  final String path;
  final SyncWhitelistCode code;
}

enum SyncWhitelistCode {
  forbiddenField,
  invalidPayload,
  invalidAnchor,
  sensitiveLocator,
}
