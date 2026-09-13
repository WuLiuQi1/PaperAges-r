import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../domain/immutable_event_merge.dart';

/// Credentials are deliberately ephemeral at this boundary. A platform secure
/// storage implementation may supply them, but this transport never persists
/// or logs either component.
class WebDavCredentials {
  const WebDavCredentials({required this.username, required this.password});

  final String username;
  final String password;
}

class WebDavTransportException implements Exception {
  const WebDavTransportException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'WebDavTransportException($message)';
}

/// Immutable-event WebDAV transport. It uses one unique file per event and
/// only reports success after a readback can be hash-validated by [codec].
class WebDavEventTransport {
  WebDavEventTransport({
    required Uri root,
    required this.credentials,
    http.Client? client,
    SyncEventCodec? codec,
  }) : _root = _directory(root),
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _codec = codec ?? const SyncEventCodec();

  final Uri _root;
  final WebDavCredentials credentials;
  final http.Client _client;
  final bool _ownsClient;
  final SyncEventCodec _codec;

  static Uri _directory(Uri value) =>
      value.path.endsWith('/') ? value : value.replace(path: '${value.path}/');

  Uri eventUri(SyncEvent event) {
    _validatePathPart(event.deviceId, 'deviceId');
    _validatePathPart(event.eventId, 'eventId');
    return _root.resolve(
      'reader-sync/v1/devices/${event.deviceId}/events/'
      '${event.deviceSeq}-${event.eventId}.json',
    );
  }

  Future<void> upload(SyncEvent event) async {
    final target = eventUri(event);
    final put = http.Request('PUT', target)
      ..headers.addAll(_headers())
      ..headers['If-None-Match'] = '*'
      ..headers['Content-Type'] = 'application/json; charset=utf-8'
      ..body = jsonEncode(event.toJson());
    final response = await _client.send(put);
    await response.stream.drain();
    if (response.statusCode != 200 &&
        response.statusCode != 201 &&
        response.statusCode != 204) {
      throw WebDavTransportException(
        'Event upload failed',
        statusCode: response.statusCode,
      );
    }
    final echoed = await read(target);
    if (echoed.eventId != event.eventId ||
        echoed.payloadHash != event.payloadHash) {
      throw const WebDavTransportException(
        'Event readback did not match upload',
      );
    }
  }

  Future<SyncEvent> read(Uri target) async {
    final response = await _client.get(target, headers: _headers());
    if (response.statusCode != 200) {
      throw WebDavTransportException(
        'Event read failed',
        statusCode: response.statusCode,
      );
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) throw const FormatException('JSON object required');
      return _codec.decode(Map<String, Object?>.from(decoded));
    } on FormatException catch (error) {
      throw WebDavTransportException('Invalid remote event: ${error.message}');
    }
  }

  /// Lists event hrefs. XML namespace prefixes are ignored by the XML parser;
  /// only paths below this app's immutable event directory are returned.
  Future<List<Uri>> listEventUris(String deviceId) async {
    _validatePathPart(deviceId, 'deviceId');
    final collection = _root.resolve(
      'reader-sync/v1/devices/$deviceId/events/',
    );
    final request = http.Request('PROPFIND', collection)
      ..headers.addAll(_headers())
      ..headers['Depth'] = '1'
      ..headers['Content-Type'] = 'application/xml; charset=utf-8'
      ..body =
          '<?xml version="1.0"?><propfind xmlns="DAV:"><prop><getetag/></prop></propfind>';
    final streamed = await _client.send(request);
    final bytes = await streamed.stream.toBytes();
    if (streamed.statusCode != 207) {
      throw WebDavTransportException(
        'Event listing failed',
        statusCode: streamed.statusCode,
      );
    }
    try {
      final document = XmlDocument.parse(utf8.decode(bytes));
      final prefix = collection.path;
      return document.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 'href')
          .map((element) => element.innerText.trim())
          .map((href) => collection.resolve(href))
          .where(
            (uri) => uri.path.startsWith(prefix) && uri.path.endsWith('.json'),
          )
          .toSet()
          .toList(growable: false);
    } on XmlParserException catch (error) {
      throw WebDavTransportException('Invalid WebDAV listing: $error');
    } on FormatException catch (error) {
      throw WebDavTransportException('Invalid WebDAV listing encoding: $error');
    }
  }
  /*
    } on XmlազանցException catch (error) {
      throw WebDavTransportException('Invalid WebDAV listing: $error');
    } on FormatException catch (error) {
      throw WebDavTransportException('Invalid WebDAV listing encoding: $error');
    }
  }

  */

  Map<String, String> _headers() => {
    'Authorization':
        'Basic ${base64Encode(utf8.encode('${credentials.username}:${credentials.password}'))}',
  };

  static void _validatePathPart(String value, String field) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,160}$').hasMatch(value)) {
      throw ArgumentError.value(
        value,
        field,
        'Must be a safe opaque identifier',
      );
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
