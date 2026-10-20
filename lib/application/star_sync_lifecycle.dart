import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'schedule_controller.dart';
import 'star_sync_service.dart';

class StarSyncLifecycle extends ConsumerStatefulWidget {
  const StarSyncLifecycle({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<StarSyncLifecycle> createState() => _StarSyncLifecycleState();
}

class _StarSyncLifecycleState extends ConsumerState<StarSyncLifecycle>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _syncing = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _start() {
    if (!mounted || !ref.read(scheduleControllerProvider).hasValue) return;
    _started = true;
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => unawaited(_refresh()),
    );
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (!mounted || _syncing) return;
    _syncing = true;
    try {
      final db = await ref.read(databaseProvider.future);
      if (!mounted || await db.loadSetting('star_enabled') != 'true') return;
      await ref.read(scheduleControllerProvider.notifier).reloadMemos();
      if (!mounted) return;
      final service = await ref.read(starSyncServiceProvider.future);
      await service.refresh();
    } catch (_) {
      // 连接页保留失败状态；离线启动和普通课表使用不被附加同步阻塞。
    } finally {
      _syncing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
    } else {
      _timer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(scheduleControllerProvider, (_, next) {
      if (!_started && next.hasValue) _start();
    });
    return widget.child;
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
