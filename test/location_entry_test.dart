import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/data/schedule_database.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/features/location/app.dart';
import 'package:offline_course_schedule/features/location/domain.dart';
import 'package:offline_course_schedule/features/location/location.dart';
import 'package:offline_course_schedule/features/location/store.dart';
import 'package:offline_course_schedule/presentation/app_theme.dart';
import 'package:offline_course_schedule/presentation/home_page.dart'
    as schedule;

import 'location/ui_test.dart' show TestStore;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Schedule extends ScheduleController {
  final ScheduleData data;
  _Schedule(this.data);
  @override
  Future<ScheduleData> build() async => data;
}

class _Locator extends LocationController {
  int starts = 0, stops = 0;
  @override
  Future<void> start({bool requestPermission = true}) async {
    starts++;
    active = true;
    state = LocationState(
      fix: Fix(31.281, 121.501, 6, DateTime.now()),
      heading: 18,
      headingAt: DateTime.now(),
      compassReliable: true,
      status: 'ready',
    );
  }

  @override
  Future<void> stop() async {
    stops++;
    active = false;
    await Future<void>.value();
    if (mounted) state = const LocationState();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var fontLoaded = false;
  setUpAll(() async {
    sqfliteFfiInit();
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (font.existsSync()) {
      final loader = FontLoader('PreviewChinese')
        ..addFont(Future.value(ByteData.sublistView(await font.readAsBytes())));
      await loader.load();
      fontLoaded = true;
    }
    final root = Platform.environment['FLUTTER_ROOT'];
    if (root != null) {
      final font = File(
        '$root/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      );
      if (font.existsSync()) {
        final loader = FontLoader('MaterialIcons')
          ..addFont(
            Future.value(ByteData.sublistView(await font.readAsBytes())),
          );
        await loader.load();
      }
    }
  });
  final point = Place(
    id: 'entry',
    name: '图书馆入口',
    note: '靠近台阶',
    color: 0xff28a86b,
    fix: Fix(31.28175, 121.50124, 5, DateTime(2026, 10, 14)),
    createdAt: DateTime(2026, 10, 14),
  );
  Widget app(List<Override> overrides) => ProviderScope(
    overrides: overrides,
    child: RepaintBoundary(
      key: const ValueKey('integration-preview'),
      child: MaterialApp(
        theme: AppTheme.light(seedColor: accent).copyWith(
          textTheme: AppTheme.light(seedColor: accent).textTheme
              .apply(fontFamily: fontLoaded ? 'PreviewChinese' : null),
        ),
        debugShowCheckedModeBanner: false,
        home: const schedule.HomePage(),
      ),
    ),
  );
  Future<void> capture(WidgetTester tester, String name) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('integration-preview')),
    );
    await tester.runAsync(() async {
      final picture = await boundary.toImage(pixelRatio: 2);
      final data = await picture.toByteData(format: ui.ImageByteFormat.png);
      await Directory('artifacts').create(recursive: true);
      await File('artifacts/$name.png')
          .writeAsBytes(data!.buffer.asUint8List());
      picture.dispose();
    });
  }

  testWidgets('课表慢读取时可独立进入定位，列表不启动定位或权限请求', (tester) async {
    final pending = Completer<ScheduleDatabase>();
    var opens = 0;
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      LocationController.channel,
      (call) async {
        calls.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        LocationController.channel,
        null,
      ),
    );
    await tester.pumpWidget(
      app([
        databaseProvider.overrideWith((ref) => pending.future),
        placeStoreProvider.overrideWith((ref) async {
          opens++;
          return TestStore([]);
        }),
      ]),
    );
    await tester.pumpAndSettle();
    expect(opens, 0);
    await tester.tap(find.byTooltip('定位'));
    await tester.pumpAndSettle();
    expect(find.byType(LocationHomePage), findsOneWidget);
    expect(opens, 1);
    expect(calls, isEmpty);
    await tester.tap(find.byTooltip('返回课表'));
    await tester.pumpAndSettle();
    expect(find.text('正在读取本机课表'), findsOneWidget);
    expect(find.byTooltip('作业'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('课表旁小按钮进入定位与寻找，返回课表释放采样且保留原页面', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final locator = _Locator();
    final database = (await tester.runAsync(
      () => ScheduleDatabase.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      ),
    ))!;
    addTearDown(database.close);
    final today = DateTime(2026, 10, 14);
    final term = Term(
      id: currentTermId,
      name: '同济课程表',
      firstWeekMonday: DateTime(2026, 9, 7),
      totalWeeks: 20,
      periodsByWeekday: {
        for (var day = 1; day <= 7; day++)
          day: [
            const LessonPeriod(number: 1, startMinutes: 480, endMinutes: 580),
          ],
      },
    );
    await tester.pumpWidget(
      app([
        scheduleControllerProvider.overrideWith(
          () => _Schedule(ScheduleData(term: term)),
        ),
        databaseProvider.overrideWith((ref) async => database),
        clockProvider.overrideWith((ref) => Stream.value(today)),
        placeStoreProvider.overrideWith((ref) async => TestStore([point])),
        locationProvider.overrideWith((ref) => locator),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('作业'), findsOneWidget);
    expect(find.byTooltip('定位'), findsOneWidget);
    await capture(tester, 'preview-schedule-location-entry');
    await tester.tap(find.byTooltip('定位'));
    await tester.pumpAndSettle();
    expect(locator.starts, 0);
    await capture(tester, 'preview-integrated-location');
    await tester.tap(find.text('图书馆入口'));
    await tester.pumpAndSettle();
    expect(locator.starts, 1);
    expect(find.byType(DynamicDirection), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(locator.stops, 1);
    await tester.tap(find.byTooltip('返回课表'));
    await tester.pumpAndSettle();
    expect(find.text('同济课程表'), findsOneWidget);
    expect(find.byTooltip('作业'), findsOneWidget);
    expect(find.text('图书馆入口'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('无学期也可打开定位，定位数据库出错不影响课表并支持重试', (tester) async {
    var failed = true;
    await tester.pumpWidget(
      app([
        scheduleControllerProvider.overrideWith(
          () => _Schedule(const ScheduleData()),
        ),
        placeStoreProvider.overrideWith((ref) async {
          if (failed) throw StateError('test');
          return TestStore([]);
        }),
      ]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('定位'));
    await tester.pumpAndSettle();
    expect(find.text('定位点读取失败，请重试'), findsOneWidget);
    failed = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.byType(LocationHomePage), findsOneWidget);
    await tester.tap(find.byTooltip('返回课表'));
    await tester.pumpAndSettle();
    expect(find.text('开始设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
