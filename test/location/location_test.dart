import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/features/location/location.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocationController controller;
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          LocationController.channel,
          (_) async => null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('bicycle_finder/events'),
          (_) async => null,
        );
    controller = LocationController();
    await controller.start();
  });
  tearDown(() async {
    await controller.stop();
    controller.dispose();
  });
  test('拒绝缓存过期与无效坐标', () {
    controller.onEvent({
      'type': 'fix',
      'lat': 31,
      'lon': 121,
      'accuracy': 4,
      'ageMs': 20000,
    });
    expect(controller.state.fix, isNull);
    controller.onEvent({
      'type': 'fix',
      'lat': 100,
      'lon': 121,
      'accuracy': 4,
      'ageMs': 0,
    });
    expect(controller.state.status, 'error');
  });
  test('权限关闭立即清除坐标与箭头', () {
    controller.onEvent({
      'type': 'fix',
      'lat': 31,
      'lon': 121,
      'accuracy': 4,
      'ageMs': 0,
    });
    controller.onEvent({'type': 'heading', 'heading': 90, 'reliable': true});
    expect(controller.state.headingFresh(DateTime.now()), true);
    controller.onEvent({'type': 'status', 'status': 'disabled'});
    expect(controller.state.fix, isNull);
    expect(controller.state.heading, isNull);
  });
  test('无指南针精度时保留距离但禁用相对箭头', () {
    controller.onEvent({
      'type': 'fix',
      'lat': 31,
      'lon': 121,
      'accuracy': 4,
      'ageMs': 0,
    });
    controller.onEvent({'type': 'heading', 'heading': 90, 'reliable': false});
    expect(controller.state.fix, isNotNull);
    expect(controller.state.headingFresh(DateTime.now()), false);
  });
  test('结束会话后不接受任何迟到的定位事件', () async {
    await controller.stop();
    controller.onEvent({
      'type': 'fix',
      'lat': 31,
      'lon': 121,
      'accuracy': 4,
      'ageMs': 0,
    });
    expect(controller.state.fix, isNull);
  });
  test('后台暂停清空实时数据', () {
    controller.onEvent({
      'type': 'fix',
      'lat': 31,
      'lon': 121,
      'accuracy': 4,
      'ageMs': 0,
    });
    controller.suspend();
    expect(controller.state.fix, isNull);
  });
  test('快速结束再开始时，旧 stop 先于新 start 完成', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LocationController.channel, (call) async {
          calls.add(call.method);
          return null;
        });
    final stopped = controller.stop();
    final started = controller.start();
    await Future.wait([stopped, started]);
    expect(calls, ['stop', 'start']);
    expect(controller.active, true);
    expect(controller.state.status, 'waiting');
  });
}
