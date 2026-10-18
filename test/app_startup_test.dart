import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/data/schedule_database.dart';
import 'package:offline_course_schedule/application/task_state.dart';
import 'package:offline_course_schedule/data/task_repository.dart';
import 'package:offline_course_schedule/domain/notification_settings.dart';
import 'package:offline_course_schedule/notifications/notification_lifecycle.dart';
import 'package:offline_course_schedule/notifications/notification_service.dart';
import 'package:offline_course_schedule/widget/task_widget_service.dart';
import 'package:offline_course_schedule/main.dart' as app;
import 'package:offline_course_schedule/presentation/home_page.dart';

void main() {
  testWidgets('课表读取完成前不启动通知、后台调度和作业小组件读取', (tester) async {
    final schedule = Completer<ScheduleData>();
    var backgroundCalls = 0;
    var taskCalls = 0;
    final notifications = _Notifications(() => Completer<DateTime?>().future);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleControllerProvider.overrideWith(
            () => _PendingSchedule(schedule.future),
          ),
          databaseProvider.overrideWith((ref) async => _StartupDatabase()),
          taskRepositoryProvider.overrideWith((ref) async {
            taskCalls++;
            return Completer<TaskRepository>().future;
          }),
        ],
        child: app.CourseScheduleApp(
          notificationService: notifications,
          initializeBackgroundSync: (_) async {
            backgroundCalls++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(notifications.calls, 0);
    expect(backgroundCalls, 0);
    expect(taskCalls, 0);
    schedule.complete(const ScheduleData());
    await tester.pumpAndSettle();
    expect(notifications.calls, 1);
    expect(backgroundCalls, 1);
    expect(taskCalls, 1);
    expect(find.text('开始设置'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('通知时区初始化不返回时入口仍渲染首屏', (tester) async {
    final pending = Completer<Object?>();
    const channel = MethodChannel('flutter_timezone');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) => pending.future,
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });

    app.main();
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(HomePage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('后台初始化挂起时首屏可操作且通知初始化独立进行', (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    final notifications = _Notifications(() => Completer<DateTime?>().future);
    await tester.pumpWidget(
      _app(
        notifications: notifications,
        background: () {
          expect(find.byType(HomePage), findsOneWidget);
          calls++;
          return pending.future;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(notifications.calls, 1);
    await tester.tap(find.text('开始设置'));
    await tester.pumpAndSettle();
    expect(find.text('设置学期'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(calls, 1);
  });

  testWidgets('后台和通知初始化失败不影响首屏操作', (tester) async {
    final notifications = _Notifications(() async => throw StateError('通知失败'));
    await tester.pumpWidget(
      _app(
        notifications: notifications,
        background: () async => throw StateError('后台失败'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('开始设置'), findsOneWidget);
    await tester.tap(find.text('开始设置'));
    await tester.pumpAndSettle();
    expect(find.text('设置学期'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('后台初始化挂起仍能处理通知冷启动日期', (tester) async {
    final date = DateTime(2026, 10, 8);
    final notifications = _Notifications(() async => date);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      TaskWidgetService.channel,
      (_) async => null,
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        TaskWidgetService.channel,
        null,
      );
    });
    await tester.pumpWidget(
      _app(
        notifications: notifications,
        background: () => Completer<void>().future,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NotificationLifecycle), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );
    expect(container.read(selectedDateProvider), date);
    expect(notifications.calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('页面已销毁后通知初始化完成不触发界面更新', (tester) async {
    final pending = Completer<DateTime?>();
    await tester.pumpWidget(
      _app(notifications: _Notifications(() => pending.future)),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(null);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

Widget _app({
  required _Notifications notifications,
  Future<void> Function()? background,
}) => ProviderScope(
  overrides: [
    scheduleControllerProvider.overrideWith(_Schedule.new),
    databaseProvider.overrideWith((ref) async => _StartupDatabase()),
    notificationServiceProvider.overrideWithValue(notifications),
  ],
  child: app.CourseScheduleApp(
    notificationService: notifications,
    initializeBackgroundSync: background == null ? null : (_) => background(),
  ),
);

// 这些测试只隔离系统插件初始化；真实 SQLite 启动另有集成回归覆盖。
class _StartupDatabase implements ScheduleDatabase {
  @override
  Future<String?> loadSetting(String key) async => null;

  @override
  Future<NotificationSettings> loadNotificationSettings() =>
      Completer<NotificationSettings>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Schedule extends ScheduleController {
  @override
  Future<ScheduleData> build() async => const ScheduleData();
}

class _Notifications extends NotificationService {
  _Notifications(this.start);
  final Future<DateTime?> Function() start;
  int calls = 0;

  @override
  Future<DateTime?> initialize() {
    calls++;
    return start();
  }

  @override
  Future<void> requestAndroidPermissions() async {}
}

class _PendingSchedule extends ScheduleController {
  _PendingSchedule(this.pending);
  final Future<ScheduleData> pending;
  @override
  Future<ScheduleData> build() => pending;
}
