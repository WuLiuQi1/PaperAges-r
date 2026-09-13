import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:paper_ages_reader/features/sync/data/webdav_event_transport.dart';
import 'package:paper_ages_reader/features/sync/domain/immutable_event_merge.dart';

void main() {
  final event = const SyncEventCodec().create(
    eventId: 'event_a',
    deviceId: 'device_a',
    deviceSeq: 7,
    entityKey: 'book:a',
    parentEventIds: const {},
    type: SyncEventType.shelfUpdated,
    payload: {'bookId': 'a', 'shelfState': 'joined'},
  );

  test(
    'uses a unique conditional PUT then verifies a readable event',
    () async {
      final client = _RecordingClient((request) async {
        if (request.method == 'PUT') {
          expect(request.headers['if-none-match'], '*');
          return http.Response('', 201);
        }
        return http.Response(jsonEncode(event.toJson()), 200);
      });
      final transport = WebDavEventTransport(
        root: Uri.parse('https://dav.example/root/'),
        credentials: const WebDavCredentials(
          username: 'reader',
          password: 'secret',
        ),
        client: client,
      );
      await transport.upload(event);
      expect(client.requests.map((request) => request.method), ['PUT', 'GET']);
      expect(
        client.requests.first.url.path,
        contains('device_a/events/7-event_a.json'),
      );
      expect(
        client.requests.first.headers['authorization'],
        startsWith('Basic '),
      );
    },
  );

  test('leaves a conditional failure visible to the caller', () async {
    final transport = WebDavEventTransport(
      root: Uri.parse('https://dav.example/root'),
      credentials: const WebDavCredentials(
        username: 'reader',
        password: 'secret',
      ),
      client: _RecordingClient((_) async => http.Response('', 412)),
    );
    expect(transport.upload(event), throwsA(isA<WebDavTransportException>()));
  });

  test('parses DAV namespace hrefs and excludes collection entries', () async {
    final transport = WebDavEventTransport(
      root: Uri.parse('https://dav.example/root/'),
      credentials: const WebDavCredentials(
        username: 'reader',
        password: 'secret',
      ),
      client: _RecordingClient(
        (_) async => http.Response('''
        <d:multistatus xmlns:d="DAV:">
          <d:response><d:href>/root/reader-sync/v1/devices/device_a/events/</d:href></d:response>
          <d:response><d:href>/root/reader-sync/v1/devices/device_a/events/7-event_a.json</d:href></d:response>
        </d:multistatus>''', 207),
      ),
    );
    final listed = await transport.listEventUris('device_a');
    expect(listed.single.path, endsWith('7-event_a.json'));
  });

  test('rejects an unsafe device identifier before sending credentials', () {
    final transport = WebDavEventTransport(
      root: Uri.parse('https://dav.example/root/'),
      credentials: const WebDavCredentials(
        username: 'reader',
        password: 'secret',
      ),
      client: _RecordingClient((_) async => http.Response('', 500)),
    );
    expect(() => transport.listEventUris('../private'), throwsArgumentError);
  });
}

class _RecordingClient extends http.BaseClient {
  _RecordingClient(this._handler);

  final Future<http.Response> Function(http.Request request) _handler;
  final requests = <http.Request>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final copied = http.Request(request.method, request.url)
      ..headers.addAll(request.headers);
    requests.add(copied);
    final response = await _handler(copied);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}
