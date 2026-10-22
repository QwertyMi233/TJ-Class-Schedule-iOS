import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/application/task_state.dart';
import 'package:offline_course_schedule/domain/notification_settings.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/domain/task_record.dart';
import 'package:offline_course_schedule/notifications/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const queue = MethodChannel('offline_course_schedule/ios_notifications');
  const notifications = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  final calls = <MethodCall>[];
  final systemCalls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    FlutterLocalNotificationsPlatform.instance =
        IOSFlutterLocalNotificationsPlugin();
    calls.clear();
    systemCalls.clear();
    messenger.setMockMethodCallHandler(queue, (call) async {
      calls.add(call);
      return (call.arguments['requests'] as List).length;
    });
    messenger.setMockMethodCallHandler(notifications, (call) async {
      systemCalls.add(call);
      if (call.method == 'checkPermissions') return {'isEnabled': true};
      return true;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(queue, null);
    messenger.setMockMethodCallHandler(notifications, null);
  });

  test(
    'iOS requests system notification permission without Android alarm calls',
    () async {
      final service = NotificationService();
      await service.requestAndroidPermissions();
      expect(await service.canScheduleExactNotifications(), isTrue);
      expect(systemCalls.map((c) => c.method), [
        'requestPermissions',
        'checkPermissions',
      ]);
      expect(systemCalls.first.arguments['alert'], isTrue);
      await service.dispose();
    },
  );

  test(
    'iOS tasks use shared native queue and clear only their own scope',
    () async {
      final service = NotificationService();
      final now = DateTime(2026, 10, 22, 10);
      final task = TaskRecord(
        id: 'manual:one',
        title: '物理作业',
        course: '物理',
        platform: 'manual',
        source: 'manual',
        accountId: '',
        createdAt: now,
        dueAt: now.add(const Duration(hours: 8)),
      );
      expect(
        await service.rescheduleTasks(
          tasks: [task],
          settings: const TaskReminderSettings(enabled: true, hours: 2),
          now: now,
        ),
        1,
      );
      final request =
          (calls.single.arguments['requests'] as List).single as Map;
      expect(
        request['timeMillis'],
        now.add(const Duration(hours: 6)).millisecondsSinceEpoch,
      );
      expect(request['payload'], 'task:manual:one');
      expect(calls.single.arguments['scope'], 'tasks');
      await service.rescheduleTasks(
        tasks: [task],
        settings: const TaskReminderSettings(enabled: false),
        now: now,
      );
      expect(calls.last.arguments['scope'], 'tasks');
      expect(calls.last.arguments['requests'], isEmpty);
      expect(systemCalls, isEmpty);
      await service.dispose();
    },
  );

  test(
    'iOS course reminders retain timestamps and silent lock screen notice',
    () async {
      final service = NotificationService();
      final now = DateTime(2026, 10, 19, 6);
      final term = Term(
        id: currentTermId,
        name: '秋季',
        firstWeekMonday: DateTime(2026, 10, 19),
        totalWeeks: 1,
        periodsByWeekday: {
          1: [
            const LessonPeriod(number: 1, startMinutes: 480, endMinutes: 530),
          ],
        },
      );
      final course = Course(
        id: 'math',
        name: '高等数学',
        teacher: '张老师',
        colorValue: 0xff000000,
        sessions: [
          CourseSession(
            id: 's',
            weekday: 1,
            startPeriod: 1,
            endPeriod: 1,
            weekRule: WeekRule(startWeek: 1, endWeek: 1, type: WeekType.every),
            location: 'A101',
          ),
        ],
      );
      await service.reschedule(
        schedule: ScheduleData(term: term, courses: [course]),
        settings: const NotificationSettings(
          enabled: true,
          showNextCourseOnLockScreen: true,
        ),
        now: now,
      );
      expect(calls.single.arguments['scope'], 'courses');
      final requests = calls.single.arguments['requests'] as List;
      expect(requests.length, 2);
      expect(
        requests.every((dynamic r) => r['payload'] == '2026-10-19'),
        isTrue,
      );
      expect(requests.any((dynamic r) => r['sound'] == false), isTrue);
      await service.reschedule(
        schedule: const ScheduleData(),
        settings: const NotificationSettings(enabled: false),
      );
      expect(calls.last.arguments['scope'], 'courses');
      expect(calls.last.arguments['requests'], isEmpty);
      await service.dispose();
    },
  );
}
