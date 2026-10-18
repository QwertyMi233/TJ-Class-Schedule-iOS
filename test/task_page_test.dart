import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:offline_course_schedule/data/platform_credential_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/application/task_sync_controller.dart';
import 'package:offline_course_schedule/application/task_state.dart';
import 'package:offline_course_schedule/data/schedule_database.dart';
import 'package:offline_course_schedule/data/task_repository.dart';
import 'package:offline_course_schedule/domain/task_record.dart';
import 'package:offline_course_schedule/import/task_capture.dart';
import 'package:offline_course_schedule/presentation/task_import_page.dart';
import 'package:offline_course_schedule/presentation/task_page.dart';
import 'package:offline_course_schedule/presentation/task_reminder_settings_page.dart';
import 'package:offline_course_schedule/notifications/notification_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Sync extends TaskSyncService {
  _Sync(super.db);
  int calls = 0, closes = 0;
  Map<String, String> result = {};
  bool fail = false;
  @override
  Future<Map<String, String>> refresh({bool manual = false}) async {
    calls++;
    if (fail) throw StateError('测试网络失败');
    return result;
  }

  @override
  void close() {
    closes++;
    super.close();
  }
}

class _Notifications extends NotificationService {
  _Notifications({this.allowed = true});
  final bool allowed;
  int tests = 0;
  @override
  Future<bool> sendTaskTestNotification() async {
    tests++;
    return allowed;
  }

