import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Versioned local state with atomic replacement. An interrupted write leaves
/// the previous index usable; imported book files live in a separate folder.
class AppDatabase {
  AppDatabase._(this._file);

  final File _file;
  final _changes = StreamController<void>.broadcast();
  Map<String, Object?> _data = _empty();

  static Future<AppDatabase> defaults() async {
    final directory = await getApplicationDocumentsDirectory();
    final database = AppDatabase._(
      File('${directory.path}${Platform.pathSeparator}paper_ages_state.json'),
    );
    await database._open();
    return database;
  }

  static Map<String, Object?> _empty() => {
    'schemaVersion': 3,
    'books': <Object?>[],
    'positions': <String, Object?>{},
    'preferences': <String, Object?>{},
    'sources': <Object?>[],
    'networkBooks': <Object?>[],
  };

  Future<void> _open() async {
    if (!await _file.exists()) return;
    final decoded = jsonDecode(await _file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Unsupported local library database version');
    }
    _data = Map<String, Object?>.from(decoded);
    final version = _data['schemaVersion'];
    if (version == 1) {
      _data['schemaVersion'] = 3;
      _data['sources'] = <Object?>[];
      _data['networkBooks'] = <Object?>[];
      await _write(_data);
    } else if (version == 2) {
      _data['schemaVersion'] = 3;
      _data['networkBooks'] = <Object?>[];
      await _write(_data);
    } else if (version != 3) {
      throw const FormatException('Unsupported local library database version');
    }
  }

  Stream<List<Map<String, Object?>>> watchBooks() async* {
    yield books;
    yield* _changes.stream.map((_) => books);
  }

  Stream<List<Map<String, Object?>>> watchSources() async* {
    yield sources;
    yield* _changes.stream.map((_) => sources);
  }

  Stream<List<Map<String, Object?>>> watchNetworkBooks() async* {
    yield networkBooks;
    yield* _changes.stream.map((_) => networkBooks);
  }

  List<Map<String, Object?>> get books => List.unmodifiable(
    ((_data['books'] as List<Object?>?) ?? const <Object?>[])
        .whereType<Map>()
        .map((row) => Map<String, Object?>.from(row)),
  );

  List<Map<String, Object?>> get sources => List.unmodifiable(
    ((_data['sources'] as List<Object?>?) ?? const <Object?>[])
        .whereType<Map>()
        .map((row) => Map<String, Object?>.from(row)),
  );

  List<Map<String, Object?>> get networkBooks => List.unmodifiable(
    ((_data['networkBooks'] as List<Object?>?) ?? const <Object?>[])
        .whereType<Map>()
        .map((row) => Map<String, Object?>.from(row)),
  );

  Map<String, Object?>? position(String bookId) {
    final raw = Map<String, Object?>.from(_data['positions']! as Map)[bookId];
    return raw is Map ? Map<String, Object?>.from(raw) : null;
  }

  String? preference(String key) =>
      Map<String, Object?>.from(_data['preferences']! as Map)[key] as String?;

  Future<void> transaction(
    void Function(Map<String, Object?> next) change,
  ) async {
    final next = Map<String, Object?>.from(_data)
      ..['books'] = List<Object?>.from(_data['books']! as List)
      ..['positions'] = Map<String, Object?>.from(_data['positions']! as Map)
      ..['preferences'] = Map<String, Object?>.from(
        _data['preferences']! as Map,
      )
      ..['sources'] = List<Object?>.from(_data['sources']! as List)
      ..['networkBooks'] = List<Object?>.from(_data['networkBooks']! as List);
    change(next);
    await _write(next);
    _data = next;
    _changes.add(null);
  }

  Future<void> _write(Map<String, Object?> value) async {
    final temporary = File('${_file.path}.part');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    await temporary.rename(_file.path);
  }

  Future<void> close() => _changes.close();
}
