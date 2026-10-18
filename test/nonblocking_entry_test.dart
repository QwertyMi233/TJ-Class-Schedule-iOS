import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/application/task_state.dart';
import 'package:offline_course_schedule/application/task_sync_controller.dart';
import 'package:offline_course_schedule/data/schedule_database.dart';
import 'package:offline_course_schedule/data/task_repository.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/domain/task_record.dart';
import 'package:offline_course_schedule/presentation/home_page.dart';
import 'package:offline_course_schedule/presentation/task_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late ScheduleDatabase db;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
  });
  tearDown(() => db.close());

  testWidgets('课表读取未完成仍可进入作业，没有整页转圈或错误的首次设置', (tester) async {
    final pending = Completer<ScheduleDatabase>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) => pending.future),
          taskSyncServiceProvider.overrideWith(
            (ref) => Completer<TaskSyncService>().future,
          ),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('开始设置'), findsNothing);
    await tester.tap(find.byTooltip('作业'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskPage), findsOneWidget);
    expect(find.text('搜索作业、课程或平台'), findsOneWidget);
    expect(find.text('没有匹配的作业，可调整筛选或好课显示内容'), findsNothing);
    pending.complete(db);
    await _settleTasks(tester);
    expect(find.text('没有匹配的作业，可调整筛选或好课显示内容'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('开始设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('作业首次慢读取仍能搜索和查看演示，数据完成后显示本机记录', (tester) async {
    final pending = Completer<ScheduleDatabase>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) => pending.future),
          taskSyncServiceProvider.overrideWith(
            (ref) => Completer<TaskSyncService>().future,
          ),
        ],
        child: const MaterialApp(home: TaskPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('待完成 0  ·  已完成 0  ·  逾期 0'), findsNothing);
    await tester.tap(find.text('查看演示'));
    await tester.pumpAndSettle();
    expect(find.text('关闭演示'), findsOneWidget);
    await tester.tap(find.text('关闭演示'));
    pending.complete(db);
    await _settleTasks(tester);
    expect(find.text('待完成 0  ·  已完成 0  ·  逾期 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('重复进入先显示已有作业，读取失败保留记录并允许重试', (tester) async {
    final repository = _DelayedRepository(db);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) async => db),
          taskRepositoryProvider.overrideWith((ref) async => repository),
          taskSyncServiceProvider.overrideWith(
            (ref) => Completer<TaskSyncService>().future,
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const TaskPage()),
                ),
                child: const Text('打开作业'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开作业'));
    await _settleTasks(tester);
    expect(find.text('本机缓存作业'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    repository.pending = Completer<List<TaskRecord>>();
    await tester.tap(find.text('打开作业'));
    await tester.pumpAndSettle();
    expect(find.text('本机缓存作业'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    for (var i = 0; i < 100 && repository.calls < 2; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(repository.calls, 2);
    repository.pending!.completeError(StateError('测试读取失败'));
    await tester.pumpAndSettle();
    expect(find.text('本机缓存作业'), findsOneWidget);
    expect(find.textContaining('读取作业失败'), findsOneWidget);
    repository.pending = null;
    await tester.tap(find.text('重试'));
    await _settleTasks(tester);
    expect(find.textContaining('读取作业失败'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('读取前修改好课分类，旧设置不覆盖刚选的内容', (tester) async {
    final pending = Completer<ScheduleDatabase>();
    final task = TaskRecord(
      id: 'haoke:local',
      title: '缓存好课任务',
      course: '数学',
      platform: 'haoke',
      source: 'haoke',
      accountId: '23',
      createdAt: DateTime(2026, 10, 6),
      haokeCategories: 1,
    );
    final repository = _DelayedRepository(db)
      ..pending = Completer<List<TaskRecord>>();
    repository.pending!.complete([task]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) => pending.future),
          taskCacheProvider.overrideWith((ref) => [task]),
          taskRepositoryProvider.overrideWith((ref) async => repository),
          taskSyncServiceProvider.overrideWith(
            (ref) => Completer<TaskSyncService>().future,
          ),
        ],
        child: const MaterialApp(home: TaskPage()),
      ),
    );
    await tester.pumpAndSettle();
    final resources = find.byKey(const ValueKey('haoke-category-2'));
    await tester.ensureVisible(resources);
    await tester.tap(resources);
    await tester.pumpAndSettle();
    pending.complete(db);
    await _settleTasks(tester);
    expect(tester.widget<FilterChip>(resources).selected, isFalse);
    expect(
      await tester.runAsync(
        () => db.loadSetting('task_haoke_visible_categories'),
      ),
      '29',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('通知新作业未在旧缓存里，读取后仍能打开详情', (tester) async {
    final task = TaskRecord(
      id: 'local',
      title: '通知新作业',
      course: '数学',
      platform: 'manual',
      source: 'manual',
      accountId: '',
      createdAt: DateTime(2026, 10, 6),
    );
    final repository = _DelayedRepository(db)
      ..pending = Completer<List<TaskRecord>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) async => db),
          taskCacheProvider.overrideWith((ref) => []),
          taskRepositoryProvider.overrideWith((ref) async => repository),
          taskSyncServiceProvider.overrideWith(
            (ref) => Completer<TaskSyncService>().future,
          ),
        ],
        child: const MaterialApp(home: TaskPage(initialTaskId: 'local')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    repository.pending!.complete([task]);
    await _settleTasks(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('保存课表时保留数据，写入完成后再更新', () async {
    final term = Term(
      id: currentTermId,
      name: '原学期',
      firstWeekMonday: DateTime(2026, 9, 7),
      totalWeeks: 20,
      periodsByWeekday: const {},
    );
    await db.replaceTermSchedule(term, []);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWith((ref) async => db)],
    );
    addTearDown(container.dispose);
    await container.read(scheduleControllerProvider.future);
    final blocked = Completer<void>();
    final entered = Completer<void>();
    final lock = db.database.transaction((txn) async {
      entered.complete();
      await blocked.future;
    });
    await entered.future;
    final saving = container
        .read(scheduleControllerProvider.notifier)
        .saveTerm(
          Term(
            id: currentTermId,
            name: '新学期',
            firstWeekMonday: term.firstWeekMonday,
            totalWeeks: 20,
            periodsByWeekday: const {},
          ),
        );
    try {
      expect(container.read(scheduleControllerProvider).isLoading, isFalse);
      expect(
        container.read(scheduleControllerProvider).valueOrNull?.term?.name,
        '原学期',
      );
    } finally {
      blocked.complete();
      await lock;
      await saving;
    }
    expect(
      container.read(scheduleControllerProvider).valueOrNull?.term?.name,
      '新学期',
    );
  });
}

Future<void> _settleTasks(WidgetTester tester) async {
  await tester.pumpAndSettle();
  final future = tester
      .widget<FutureBuilder<List<TaskRecord>>>(
        find.byType(FutureBuilder<List<TaskRecord>>),
      )
      .future;
  var completed = false;
  future!.then((_) => completed = true);
  for (var i = 0; i < 100 && !completed; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(completed, isTrue);
  await tester.pumpAndSettle();
}

class _DelayedRepository extends TaskRepository {
  _DelayedRepository(ScheduleDatabase db) : super(db.database);
  Completer<List<TaskRecord>>? pending;
  int calls = 0;

  @override
  Future<List<TaskRecord>> loadVisible() async {
    calls++;
    return pending != null
        ? pending!.future
        : [
            TaskRecord(
              id: 'local',
              title: '本机缓存作业',
              course: '数学',
              platform: 'manual',
              source: 'manual',
              accountId: '',
              createdAt: DateTime(2026, 10, 6),
            ),
          ];
  }
}
