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
  Future<void> _transactionTail = Future<void>.value();

  static Future<AppDatabase> defaults() async {
    final directory = await getApplicationDocumentsDirectory();
    final database = AppDatabase._(
      File('${directory.path}${Platform.pathSeparator}paper_ages_state.json'),
    );
    await database._open();
    return database;
  }

  /// Opens an explicit state file. Production uses [defaults]; this entry
  /// point also lets migration/recovery checks exercise the exact file format
  /// without substituting an in-memory fake.
  static Future<AppDatabase> openFile(File file) async {
    final database = AppDatabase._(file);
    await database._open();
    return database;
  }

  static Map<String, Object?> _empty() => {
    'schemaVersion': 4,
    'books': <Object?>[],
    'positions': <String, Object?>{},
    'preferences': <String, Object?>{},
    'sources': <Object?>[],
    'networkBooks': <Object?>[],
    'sourceBindings': <String, Object?>{},
    'downloadTasks': <Object?>[],
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
      _data['schemaVersion'] = 4;
      _data['sources'] = <Object?>[];
      _data['networkBooks'] = <Object?>[];
      _data['sourceBindings'] = <String, Object?>{};
      _data['downloadTasks'] = <Object?>[];
      await _write(_data);
    } else if (version == 2) {
      _data['schemaVersion'] = 4;
      _data['networkBooks'] = <Object?>[];
      _data['sourceBindings'] = <String, Object?>{};
      _data['downloadTasks'] = <Object?>[];
      await _write(_data);
    } else if (version == 3) {
      _data['schemaVersion'] = 4;
      _data['sourceBindings'] = <String, Object?>{};
      _data['downloadTasks'] = <Object?>[];
      await _write(_data);
    } else if (version != 4) {
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

  Stream<List<Map<String, Object?>>> watchDownloadTasks() async* {
    yield downloadTasks;
    yield* _changes.stream.map((_) => downloadTasks);
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

  List<Map<String, Object?>> get downloadTasks => List.unmodifiable(
    ((_data['downloadTasks'] as List<Object?>?) ?? const <Object?>[])
        .whereType<Map>()
        .map((row) => Map<String, Object?>.from(row)),
  );

  Map<String, Object?>? sourceBinding(String bookId) {
    final raw = Map<String, Object?>.from(
      (_data['sourceBindings'] as Map?) ?? const <String, Object?>{},
    )[bookId];
    return raw is Map ? Map<String, Object?>.from(raw) : null;
  }

  Map<String, Object?>? position(String bookId) {
    final raw = Map<String, Object?>.from(_data['positions']! as Map)[bookId];
    return raw is Map ? Map<String, Object?>.from(raw) : null;
  }

  String? preference(String key) =>
      Map<String, Object?>.from(_data['preferences']! as Map)[key] as String?;

  Future<void> transaction(void Function(Map<String, Object?> next) change) {
    final result = _transactionTail.then((_) => _applyTransaction(change));
    // A failed write must not permanently block a later recovery operation.
    _transactionTail = result.catchError((_) {});
    return result;
  }

  Future<void> _applyTransaction(
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
    next['sourceBindings'] = Map<String, Object?>.from(
      (_data['sourceBindings'] as Map?) ?? const <String, Object?>{},
    );
    next['downloadTasks'] = List<Object?>.from(
      (_data['downloadTasks'] as List?) ?? const <Object?>[],
    );
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
