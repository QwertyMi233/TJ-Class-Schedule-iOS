import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/application/startup_date.dart';
import 'package:offline_course_schedule/data/schedule_backup_codec.dart';
import 'package:offline_course_schedule/data/schedule_database.dart';
import 'package:offline_course_schedule/domain/notification_settings.dart';
import 'package:offline_course_schedule/domain/schedule_engine.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/notifications/reminder_planner.dart';
import 'package:offline_course_schedule/widget/next_course_widget_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  final date = DateTime(2026, 10, 19);
  final term = Term(
    id: 'term',
    name: '测试',
    firstWeekMonday: date,
    totalWeeks: 2,
    periodsByWeekday: {
      1: const [LessonPeriod(number: 1, startMinutes: 480, endMinutes: 525)],
    },
  );
  Memo point({int start = 840}) => Memo(
    id: 'point',
    title: '领取材料',
    colorValue: 1,
    date: date,
    startMinutes: start,
  );

  test('一次性允许仅开始时刻，日期与开始仍必填且边界有效', () {
    expect(point().endMinutes, isNull);
    expect(point(start: 1439).startMinutes, 1439);
    for (final value in [-1, 1440]) {
      expect(() => point(start: value), throwsArgumentError);
    }
    expect(
      () => Memo(
        id: 'bad',
        title: '缺少开始',
        colorValue: 1,
        date: date,
        endMinutes: 900,
      ),
      throwsArgumentError,
    );
  });
  test('引擎只产生一个时刻，不虚构持续时间或结束时刻', () {
    final entry = ScheduleEngine(
      term: term,
      courses: const [],
      memos: [point()],
    ).getEntriesForDate(date).single;
    expect(entry.startTime, DateTime(2026, 10, 19, 14));
    expect(entry.endTime, entry.startTime);
    expect(entry.hasEndTime, false);
  });
  test('无结束时刻在数据库写入、重读和备份恢复后仍保持为空', () async {
    final db = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(db.close);
    await db.replaceTermSchedule(term, const []);
    await db.replaceTermMemos(term.id, [point()]);
    final saved = await db.loadMemos(term.id);
    expect(saved.single.endMinutes, isNull);
    const codec = ScheduleBackupCodec();
    final recovered = codec.decode(
      codec.encode(
        ScheduleBackup(
          term: term,
          courses: const [],
          memos: saved,
          adjustments: const [],
          cancellations: const [],
          settings: const NotificationSettings(),
        ),
      ),
    );
    expect(recovered.memos.single.endMinutes, isNull);
    expect(recovered.memos.single.startMinutes, 840);
  });
  test('仅开始时刻的备忘录正常提醒并出现在下一项小组件', () {
    final plans = const ReminderPlanner().createPlans(
      now: DateTime(2026, 10, 19, 12),
      term: term,
      courses: const [],
      memos: [point()],
      settings: const NotificationSettings(memoAdvanceMinutes: 10),
    );
    expect(plans.single.scheduledAt, DateTime(2026, 10, 19, 13, 50));
    final items = const NextCourseWidgetService().buildItems(
      ScheduleData(term: term, courses: const [], memos: [point()]),
      DateTime(2026, 10, 19, 12),
    );
    expect(items.single['time'], '14:00');
    expect(items.single['isMemo'], true);
  });
  test('启动时早先开始的长事件未结束，不能因后一个短事件结束而跳到明天', () {
    final memos = [
      Memo(
        id: 'long',
        title: '长事件',
        colorValue: 1,
        date: date,
        startMinutes: 540,
        endMinutes: 1080,
      ),
      Memo(
        id: 'short',
        title: '短事件',
        colorValue: 1,
        date: date,
        startMinutes: 600,
        endMinutes: 660,
      ),
    ];
    final engine = ScheduleEngine(term: term, courses: const [], memos: memos);
    expect(startupSelectedDate(engine, DateTime(2026, 10, 19, 12)), isNull);
    expect(
      startupSelectedDate(engine, DateTime(2026, 10, 19, 18)),
      DateTime(2026, 10, 20),
    );
  });
}
