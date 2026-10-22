import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/domain/notification_settings.dart';
import 'package:offline_course_schedule/presentation/magic_os_guide_page.dart';
import 'package:offline_course_schedule/presentation/notification_settings_page.dart';

class _Settings extends NotificationSettingsController {
  @override
  Future<NotificationSettings> build() async => const NotificationSettings();
}

void main() {
  for (final size in const [
    Size(320, 568),
    Size(375, 667),
    Size(430, 932),
    Size(852, 393),
    Size(744, 1133),
    Size(1024, 768),
  ]) {
    testWidgets('iOS guidance and settings fit ${size.width}×${size.height}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Widget app(Widget page) => ProviderScope(
        overrides: [notificationSettingsProvider.overrideWith(_Settings.new)],
        child: MaterialApp(home: page),
      );
      await tester.pumpWidget(
        app(const MagicOsGuidePage(showBackButton: true)),
      );
      await tester.pumpAndSettle();
      expect(find.text('iOS 提醒与后台设置'), findsOneWidget);
      expect(find.text('允许应用自动启动'), findsNothing);
      await tester.scrollUntilVisible(find.text('我已了解'), 180);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(app(const NotificationSettingsPage()));
      await tester.pumpAndSettle();
      expect(find.text('通知 + 声音（震动跟随系统）'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('申请通知权限'), 180);
      expect(find.text('精确闹钟权限'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  }
}
