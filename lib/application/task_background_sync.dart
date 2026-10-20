import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';
import '../data/schedule_database.dart';
import '../data/task_repository.dart';
import '../notifications/notification_service.dart';
import '../notifications/task_sync_notifications.dart';
import 'task_state.dart';
import '../widget/task_widget_service.dart';
import 'task_sync_controller.dart';
import 'star_background_sync.dart';
import '../data/star_activity_client.dart';

@pragma('vm:entry-point')
void taskSyncDispatcher() {
  Workmanager().executeTask((task, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    final db = await ScheduleDatabase.open(singleInstance: false);
    final notifications = NotificationService();
    try {
      if (task == 'sync-star-activities') {
        try {
          await syncStarInBackground(db, notifications);
          return true;
        } on StarRequestException catch (error) {
          return error.needsAuth;
        }
      }
      return await syncTasksInBackground(db, notifications);
    } catch (_) {
      return false;
    } finally {
      await notifications.dispose();
      await db.close();
    }
  });
}

Future<bool> syncTasksInBackground(
  ScheduleDatabase db,
  NotificationService notifications, {
  TaskSyncService? syncService,
  TaskWidgetService widgets = const TaskWidgetService(),
}) async {
  if (await db.loadSetting('task_auto_sync') != 'true') return true;
  var notificationsReady = false;
  try {
    await notifications.initialize();
    notificationsReady = true;
  } catch (_) {
    // 通知不可用时仍要同步作业。
  }
  final notifier = TaskSyncNotifications(db, notifications);
  final service =
      syncService ??
      TaskSyncService(
        db,
        backgroundTick: true,
        onAutomaticUpdate: notificationsReady ? notifier.updated : null,
        onAuthRequired: notificationsReady ? notifier.authRequired : null,
      );
  try {
    await service.refresh();
    final retry =
        service.deferredByAnotherSync || await service.hasPendingHaokeRetry();
    final tasks = await TaskRepository(db.database).loadVisible();
    try {
      await widgets.syncBackground(tasks);
    } catch (_) {}
    if (notificationsReady) {
      try {
        await notifications.rescheduleTasks(
          tasks: tasks,
          settings: taskReminderSettingsFromJson(
            await db.loadSetting('task_reminders'),
          ),
        );
      } catch (_) {}
    }
    return !retry;
  } finally {
    if (syncService == null) service.close();
  }
}

Future<void> configureTaskBackgroundSync(bool enabled) async {
  if (!Platform.isAndroid) return;
  if (!enabled) {
    await Workmanager().cancelByUniqueName('task-background-sync');
    return;
  }
  await Workmanager().registerPeriodicTask(
    'task-background-sync',
    'sync-tasks',
    frequency: const Duration(minutes: 15),
    backoffPolicy: BackoffPolicy.linear,
    backoffPolicyDelay: TaskSyncService.haokeRetryDelay,
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    constraints: Constraints(networkType: NetworkType.connected),
  );
}

Future<void> initializeTaskBackgroundSync(ScheduleDatabase db) async {
  if (!Platform.isAndroid) return;
  await Workmanager().initialize(taskSyncDispatcher);
  await configureTaskBackgroundSync(
    await db.loadSetting('task_auto_sync') == 'true',
  );
  await configureStarBackgroundSync(
    await db.loadSetting('star_enabled') == 'true',
  );
}
