import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paper_ages_reader/core/storage/app_database.dart';
import 'package:paper_ages_reader/features/sync/data/webdav_sync_settings_repository.dart';

void main() {
  late AppDatabase database;
  late WebDavSyncSettingsRepository repository;

  setUp(() async {
    final directory = await Directory.systemTemp.createTemp(
      'paper-ages-settings-',
    );
    addTearDown(() => directory.delete(recursive: true));
    database = await AppDatabase.openFile(File('${directory.path}/state.json'));
    repository = WebDavSyncSettingsRepository(database);
    addTearDown(database.close);
  });

  test('persists only a credential-free HTTPS endpoint', () async {
    await repository.setEndpoint(Uri.parse('https://dav.example/reader/'));
    expect(repository.endpoint, Uri.parse('https://dav.example/reader/'));
    expect(
      database.preference('sync.webdav.endpoint'),
      isNot(contains('password')),
    );
  });

  test('rejects insecure or credential-bearing endpoints', () async {
    await expectLater(
      repository.setEndpoint(Uri.parse('http://dav.example/reader/')),
      throwsArgumentError,
    );
    await expectLater(
      repository.setEndpoint(Uri.parse('https://name:secret@dav.example/')),
      throwsArgumentError,
    );
    await expectLater(
      repository.setEndpoint(Uri.parse('https://dav.example/?token=bad')),
      throwsArgumentError,
    );
  });
}
