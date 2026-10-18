import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/features/location/domain.dart';
import 'package:offline_course_schedule/features/location/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory directory;
  late PlaceStore store;
  final now = DateTime(2026, 10, 14);
  Place point(String id, double lat) => Place(
    id: id,
    name: '同名自行车',
    note: id,
    color: 0xff28a86b,
    fix: Fix(lat, 121, 6, now),
    createdAt: now,
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('finder-test-');
    await databaseFactory.setDatabasesPath(directory.path);
    store = await PlaceStore.open();
  });
  tearDown(() async {
    await store.database.close();
    await directory.delete(recursive: true);
  });
  test('同名点独立保存，修改与删除只影响目标 ID', () async {
    final a = point('a', 31), b = point('b', 32);
    await store.insert(a);
    await store.insert(b);
    await store.edit(a.renamed('新的名字', '新的备注'));
    final items = await store.all();
    expect(items, hasLength(2));
    expect(items.singleWhere((p) => p.id == 'a').name, '新的名字');
    expect(items.singleWhere((p) => p.id == 'a').fix.latitude, 31);
    expect(items.singleWhere((p) => p.id == 'b').name, '同名自行车');
    expect(items.singleWhere((p) => p.id == 'b').fix.latitude, 32);
    await store.delete('a');
    expect((await store.all()).single.id, 'b');
  });
  test('关闭并重新打开仍保留坐标备注和时间', () async {
    final a = point('a', 31);
    await store.insert(a);
    await store.database.close();
    store = await PlaceStore.open();
    expect((await store.all()).single.toMap(), a.toMap());
  });
  test('重复 ID 不会覆盖另一定位点', () async {
    await store.insert(point('a', 31));
    await expectLater(
      store.insert(point('a', 32)),
      throwsA(isA<DatabaseException>()),
    );
    expect((await store.all()).single.fix.latitude, 31);
  });
  test('批量生成点 ID 保持独立', () {
    final ids = List.generate(1000, (_) => newId());
    expect(ids.toSet(), hasLength(1000));
  });
  test('方向模式持久保存，快速切换后保留最后选择', () async {
    final controller = DirectionStyleController(store);
    await controller.restore();
    await Future.wait([
      controller.choose(DirectionStyle.highlight),
      controller.choose(DirectionStyle.arrow),
      controller.choose(DirectionStyle.highlight),
    ]);
    controller.dispose();
    await store.database.close();
    store = await PlaceStore.open();
    final restored = DirectionStyleController(store);
    await restored.restore();
    expect(restored.state, DirectionStyle.highlight);
    restored.dispose();
  });
  test('v1 数据库升级保持原定位点并可保存方向模式', () async {
    await store.database.close();
    final path = p.join(directory.path, 'saved_locations.db');
    await databaseFactory.deleteDatabase(path);
    final old = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) => db.execute(
        'CREATE TABLE places (id TEXT PRIMARY KEY, name TEXT NOT NULL, note TEXT NOT NULL, color INTEGER NOT NULL, '
        'lat REAL NOT NULL, lon REAL NOT NULL, accuracy REAL NOT NULL, fixed_at INTEGER NOT NULL, created_at INTEGER NOT NULL)',
      ),
    );
    final saved = point('old-bike', 31);
    await old.insert('places', saved.toMap());
    await old.close();
    store = await PlaceStore.open();
    expect((await store.all()).single.toMap(), saved.toMap());
    await store.setPreference('directionStyle', 'highlight');
    expect(await store.preference('directionStyle'), 'highlight');
  });
}
