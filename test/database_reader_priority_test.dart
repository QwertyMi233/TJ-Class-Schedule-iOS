import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/data/schedule_database.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test('后台持有写事务时新连接仍能打开并读取已保存课表', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tj-reader-priority-',
    );
    final path = '${directory.path}/schedule.db';
    final background = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    await background.replaceTermSchedule(
      Term(
        id: 'current-term',
        name: '本机课表',
        firstWeekMonday: DateTime(2026, 9, 7),
        totalWeeks: 20,
        periodsByWeekday: {},
      ),
      [],
    );
    // 先校验真实 SQLite 模式，避免旧实现阻塞后留下未完成的操作。
    final mode = await background.database.rawQuery('PRAGMA journal_mode');
    try {
      expect(mode.single.values.single, 'wal');
      final locked = Completer<void>();
      final release = Completer<void>();
      final writing = background.database.transaction((txn) async {
        await txn.insert('app_settings', {
          'key': 'background-sync',
          'value': 'busy',
        });
        locked.complete();
        await release.future;
      });
      await locked.future;
      ScheduleDatabase? foreground;
      try {
        foreground = await ScheduleDatabase.open(
          factory: databaseFactoryFfi,
          path: path,
          singleInstance: false,
        ).timeout(const Duration(seconds: 2));
        final schedule = await foreground
            .loadTermSchedule('current-term')
            .timeout(const Duration(seconds: 2));
        expect(schedule!.term.name, '本机课表');
        expect(await foreground.loadSetting('background-sync'), isNull);
      } finally {
        release.complete();
        await writing;
        await foreground?.close();
      }
      expect(await background.loadSetting('background-sync'), 'busy');
    } finally {
      await background.close();
      await directory.delete(recursive: true);
    }
  });
}
