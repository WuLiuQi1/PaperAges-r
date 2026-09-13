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
    'schemaVersion': 1,
    'books': <Object?>[],
    'positions': <String, Object?>{},
    'preferences': <String, Object?>{},
  };

  Future<void> _open() async {
    if (!await _file.exists()) return;
    final decoded = jsonDecode(await _file.readAsString());
    if (decoded is! Map<String, dynamic> || decoded['schemaVersion'] != 1) {
      throw const FormatException('Unsupported local library database version');
    }
    _data = Map<String, Object?>.from(decoded);
  }

  Stream<List<Map<String, Object?>>> watchBooks() async* {
    yield books;
    yield* _changes.stream.map((_) => books);
  }

  List<Map<String, Object?>> get books => List.unmodifiable(
    ((_data['books'] as List<Object?>?) ?? const <Object?>[])
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
      );
    change(next);
    final temporary = File('${_file.path}.part');
    await temporary.writeAsString(jsonEncode(next), flush: true);
    await temporary.rename(_file.path);
    _data = next;
    _changes.add(null);
  }

  Future<void> close() => _changes.close();
}
