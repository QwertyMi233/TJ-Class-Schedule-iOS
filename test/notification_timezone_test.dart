import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/notifications/notification_service.dart';
import 'package:timezone/timezone.dart' as tz;

class _Plugin implements FlutterLocalNotificationsPlugin {
  bool initialized = false;
  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async => initialized = true;
  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_timezone');
  for (final entry in {
    'GMT': 0,
    'UTC': 0,
    'Asia/Shanghai': 8,
    'US/Pacific': -7,
  }.entries) {
    test('通知初始化支持系统时区 ${entry.key}，保留实际夏季偏移', () async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => entry.key,
      );
      addTearDown(() {
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
        tz.setLocalLocation(tz.UTC);
      });
      final plugin = _Plugin();
      final service = NotificationService(plugin: plugin);
      addTearDown(service.dispose);
      await service.initialize();
      expect(plugin.initialized, isTrue);
      expect(
        tz.TZDateTime(tz.local, 2026, 7, 1).timeZoneOffset,
        Duration(hours: entry.value),
      );
    });
  }
}
