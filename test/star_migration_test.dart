import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/data/schedule_backup_codec.dart';
import 'package:offline_course_schedule/data/schedule_database.dart';
import 'package:offline_course_schedule/domain/notification_settings.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  final term = Term(
    id: 'current-term',
    name: '原学期',
    firstWeekMonday: DateTime(2026, 10, 19),
    totalWeeks: 20,
    periodsByWeekday: {},
  );
  test('10 升到 11 保留手工备忘录的可空结束时间与原设置', () async {
    final directory = Directory.systemTemp.createTempSync('star-migration-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/schedule.db';
    var db = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    await db.replaceTermSchedule(term, []);
    await db.replaceTermMemos(term.id, [
      Memo(
        id: 'manual',
        title: '原备忘录',
        colorValue: 1,
        date: DateTime(2026, 10, 21),
        startMinutes: 60,
      ),
    ]);
    await db.saveSetting('unchanged', 'saved');
    await db.database.execute('ALTER TABLE memos DROP COLUMN source');
    await db.database.setVersion(10);
    await db.close();
    db = await ScheduleDatabase.open(factory: databaseFactoryFfi, path: path);
    addTearDown(db.close);
    expect(await db.database.getVersion(), 11);
    final memo = (await db.loadMemos(term.id)).single;
    expect(memo.title, '原备忘录');
    expect(memo.endMinutes, isNull);
    expect(memo.source, isNull);
    expect(await db.loadSetting('unchanged'), 'saved');
  });
  test('卓越星来源经过备份与恢复仍保留，旧手工备忘录格式继续兼容', () {
    final star = Memo(
      id: 'star-a',
      title: '活动',
      source: 'star',
      colorValue: 1,
      date: DateTime(2026, 10, 21),
      startMinutes: 60,
      endMinutes: 120,
    );
    const codec = ScheduleBackupCodec();
    final restored = codec.decode(
      codec.encode(
        ScheduleBackup(
          term: term,
          courses: [],
          memos: [star],
          adjustments: [],
          cancellations: [],
          settings: const NotificationSettings(),
        ),
      ),
    );
    expect(restored.memos.single.source, 'star');
    expect(restored.memos.single.endMinutes, 120);
  });
}
