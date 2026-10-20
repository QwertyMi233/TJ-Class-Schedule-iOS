import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/task_background_sync.dart';
import 'package:offline_course_schedule/application/task_state.dart';
import 'package:offline_course_schedule/application/task_sync_controller.dart';
import 'package:offline_course_schedule/data/schedule_database.dart';
import 'package:offline_course_schedule/domain/task_record.dart';
import 'package:offline_course_schedule/notifications/notification_service.dart';
import 'package:offline_course_schedule/widget/task_widget_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class BackgroundSync extends TaskSyncService {
  BackgroundSync(super.database);
  int calls = 0;
  bool retry = false;
  @override
  Future<Map<String, String>> refresh({bool manual = false}) async {
    expect(manual, false);
    calls++;
    await database.saveSetting('background_synced', 'true');
    return {};
  }

  @override
  Future<bool> hasPendingHaokeRetry() async => retry;
}

class BackgroundNotifications extends NotificationService {
  int starts = 0, reschedules = 0;
  bool fail = false;
  @override
  Future<DateTime?> initialize() async {
    starts++;
    if (fail) throw StateError('notification unavailable');
    return null;
  }

  @override
  Future<int> rescheduleTasks({
    required List<TaskRecord> tasks,
    required TaskReminderSettings settings,
    DateTime? now,
  }) async {
    reschedules++;
    return 0;
  }
}

class BackgroundWidgets extends TaskWidgetService {
  bool fail = false;
  @override
  Future<void> syncBackground(List<TaskRecord> tasks) async {
    if (fail) throw StateError('widget unavailable');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late ScheduleDatabase db;
  late BackgroundSync sync;
  late BackgroundNotifications notifications;
  late BackgroundWidgets widgets;
  setUp(() async {
    db = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    await db.saveSetting('task_auto_sync', 'true');
    sync = BackgroundSync(db);
    notifications = BackgroundNotifications();
    widgets = BackgroundWidgets();
  });
  tearDown(() async {
    sync.close();
    await notifications.dispose();
    await db.close();
  });

  test('通知初始化失败不会阻止后台登录与作业同步', () async {
    notifications.fail = true;
    expect(
      await syncTasksInBackground(
        db,
        notifications,
        syncService: sync,
        widgets: widgets,
      ),
      true,
    );
    expect(sync.calls, 1);
    expect(await db.loadSetting('background_synced'), 'true');
    expect(notifications.reschedules, 0);
  });
  test('小组件失败不丢补试，也不阻止安排截止提醒', () async {
    sync.retry = true;
    widgets.fail = true;
    expect(
      await syncTasksInBackground(
        db,
        notifications,
        syncService: sync,
        widgets: widgets,
      ),
      false,
    );
    expect(notifications.reschedules, 1);
  });
  test('被前台任务占用时后台交还调度器重试', () async {
    sync.deferredByAnotherSync = true;
    expect(
      await syncTasksInBackground(
        db,
        notifications,
        syncService: sync,
        widgets: widgets,
      ),
      false,
    );
  });
  test('关闭自动同步后不初始化通知或调用同步', () async {
    await db.saveSetting('task_auto_sync', 'false');
    expect(
      await syncTasksInBackground(
        db,
        notifications,
        syncService: sync,
        widgets: widgets,
      ),
      true,
    );
    expect(sync.calls, 0);
    expect(notifications.starts, 0);
  });
}
