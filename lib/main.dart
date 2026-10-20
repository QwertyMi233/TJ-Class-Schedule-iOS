import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/schedule_controller.dart';
import 'application/startup_date.dart';
import 'application/task_background_sync.dart';
import 'application/star_sync_lifecycle.dart';
import 'data/schedule_database.dart';
import 'domain/schedule_engine.dart';
import 'notifications/notification_lifecycle.dart';
import 'notifications/notification_service.dart';
import 'presentation/app_theme.dart';
import 'presentation/home_page.dart';
import 'widget/widget_lifecycle.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final notificationService = NotificationService();
  runApp(
    ProviderScope(
      overrides: [
        notificationServiceProvider.overrideWithValue(notificationService),
      ],
      child: CourseScheduleApp(
        notificationService: notificationService,
        initializeBackgroundSync: initializeTaskBackgroundSync,
      ),
    ),
  );
}

class CourseScheduleApp extends ConsumerStatefulWidget {
  const CourseScheduleApp({
    super.key,
    this.notificationService,
    this.initialDate,
    this.initializeBackgroundSync,
  });

  final NotificationService? notificationService;
  final DateTime? initialDate;
  final Future<void> Function(ScheduleDatabase)? initializeBackgroundSync;

  @override
  ConsumerState<CourseScheduleApp> createState() => _CourseScheduleAppState();
}

class _CourseScheduleAppState extends ConsumerState<CourseScheduleApp> {
  bool _notificationsReady = false;
  bool _optionalServicesStarted = false;
  DateTime? _initialDate;

  @override
  void initState() {
    super.initState();
    _initialDate = widget.initialDate;
    if (widget.notificationService == null) unawaited(_applyStartupDate());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startOptionalServices();
    });
  }

  void _startOptionalServices() {
    if (!mounted ||
        _optionalServicesStarted ||
        !ref.read(scheduleControllerProvider).hasValue) {
      return;
    }
    _optionalServicesStarted = true;
    // 本机课表先读完，再独立启动附加服务。
    unawaited(_initializeBackgroundSync());
    unawaited(_initializeNotifications());
  }

  Future<void> _initializeBackgroundSync() async {
    final initialize = widget.initializeBackgroundSync;
    if (initialize == null) return;
    try {
      final database = await ref.read(databaseProvider.future);
      if (!mounted) return;
      await initialize(database);
    } catch (error) {
      if (kDebugMode) debugPrint('后台同步初始化失败：$error');
    }
  }

  Future<void> _initializeNotifications() async {
    final service = widget.notificationService;
    if (service == null) return;
    try {
      final initialDate = await service.initialize();
      if (!mounted) return;
      setState(() {
        _initialDate ??= initialDate;
        _notificationsReady = true;
      });
    } catch (error) {
      if (kDebugMode) debugPrint('通知初始化失败：$error');
    }
    if (mounted) await _applyStartupDate();
  }

  /// 仅启动时选取日期，避免重建或回到前台时覆盖用户手动选择的日期。
  Future<void> _applyStartupDate() async {
    // 用户点通知冷启动时带着明确的日期意图，此时不要覆盖成「第二天」。
    if (_initialDate != null) return;
    try {
      final data = await ref.read(scheduleControllerProvider.future);
      final term = data.term;
      if (term == null || !mounted) return;
      final now = await ref.read(clockProvider.future);
      final next = startupSelectedDate(
        ScheduleEngine(
          term: term,
          courses: data.courses,
          memos: data.memos,
          adjustments: data.adjustments,
          cancellations: data.cancellations,
        ),
        now,
      );
      if (next == null || !mounted) return;
      ref.read(selectedDateProvider.notifier).state = next;
    } catch (_) {
      // 课表还没加载好或读取失败时保持原有行为，不打扰用户。
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(scheduleControllerProvider, (_, __) => _startOptionalServices());
    final scheduleReady = ref.watch(scheduleControllerProvider).hasValue;
    // 设置尚未加载完成时先用缺省种子色，避免启动瞬间闪一下主题。
    final seedColor = Color(
      (scheduleReady ? ref.watch(themeSeedColorProvider).valueOrNull : null) ??
          ThemeSeedColorController.defaultColorValue,
    );
    return MaterialApp(
      title: 'TJ Class Schedule',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(seedColor: seedColor),
      darkTheme: AppTheme.dark(seedColor: seedColor),
      themeMode: ThemeMode.system,
      home: StarSyncLifecycle(
        child: WidgetLifecycle(
          child: !_notificationsReady
              ? const HomePage()
              : NotificationLifecycle(
                  service: widget.notificationService!,
                  initialDate: _initialDate,
                  child: const HomePage(),
                ),
        ),
      ),
    );
  }
}
