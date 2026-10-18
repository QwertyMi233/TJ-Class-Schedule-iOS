import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/data/schedule_database.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/main.dart';
import 'package:offline_course_schedule/presentation/home_page.dart';
import 'package:sqflite/sqflite.dart' as plugin;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test('安卓单线程队列中两个启动连接不会因节假日事务互相等待', () async {
    final queue = _AndroidSqliteQueue();
    const channel = MethodChannel('com.tekartik.sqflite');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      queue.handle,
    );
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    var finished = false;
    final opening =
        Future.wait([
          ScheduleDatabase.open(
            factory: plugin.databaseFactorySqflitePlugin,
            path: 'C:/startup-test/schedule.db',
            singleInstance: false,
          ),
          ScheduleDatabase.open(
            factory: plugin.databaseFactorySqflitePlugin,
            path: 'C:/startup-test/schedule.db',
            singleInstance: false,
          ),
        ]).then((databases) {
          finished = true;
          return databases;
        });
    for (var i = 0; i < 100 && !finished && !queue.blocked; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final completedBeforeRelease = finished;
    // 释放模拟原生锁后再关闭连接，避免失败用例留下未结束的异步操作。
    queue.release();
    final databases = await opening;
    for (final database in databases) {
      await database.close();
    }
    expect(queue.blocked, isFalse);
    expect(completedBeforeRelease, isTrue);
    expect(queue.batches, 2);
  });

  testWidgets('真实控制器冷启动读取后显示已保存课程，等待期间不留空白', (tester) async {
    final db = await tester.runAsync(
      () => ScheduleDatabase.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      ),
    );
    final today = DateTime(2026, 10, 8);
    final term = Term(
      id: currentTermId,
      name: '已保存学期',
      firstWeekMonday: DateTime(2026, 9, 7),
      totalWeeks: 20,
      periodsByWeekday: {
        today.weekday: [
          const LessonPeriod(number: 1, startMinutes: 480, endMinutes: 525),
        ],
      },
    );
    final course = Course(
      id: 'saved-course',
      name: '已保存高等数学',
      teacher: '教师',
      colorValue: 0xFF7D9DCE,
      sessions: [
        CourseSession(
          id: 'saved-session',
          weekday: today.weekday,
          startPeriod: 1,
          endPeriod: 1,
          weekRule: WeekRule(startWeek: 1, endWeek: 20, type: WeekType.every),
          location: 'A101',
        ),
      ],
    );
    await tester.runAsync(() => db!.replaceTermSchedule(term, [course]));
    final pending = Completer<ScheduleDatabase>();
    ScheduleDatabase? backgroundDatabase;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) => pending.future),
          selectedDateProvider.overrideWith((ref) => today),
          clockProvider.overrideWith((ref) => Stream.value(today)),
        ],
        child: CourseScheduleApp(
          initialDate: null,
          initializeBackgroundSync: (database) async =>
              backgroundDatabase = database,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('正在读取本机课表'), findsOneWidget);
    expect(find.text('重新读取'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('开始设置'), findsNothing);
    expect(backgroundDatabase, isNull);
    pending.complete(db!);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );
    var loaded = false;
    container
        .read(scheduleControllerProvider.future)
        .then((_) => loaded = true);
    for (var i = 0; i < 100 && !loaded; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(loaded, isTrue);
    expect(find.text('已保存学期'), findsOneWidget);
    expect(find.text('已保存高等数学'), findsOneWidget);
    expect(find.text('正在读取本机课表'), findsNothing);
    expect(tester.takeException(), isNull);
    var settingsLoaded = false;
    Future.wait([
      container.read(themeSeedColorProvider.future),
      container.read(swipeAdvancesWeekProvider.future),
      container.read(backgroundImagePathProvider.future),
      container.read(backgroundOverlayOpacityProvider.future),
      container.read(cardOpacityProvider.future),
    ]).then((_) => settingsLoaded = true);
    for (var i = 0; i < 100 && !settingsLoaded; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(settingsLoaded, isTrue);
    expect(backgroundDatabase, same(db));
    await tester.tap(find.text('本周'));
    await tester.pumpAndSettle();
    expect(find.text('已保存高等数学'), findsWidgets);
    await tester.tap(find.text('今日'));
    await tester.pumpAndSettle();
    expect(find.text('已保存高等数学'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });

  testWidgets('数据库首次读取失败后点击重新读取能恢复页面', (tester) async {
    final db = (await tester.runAsync(
      () => ScheduleDatabase.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      ),
    ))!;
    var attempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) async {
            if (++attempts == 1) throw StateError('模拟首次读取失败');
            return db;
          }),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('本机课表读取失败，请重试'), findsOneWidget);
    await tester.tap(find.text('重新读取'));
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );
    var loaded = false;
    container
        .read(scheduleControllerProvider.future)
        .then((_) => loaded = true);
    for (var i = 0; i < 100 && !loaded; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('开始设置'), findsOneWidget);
    expect(find.text('本机课表读取失败，请重试'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });

  test('重新读取课表及设置不会重复初始化数据库字段', () async {
    final db = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWith((ref) async => db)],
    );
    addTearDown(container.dispose);
    await container.read(scheduleControllerProvider.future);
    final settings = [
      notificationSettingsProvider,
      swipeAdvancesWeekProvider,
      themeSeedColorProvider,
      backgroundImagePathProvider,
      widgetColorProvider,
      backgroundOverlayOpacityProvider,
      cardOpacityProvider,
      widgetRefreshModeProvider,
    ];
    for (final setting in settings) {
      await container.read(setting.future);
    }
    container.invalidate(databaseProvider);
    expect(
      await container.read(scheduleControllerProvider.future),
      isA<ScheduleData>(),
    );
    for (final setting in settings) {
      await container.read(setting.future);
      expect(container.read(setting).hasError, isFalse);
    }
  });
}

// 模拟 Android sqflite 单原生 worker、无 WAL 时的排他锁。
// 另一个连接读取等锁会占住 worker，排在后面的 COMMIT 无法执行。
class _AndroidSqliteQueue {
  Future<Object?> _tail = Future.value();
  final _unlock = Completer<void>();
  int _nextId = 0;
  int? _owner;
  bool blocked = false;
  bool _released = false;
  int batches = 0;

  void release() {
    _released = true;
    _unlock.complete();
  }

  Future<Object?> handle(MethodCall call) {
    final result = _tail.then((_) async {
      await Future<void>.delayed(Duration.zero);
      final args = (call.arguments as Map?) ?? {};
      final id = args['id'] as int?;
      final sql = args['sql'] as String? ?? '';
      // Android 将原始 BEGIN 转为排他事务；另一连接的读取也会等锁。
      if (!_released &&
          _owner != null &&
          _owner != id &&
          (call.method == 'query' || sql.startsWith('BEGIN'))) {
        blocked = true;
        await _unlock.future;
      }
      if (sql.startsWith('BEGIN')) {
        _owner = id;
        return {'transactionId': id};
      }
      if (sql == 'COMMIT' || sql == 'ROLLBACK') _owner = null;
      switch (call.method) {
        case 'openDatabase':
          return {'id': ++_nextId};
        case 'query':
          return {
            'columns': ['user_version'],
            'rows': [
              [10],
            ],
          };
        case 'batch':
          batches++;
          return <Object?>[];
        default:
          return null;
      }
    });
    _tail = result;
    return result;
  }
}
