import 'dart:io';

import 'package:workmanager/workmanager.dart';

import '../data/schedule_database.dart';
import '../notifications/notification_service.dart';
import '../widget/next_course_widget_service.dart';
import 'schedule_controller.dart';
import 'star_sync_service.dart';

Future<void> configureStarBackgroundSync(bool enabled) async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  final uniqueName = Platform.isIOS
      ? iosStarSyncIdentifier
      : 'star-background-sync';
  if (!enabled) {
    await Workmanager().cancelByUniqueName(uniqueName);
    return;
  }
  await Workmanager().registerPeriodicTask(
    uniqueName,
    'sync-star-activities',
    frequency: const Duration(minutes: 15),
    initialDelay: const Duration(minutes: 15),
    backoffPolicy: BackoffPolicy.linear,
    backoffPolicyDelay: const Duration(minutes: 5),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    constraints: Constraints(networkType: NetworkType.connected),
  );
}

const iosStarSyncIdentifier = 'icu.tjschedule.refresh.star';

Future<void> syncStarInBackground(
  ScheduleDatabase db,
  NotificationService notifications,
) async {
  if (await db.loadSetting('star_enabled') != 'true') return;
  final service = StarSyncService(db);
  try {
    await service.refresh();
    final saved = await db.loadTermSchedule(currentTermId);
    if (saved == null) return;
    final schedule = ScheduleData(
      term: saved.term,
      courses: saved.courses,
      memos: await db.loadMemos(currentTermId),
      adjustments: await db.loadScheduleAdjustments(),
      cancellations: await db.loadCourseCancellations(),
    );
    try {
      await const NextCourseWidgetService().syncBackground(schedule);
    } catch (_) {}
    try {
      await notifications.initialize();
      await notifications.reschedule(
        schedule: schedule,
        settings: await db.loadNotificationSettings(),
      );
    } catch (_) {}
  } finally {
    service.close();
  }
}
