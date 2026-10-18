import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/application/task_state.dart';
import 'package:offline_course_schedule/data/schedule_database.dart';
import 'package:offline_course_schedule/data/task_repository.dart';
import 'package:offline_course_schedule/domain/notification_settings.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/domain/task_record.dart';
import 'package:offline_course_schedule/main.dart';
import 'package:offline_course_schedule/notifications/notification_service.dart';
import 'package:offline_course_schedule/presentation/home_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  for (final failure in [
    '通知初始化挂起',
    '通知初始化失败',
    '通知调度失败',
    '作业读取挂起',
    '小组件设置读取挂起',
  ]) {
    testWidgets('$failure 时已保存课表及课表小组件仍可用', (tester) async {
      final now = DateTime.now();
      final db = (await tester.runAsync(
        () => ScheduleDatabase.open(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        ),
      ))!;
      await tester.runAsync(() async {
        await db.replaceTermSchedule(
          Term(
            id: currentTermId,
            name: '本机已保存学期',
            firstWeekMonday: DateTime(
              now.year,
              now.month,
              now.day,
            ).subtract(Duration(days: now.weekday - 1)),
            totalWeeks: 20,
            periodsByWeekday: {
              for (var weekday = 1; weekday <= 7; weekday++)
                weekday: const [
                  LessonPeriod(number: 1, startMinutes: 1380, endMinutes: 1430),
                ],
            },
          ),
          [
            Course(
              id: 'course',
              name: '本机高等数学',
              teacher: '老师',
              colorValue: 0xFF7D9DCE,
              sessions: [
                for (var weekday = 1; weekday <= 7; weekday++)
                  CourseSession(
                    id: 'session-$weekday',
                    weekday: weekday,
                    startPeriod: 1,
                    endPeriod: 1,
                    weekRule: WeekRule(
                      startWeek: 1,
                      endWeek: 20,
                      type: WeekType.every,
                    ),
                    location: 'A101',
                  ),
              ],
            ),
          ],
        );
        await db.saveNotificationSettings(
          const NotificationSettings(
            tutorialPromptCompleted: true,
            magicOsGuideCompleted: true,
          ),
        );
      });
      final updates = <Map<Object?, Object?>>[];
      var taskUpdates = 0;
      const channel = MethodChannel('offline_course_schedule/widget');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'update') {
          updates.add(call.arguments as Map<Object?, Object?>);
        }
        if (call.method == 'updateTasks') taskUpdates++;
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final notifications = _Notifications(failure);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWith((ref) async => db),
            if (failure == '小组件设置读取挂起') ...[
              widgetColorProvider.overrideWith(_PendingColor.new),
              widgetRefreshModeProvider.overrideWith(_PendingRefresh.new),
            ],
            if (failure == '作业读取挂起')
              taskRepositoryProvider.overrideWith(
                (ref) => Completer<TaskRepository>().future,
              ),
          ],
          child: CourseScheduleApp(
            initialDate: now,
            notificationService: notifications,
          ),
        ),
      );
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomePage)),
      );
      var loaded = false;
      Future.wait([
        container.read(scheduleControllerProvider.future),
        if (failure != '小组件设置读取挂起') container.read(widgetColorProvider.future),
        if (failure != '小组件设置读取挂起')
          container.read(widgetRefreshModeProvider.future),
        container.read(themeSeedColorProvider.future),
        container.read(swipeAdvancesWeekProvider.future),
        container.read(backgroundImagePathProvider.future),
        container.read(backgroundOverlayOpacityProvider.future),
        container.read(cardOpacityProvider.future),
        container.read(notificationSettingsProvider.future),
        container.read(taskReminderSettingsProvider.future),
      ]).then((_) => loaded = true);
      for (var i = 0; i < 100 && !loaded; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(loaded, isTrue);
      await tester.pumpAndSettle();
      expect(find.text('本机高等数学'), findsWidgets);
      expect(updates, isNotEmpty, reason: '小组件不能依赖通知或作业初始化');
      expect((updates.last['courses'] as List).first['name'], '本机高等数学');
      if (failure == '小组件设置读取挂起') {
        expect(updates.last.containsKey('color'), isFalse);
        expect(updates.last.containsKey('refreshMode'), isFalse);
      }
      if (failure != '作业读取挂起') {
        for (var i = 0; i < 100 && taskUpdates == 0; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(taskUpdates, greaterThan(0), reason: '作业小组件也不能依赖通知');
      }
      final count = updates.length;
      final taskCount = taskUpdates;
      final notificationCount = notifications.taskReschedules;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(updates.length, greaterThan(count));
      if (failure != '作业读取挂起') {
        for (var i = 0; i < 100; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
          if (taskUpdates > taskCount &&
              (failure != '小组件设置读取挂起' ||
                  notifications.taskReschedules > notificationCount)) {
            break;
          }
        }
        expect(taskUpdates, greaterThan(taskCount));
      }
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      // dispose 后等待已开始的 SQLite 查询结束，再关闭测试连接。
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.runAsync(db.close);
    });
  }
}

class _Notifications extends NotificationService {
  _Notifications(this.failure);
  final String failure;
  int taskReschedules = 0;

  @override
  Future<DateTime?> initialize() {
    if (failure == '通知初始化挂起') return Completer<DateTime?>().future;
    if (failure == '通知初始化失败') throw StateError('通知初始化失败');
    return Future.value(null);
  }

  @override
  Future<void> requestAndroidPermissions() async {}

  @override
  Future<int> reschedule({
    required ScheduleData schedule,
    required NotificationSettings settings,
    DateTime? now,
  }) async {
    if (failure == '通知调度失败') {
      throw PlatformException(code: 'notification-error');
    }
    return 0;
  }

  @override
  Future<int> rescheduleTasks({
    required List<TaskRecord> tasks,
    required TaskReminderSettings settings,
    DateTime? now,
  }) async {
    taskReschedules++;
    return 0;
  }
}

class _PendingColor extends WidgetColorController {
  @override
  Future<int?> build() => Completer<int?>().future;
}

class _PendingRefresh extends WidgetRefreshModeController {
  @override
  Future<WidgetRefreshMode> build() => Completer<WidgetRefreshMode>().future;
}
