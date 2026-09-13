import '../../../core/storage/app_database.dart';

class WebDavSyncSettingsRepository {
  WebDavSyncSettingsRepository(this._database);

  static const _endpointKey = 'sync.webdav.endpoint';
  final AppDatabase _database;

  Uri? get endpoint {
    final value = _database.preference(_endpointKey);
    return value == null ? null : Uri.tryParse(value);
  }

  Future<void> setEndpoint(Uri endpoint) async {
    if (endpoint.scheme != 'https' ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasQuery) {
      throw ArgumentError.value(
        endpoint,
        'endpoint',
        'Use a credential-free HTTPS WebDAV directory URL',
      );
    }
    await _database.transaction((next) {
      final preferences = Map<String, Object?>.from(
        next['preferences']! as Map,
      );
      preferences[_endpointKey] = endpoint.toString();
      next['preferences'] = preferences;
    });
  }

  Future<void> clearEndpoint() => _database.transaction((next) {
    final preferences = Map<String, Object?>.from(next['preferences']! as Map)
      ..remove(_endpointKey);
    next['preferences'] = preferences;
  });
}
