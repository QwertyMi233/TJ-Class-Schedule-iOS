import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'domain.dart';

class PlaceStore {
  final Database database;
  PlaceStore(this.database);
  static Future<PlaceStore> open() async => PlaceStore(
    await openDatabase(
      p.join(await getDatabasesPath(), 'saved_locations.db'),
      version: 2,
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) await createPreferences(db);
      },
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE places ('
          'id TEXT PRIMARY KEY, name TEXT NOT NULL, note TEXT NOT NULL, color INTEGER NOT NULL, '
          'lat REAL NOT NULL, lon REAL NOT NULL, accuracy REAL NOT NULL, '
          'fixed_at INTEGER NOT NULL, created_at INTEGER NOT NULL)',
        );
        await createPreferences(db);
      },
    ),
  );
  static Future<void> createPreferences(Database db) => db.execute(
    'CREATE TABLE preferences (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
  );
  Future<List<Place>> all() async => (await database.query(
    'places',
    orderBy: 'created_at DESC, id ASC',
  )).map(Place.fromMap).toList();
  Future<void> insert(Place place) =>
      database.insert('places', place.toMap()).then((_) {});
  Future<void> edit(Place place) => database
      .update(
        'places',
        {'name': place.name, 'note': place.note},
        where: 'id = ?',
        whereArgs: [place.id],
      )
      .then((_) {});
  Future<void> delete(String id) =>
      database.delete('places', where: 'id = ?', whereArgs: [id]).then((_) {});
  Future<String?> preference(String key) async {
    final rows = await database.query(
      'preferences',
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setPreference(String key, String value) => database
      .insert('preferences', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace)
      .then((_) {});
}

enum DirectionStyle { arrow, highlight }

final directionStyleProvider =
    StateNotifierProvider<DirectionStyleController, DirectionStyle>(
      (ref) => DirectionStyleController(ref.watch(storeProvider)),
    );

class DirectionStyleController extends StateNotifier<DirectionStyle> {
  final PlaceStore store;
  int revision = 0;
  Future<void> writes = Future.value();
  DirectionStyleController(this.store) : super(DirectionStyle.arrow) {
    restore();
  }
  Future<void> restore() async {
    final token = revision;
    try {
      final value = await store.preference('directionStyle');
      if (mounted && token == revision) {
        state = value == 'highlight'
            ? DirectionStyle.highlight
            : DirectionStyle.arrow;
      }
    } catch (_) {
      /* 偏好读取失败不影响寻找。 */
    }
  }

  Future<void> choose(DirectionStyle value) async {
    revision++;
    state = value;
    final next = writes.then(
      (_) => store.setPreference('directionStyle', value.name),
    );
    writes = next.catchError((_) {});
    await next;
  }
}

// 按需打开独立数据库，不参与课表的启动、导入、清空或备份流程。
final placeStoreProvider = FutureProvider<PlaceStore>((ref) async {
  PlaceStore? store;
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    final opened = store;
    if (opened != null) unawaited(opened.database.close());
  });
  store = await PlaceStore.open();
  if (disposed) await store.database.close();
  return store;
});
final storeProvider = Provider<PlaceStore>(
  (ref) => ref.watch(placeStoreProvider).requireValue,
);
final placesProvider = FutureProvider<List<Place>>(
  (ref) => ref.watch(storeProvider).all(),
);

String newId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