  @override
  Future<void> requestAndroidPermissions() async {}
  @override
  Future<bool> notificationsEnabled() async => allowed;
}

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

  Future<void> show(
    WidgetTester tester,
    Widget page, {
    _Sync? sync,
    NotificationService? notifications,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) async => db),
          if (notifications != null)
            notificationServiceProvider.overrideWithValue(notifications),
          if (sync != null)
            taskSyncServiceProvider.overrideWith((ref) async {
              ref.onDispose(sync.close);
              return sync;
            }),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.5)),
            child: child!,
          ),
          home: page,
        ),
      ),
    );
    // SQLite/provider futures need real event-loop turns before settling animations.
    var tasksLoaded = false;
    if (page is TaskPage) {
      tester
          .widget<FutureBuilder<List<TaskRecord>>>(
            find.byType(FutureBuilder<List<TaskRecord>>),
          )
          .future!
          .then((_) => tasksLoaded = true);
    }
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (page is TaskPage) {
        if (tasksLoaded) break;
      } else if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();
  }

  testWidgets('320宽大字体五类可组合，退出重进保留选择且原任务不删除', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() => db.saveSetting('task_haoke_account', '23'));
    final repository = TaskRepository(db.database);
    for (final category in TaskRecord.haokeCategoryLabels.entries) {
      await tester.runAsync(
        () => repository.save(
          TaskRecord(
            id: 'haoke:${category.key}',
            title: '筛选测试${category.value}',
            course: '数学',
            platform: 'haoke',
            source: 'haoke',
            accountId: '23',
            createdAt: DateTime.now(),
            haokeCategories: category.key,
          ),
        ),
      );
    }
    await show(tester, const TaskPage(), sync: _Sync(db));
    final chip = find.byKey(const ValueKey('haoke-category-2'));
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    final exam = find.byKey(const ValueKey('haoke-category-8'));
    await tester.ensureVisible(exam);
    await tester.tap(exam);
    await tester.pumpAndSettle();
    final mind = find.byKey(const ValueKey('haoke-category-16'));
    await tester.ensureVisible(mind);
    await tester.tap(mind);
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(chip).selected, isFalse);
    expect(tester.widget<FilterChip>(exam).selected, isFalse);
    final quizTask = find.text('筛选测试课堂练习');
    await tester.scrollUntilVisible(
      quizTask,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('筛选测试作业/小测'), findsOneWidget);
    expect(quizTask, findsOneWidget);
    expect(find.text('筛选测试考试'), findsNothing);
    expect(find.text('筛选测试知识点资源'), findsNothing);
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (await tester.runAsync(
            () => db.loadSetting('task_haoke_visible_categories'),
          ) ==
          '5') {
        break;
      }
    }
    expect(
      await tester.runAsync(
        () => db.loadSetting('task_haoke_visible_categories'),
      ),
      '5',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await show(tester, const TaskPage(), sync: _Sync(db));
    await tester.ensureVisible(chip);
    expect(tester.widget<FilterChip>(chip).selected, isFalse);
    expect(
      tester
          .widget<FilterChip>(find.byKey(const ValueKey('haoke-category-4')))
          .selected,
      isTrue,
    );
    expect(await tester.runAsync(() => repository.loadAll()), hasLength(5));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('手机窄屏确认、取消、撤销；演示与真实作业分离，详情可滚动', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = TaskRepository(db.database);
    await tester.runAsync(
      () => repo.save(
        TaskRecord.manual(
          id: 'manual:ui',
          title: '真实作业',
          course: '很长的中文课程名称用于验证手机字体放大',
          platform: 'manual',
          url: '',
          note: List.filled(80, '长备注').join('\n'),
        ),
      ),
    );
    await show(tester, const TaskPage());
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect((await tester.runAsync(repo.loadAll))!.single.completed, isFalse);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认完成'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
    expect((await tester.runAsync(repo.loadAll))!.single.completed, isTrue);
    await tester.tap(find.text('撤销'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
    expect((await tester.runAsync(repo.loadAll))!.single.completed, isFalse);
    await tester.ensureVisible(find.text('查看演示'));
    await tester.tap(find.text('查看演示'));
    await tester.pumpAndSettle();
    expect(find.text('真实作业'), findsNothing);
    expect(find.text('演示 · 数学课后习题'), findsOneWidget);
    expect(await tester.runAsync(repo.loadAll), hasLength(1));
    await tester.tap(find.text('关闭演示'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('真实作业'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('真实作业'));
    await tester.pumpAndSettle();
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('320宽大字体展示倒计时、同科目颜色、失效入口和Token教程', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await db.saveSetting('task_canvas_needs_auth', 'true');
      final repo = TaskRepository(db.database);
      for (final id in ['one', 'two']) {
        await repo.save(
          TaskRecord.manual(
            id: id,
            title: '倒计时$id',
            course: '数学',
            platform: 'manual',
            url: '',
            note: '',
            dueAt: DateTime.now().add(const Duration(hours: 5)),
          ),
        );
      }
    });
    await show(tester, const TaskPage());
    expect(find.text('重新加载 Token'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('倒计时two'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('剩余 '), findsWidgets);
    final colors = <Color>[];
    for (final id in ['one', 'two']) {
      await tester.scrollUntilVisible(
        find.text('倒计时$id'),
        id == 'one' ? -120 : 120,
        scrollable: find.byType(Scrollable).first,
      );
      final card = tester.widget<Card>(
        find
            .ancestor(of: find.text('倒计时$id'), matching: find.byType(Card))
            .first,
      );
      colors.add((card.shape! as RoundedRectangleBorder).side.color);
    }
    expect(colors.first, colors.last);
    await tester.scrollUntilVisible(
      find.text('Token 与使用教程'),
      -180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Token 与使用教程'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Canvas'), findsWidgets);
    expect(find.textContaining('好课'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('自定义提前小时保存；非法输入与系统拒绝通知不会启用提醒', (tester) async {
    for (final allowed in [false, true]) {
      final notifications = _Notifications(allowed: allowed);
      await show(
        tester,
        const TaskReminderSettingsPage(),
        notifications: notifications,
      );
      await tester.tap(find.byType(Switch));
      await tester.enterText(find.byType(TextField), '0');
      await tester.ensureVisible(find.text('保存'));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('请输入 1–8760 的整小时数'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '7');
      await tester.tap(find.text('保存'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      final saved = await tester.runAsync(
        () => db.loadSetting('task_reminders'),
      );
      final settings = saved == null
          ? <String, dynamic>{'enabled': false}
          : jsonDecode(saved) as Map<String, dynamic>;
      expect(settings['enabled'], allowed);
      if (allowed) {
        expect(settings['hours'], 7);
      } else {
        expect(find.text('系统通知尚未允许，请先打开系统通知设置'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await notifications.dispose();
    }
  });

  testWidgets('断开连接删除凭证，离线仍显示最后账号的作业', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = PlatformCredentialStore(db);
    await tester.runAsync(() async {
      await store.save('canvas', 'a', 'test-token');
      await TaskRepository(db.database).save(
        TaskRecord(
          id: 'canvas:a:1:2',
          title: '断开后的离线作业',
          course: '数学',
          platform: 'canvas',
          source: 'canvas',
          accountId: 'a',
          createdAt: DateTime.utc(2026, 10, 1),
        ),
      );
      await store.remove('canvas');
      expect(await store.read('canvas'), isNull);
    });
    await show(tester, const TaskPage());
    expect(find.text('断开后的离线作业'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('后台停止定时和网络资源，恢复前台重建，退出取消', (tester) async {
    final sync = _Sync(db);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await show(tester, const TaskPage(), sync: sync);
    final calls = sync.calls;
    expect(calls, greaterThan(0));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.pump(const Duration(minutes: 31));
    expect(sync.calls, calls);
    expect(sync.closes, greaterThan(0));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
    expect(sync.calls, greaterThan(calls));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    final stopped = sync.calls;
    await tester.pump(const Duration(minutes: 31));
    expect(sync.calls, stopped);
    expect(tester.takeException(), isNull);
  });

  testWidgets('同步后旧课程消失时，全部课程筛选会实际显示新课程', (tester) async {
    final repo = TaskRepository(db.database);
    await tester.runAsync(
      () => repo.save(
        TaskRecord(
          id: 'old',
          title: '旧作业',
          course: '旧课程',
          platform: 'manual',
          source: 'manual',
          accountId: 'local',
          createdAt: DateTime.now(),
        ),
      ),
    );
    await show(tester, const TaskPage(), sync: _Sync(db));
    final courses = find.byType(DropdownButton<String>).at(1);
    await tester.ensureVisible(courses);
    await tester.tap(courses);
    await tester.pumpAndSettle();
    await tester.tap(find.text('旧课程').last);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await repo.deleteManual('old');
      await repo.save(
        TaskRecord(
          id: 'new',
          title: '新作业',
          course: '新课程',
          platform: 'manual',
          source: 'manual',
          accountId: 'local',
          createdAt: DateTime.now(),
        ),
      );
    });
    final context = tester.element(find.byType(TaskPage));
    ProviderScope.containerOf(
      context,
    ).read(taskRevisionProvider.notifier).state++;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
    expect(find.text('全部课程'), findsOneWidget);
    expect(find.text('新作业'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('自动成功、失败和恢复前台均不弹同步提示', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final sync = _Sync(db)..result = {'canvas': '同步完成：10 项作业'};
    await show(tester, const TaskPage(), sync: sync);
    expect(sync.calls, greaterThan(0));
    expect(find.byType(SnackBar), findsNothing);
    sync.fail = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('手动同步提示不重复排队', (tester) async {
    final sync = _Sync(db)..result = {'canvas': '同步完成：10 项作业'};
    await show(tester, const TaskPage(), sync: sync);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('同步并刷新'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pumpAndSettle();
    }
    expect(find.byType(SnackBar), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('重新登录提示带按钮仍在三秒后消失，页面入口保留', (tester) async {
    await tester.runAsync(
      () => db.saveSetting('task_canvas_needs_auth', 'true'),
    );
    final sync = _Sync(db)..result = {'canvas': '需要重新登录'};
    await show(tester, const TaskPage(), sync: sync);
    await tester.tap(find.byTooltip('同步并刷新'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(tester.widget<SnackBar>(find.byType(SnackBar)).persist, isFalse);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('重新加载 Token'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('通知测试发送成功反馈，拒绝权限引导设置且提示自动关闭', (tester) async {
    for (final allowed in [true, false]) {
      final notices = _Notifications(allowed: allowed);
      await show(tester, const TaskPage(), notifications: notices);
      await tester.ensureVisible(find.text('通知测试'));
      await tester.tap(find.text('通知测试'));
      await tester.pumpAndSettle();
      expect(notices.tests, 1);
      expect(
        find.text(allowed ? '测试通知已发送，请查看通知栏' : '系统通知未允许，请在设置中开启'),
        findsOneWidget,
      );
      if (!allowed) expect(find.text('通知设置'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await notices.dispose();
    }
  });

  testWidgets('预览后修改 JSON 清除旧预览和确认状态', (tester) async {
    await show(tester, const TaskImportPage());
    final input = jsonEncode({
      'version': 1,
      'tasks': [
        {'title': '导入任务', 'course': '数学', 'platform': 'manual'},
      ],
    });
    await tester.enterText(find.byType(TextField), input);
    await tester.tap(find.text('预览并核对'));
    await tester.pumpAndSettle();
    expect(find.text('待导入 1 项'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '{}');
    await tester.pumpAndSettle();
    expect(find.text('待导入 1 项'), findsNothing);
    expect(find.text('确认导入'), findsNothing);
    expect(await tester.runAsync(TaskRepository(db.database).loadAll), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  test('采集仅接受官方教学平台与指定校园 OJ', () {
    for (final url in [
      'https://canvas.tongji.edu.cn/courses/1',
      'https://tongji.aihaoke.net/student/course',
      'https://i.chaoxing.com/base',
      'http://192.168.180.213:18080/d/a',
    ]) {
      expect(canCaptureTaskPage(Uri.parse(url)), isTrue);
    }
    for (final url in [
      'https://canvas.tongji.edu.cn.evil.example/',
      'https://evil.example/',
      'http://tongji.aihaoke.net/',
      'https://user:pass@tongji.aihaoke.net/',
      'http://192.168.180.213:80/',
    ]) {
      expect(canCaptureTaskPage(Uri.parse(url)), isFalse);
    }
  });
}
