import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/schedule_controller.dart';
import '../application/task_state.dart';
import 'next_course_widget_service.dart';
import 'task_widget_service.dart';

class WidgetLifecycle extends ConsumerStatefulWidget {
  const WidgetLifecycle({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<WidgetLifecycle> createState() => _WidgetLifecycleState();
}

class _WidgetLifecycleState extends ConsumerState<WidgetLifecycle>
    with WidgetsBindingObserver {
  bool _syncingTasks = false;
  bool _tasksChanged = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_syncCourses());
      unawaited(_syncTasks());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncCourses());
      unawaited(_syncTasks());
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheduleReady = ref.watch(scheduleControllerProvider).hasValue;
    if (scheduleReady) {
      ref.watch(widgetColorProvider);
      ref.watch(widgetRefreshModeProvider);
      ref.watch(taskRepositoryProvider);
      ref.listen(widgetColorProvider, (_, __) => unawaited(_syncCourses()));
      ref.listen(
        widgetRefreshModeProvider,
        (_, __) => unawaited(_syncCourses()),
      );
      ref.listen(taskRepositoryProvider, (_, __) => unawaited(_syncTasks()));
      ref.listen(taskRevisionProvider, (_, __) => unawaited(_syncTasks()));
    }
    ref.listen(scheduleControllerProvider, (_, __) {
      unawaited(_syncCourses());
      unawaited(_syncTasks());
    });
    return widget.child;
  }

  Future<void> _syncCourses() async {
    if (!mounted) return;
    final schedule = ref.read(scheduleControllerProvider).valueOrNull;
    if (schedule == null) return;
    final color = ref.read(widgetColorProvider);
    final refresh = ref.read(widgetRefreshModeProvider);
    try {
      await const NextCourseWidgetService().sync(
        schedule,
        colorValue: color.valueOrNull,
        refreshMode: refresh.valueOrNull,
        updateAppearance: color.hasValue && refresh.hasValue,
      );
    } catch (error) {
      debugPrint('课表小组件更新失败：$error');
    }
  }

  Future<void> _syncTasks() async {
    if (!mounted || !ref.read(scheduleControllerProvider).hasValue) return;
    if (_syncingTasks) {
      _tasksChanged = true;
      return;
    }
    _syncingTasks = true;
    try {
      final repository = await ref.read(taskRepositoryProvider.future);
      final tasks = await repository.loadVisible();
      if (mounted) await const TaskWidgetService().sync(tasks);
    } catch (error) {
      debugPrint('作业小组件更新失败：$error');
    } finally {
      _syncingTasks = false;
      if (_tasksChanged && mounted) {
        _tasksChanged = false;
        unawaited(_syncTasks());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
