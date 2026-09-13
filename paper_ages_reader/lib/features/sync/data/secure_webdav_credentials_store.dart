import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'webdav_event_transport.dart';

/// Stores only WebDAV credentials in the operating system secure store.
/// Endpoint URLs and all sync data remain outside this adapter.
class SecureWebDavCredentialsStore {
  SecureWebDavCredentialsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _usernameKey = 'paper_ages.webdav.username';
  static const _passwordKey = 'paper_ages.webdav.password';
  final FlutterSecureStorage _storage;

  Future<void> save(WebDavCredentials credentials) async {
    await _storage.write(key: _usernameKey, value: credentials.username);
    await _storage.write(key: _passwordKey, value: credentials.password);
  }

  Future<WebDavCredentials?> read() async {
    final username = await _storage.read(key: _usernameKey);
    final password = await _storage.read(key: _passwordKey);
    if (username == null || password == null) return null;
    return WebDavCredentials(username: username, password: password);
  }

  Future<void> clear() async {
    await _storage.delete(key: _usernameKey);
    await _storage.delete(key: _passwordKey);
  }
}
