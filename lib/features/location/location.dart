import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain.dart';

class LocationState {
  final Fix? fix;
  final double? heading;
  final DateTime? headingAt;
  final bool compassReliable;
  final String status;
  const LocationState({
    this.fix,
    this.heading,
    this.headingAt,
    this.compassReliable = false,
    this.status = 'idle',
  });
  bool headingFresh(DateTime now) =>
      heading != null &&
      compassReliable &&
      headingAt != null &&
      now.difference(headingAt!) <= const Duration(seconds: 3);
}

class LocationController extends StateNotifier<LocationState> {
  static const channel = MethodChannel('offline_course_schedule/location');
  static const events = EventChannel('offline_course_schedule/location_events');
  StreamSubscription<dynamic>? subscription;
  Timer? clock;
  bool active = false;
  int session = 0;
  Future<void> operations = Future.value();
  LocationController() : super(const LocationState());

  Future<void> start({bool requestPermission = true}) async {
    active = true;
    final token = ++session;
    state = const LocationState(status: 'waiting');
    clock ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !active) return;
      final now = DateTime.now();
      // 超时后清除指引，而不是把旧坐标继续当成实时位置。
      if (state.fix != null && !state.fix!.freshAt(now)) {
        state = const LocationState(status: 'stale');
      } else if (state.heading != null &&
          state.headingAt != null &&
          now.difference(state.headingAt!) > const Duration(seconds: 3)) {
        state = LocationState(fix: state.fix, status: state.status);
      }
    });
    // 串行关闭旧事件流、创建新事件流，避免快速切换定位点时旧会话关闭新会话。
    operations = operations.then((_) async {
      if (!mounted || !active || token != session) return;
      await subscription?.cancel();
      if (!mounted || !active || token != session) return;
      subscription = events.receiveBroadcastStream().listen(
        (event) {
          if (token == session) onEvent(event);
        },
        onError: (_) {
          if (mounted && active && token == session) {
            state = const LocationState(status: 'error');
          }
        },
      );
      try {
        await channel.invokeMethod<void>('start', {
          'requestPermission': requestPermission,
        });
      } on PlatformException {
        if (mounted && active && token == session) {
          state = const LocationState(status: 'error');
        }
      } on MissingPluginException {
        if (mounted && active && token == session) {
          state = const LocationState(status: 'unsupported');
        }
      }
    });
    await operations;
  }

  void onEvent(dynamic value) {
    if (!mounted || !active || value is! Map) return;
    final event = Map<String, dynamic>.from(value);
    switch (event['type']) {
      case 'fix':
        try {
          final age = (event['ageMs'] as num).toInt();
          if (age < 0 || age > 15000) return;
          final fix = Fix(
            (event['lat'] as num).toDouble(),
            (event['lon'] as num).toDouble(),
            (event['accuracy'] as num).toDouble(),
            DateTime.now().subtract(Duration(milliseconds: age)),
          );
          state = LocationState(
            fix: fix,
            heading: state.heading,
            headingAt: state.headingAt,
            compassReliable: state.compassReliable,
            status: 'ready',
          );
        } catch (_) {
          state = const LocationState(status: 'error');
        }
      case 'heading':
        final heading = event['heading'];
        final valid = heading is num && heading.toDouble().isFinite;
        state = LocationState(
          fix: state.fix,
          status: state.status,
          heading: valid ? normalize(heading.toDouble()) : null,
          headingAt: valid ? DateTime.now() : null,
          compassReliable: valid && event['reliable'] == true,
        );
      case 'status':
        state = LocationState(status: event['status'] as String? ?? 'error');
    }
  }

  void suspend() {
    if (mounted) state = const LocationState(status: 'waiting');
  }

  Future<void> stop() async {
    active = false;
    final token = ++session;
    clock?.cancel();
    clock = null;
    operations = operations.then((_) async {
      final old = subscription;
      subscription = null;
      await old?.cancel();
      try {
        await channel.invokeMethod<void>('stop');
      } catch (_) {
        /* 页面关闭后释放资源。 */
      }
      if (mounted && !active && token == session) state = const LocationState();
    });
    await operations;
  }

  Future<void> settings({bool location = false}) =>
      channel.invokeMethod<void>(location ? 'locationSettings' : 'appSettings');
  @override
  void dispose() {
    active = false;
    session++;
    subscription?.cancel();
    clock?.cancel();
    channel.invokeMethod<void>('stop').catchError((_) {});
    super.dispose();
  }
}

final locationProvider =
    StateNotifierProvider<LocationController, LocationState>(
      (ref) => LocationController(),
    );

String statusText(String status) => switch (status) {
  'denied' => '需要定位权限才能保存和寻找',
  'deniedForever' => '定位权限已关闭，请在设置中允许',
  'disabled' => '请打开手机的定位开关',
  'stale' => '定位信号中断，正在等待更新',
  'unsupported' => '此设备不支持定位',
  'error' => '定位暂不可用，请重试',
  _ => '正在获取位置，请到开阔处稍等',
};
