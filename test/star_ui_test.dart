import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/application/star_sync_service.dart';
import 'package:offline_course_schedule/data/schedule_database.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/domain/star_activity.dart';
import 'package:offline_course_schedule/main.dart';
import 'package:offline_course_schedule/presentation/star_connection_page.dart';
import 'package:offline_course_schedule/widget/next_course_widget_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'star_activity_test.dart' show ticket;
import 'star_sync_test.dart' show FakeStarClient;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  const channel = MethodChannel('offline_course_schedule/widget');
  late ScheduleDatabase db;
  final day = DateTime(2026, 10, 21);
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    db = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    await db.replaceTermSchedule(
      Term(
        id: currentTermId,
        name: '测试',
        firstWeekMonday: DateTime(2026, 10, 19),
        totalWeeks: 1,
        periodsByWeekday: {},
      ),
      [],
    );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await db.close();
  });

  testWidgets('从主界面接入后今日、本周和小组件使用相同活动信息', (tester) async {
    Map<Object?, Object?>? payload;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'update') {
        payload = call.arguments as Map<Object?, Object?>;
      }
      return null;
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) async => db),
          selectedDateProvider.overrideWith((ref) => day),
          clockProvider.overrideWith((ref) => Stream.value(day)),
          starSyncServiceProvider.overrideWith(
            (ref) async => StarSyncService(
              db,
              client: FakeStarClient(),
              clock: () => DateTime.utc(2026, 10, 20),
              onChanged: () =>
                  ref.read(scheduleControllerProvider.notifier).reloadMemos(),
            ),
          ),
        ],
        child: const CourseScheduleApp(),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CourseScheduleApp)),
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
    expect(loaded, isTrue);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('卓越星活动同步'));
    await tester.pumpAndSettle();
    expect(find.byType(StarConnectionPage), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('手动令牌（备用）'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isTrue,
    );
    await tester.enterText(find.byType(TextField), 'fixture-refresh');
    await tester.ensureVisible(find.text('连接并同步'));
    await tester.tap(find.text('连接并同步'));
    for (var i = 0; i < 100 && find.text('已连接卓越星').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('已连接卓越星'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('校园讲座'), findsOneWidget);
    expect(find.text('同济楼 301'), findsOneWidget);
    expect(find.textContaining('18:00'), findsWidgets);
    expect((payload!['courses'] as List).single['name'], '校园讲座');
    expect((payload!['courses'] as List).single['isMemo'], isTrue);
    await tester.tap(find.text('本周'));
    await tester.pumpAndSettle();
    expect(find.text('校园讲座'), findsOneWidget);
    expect(find.text('同济楼 301'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('后台课表组件缓存含时间地点，且没有账号凭据', () async {
    final memo = StarActivity.fromTicket(ticket()).toMemos('a').single;
    final saved = await db.loadTermSchedule(currentTermId);
    await const NextCourseWidgetService().syncBackground(
      ScheduleData(term: saved!.term, memos: [memo]),
      now: day,
    );
    final prefs = await SharedPreferences.getInstance();
    final text = prefs.getString('schedule_widget_courses')!;
    final row = (jsonDecode(text) as List).single;
    expect(row['name'], memo.title);
    expect(row['location'], memo.location);
    expect(row['time'], '18:00');
    expect(text, isNot(contains('Token')));
  });

  test('手工编辑旧快照时不会覆盖或删除后台刚同步的活动', () async {
    final manual = Memo(
      id: 'm',
      title: '手工',
      colorValue: 1,
      date: day,
      startMinutes: 1,
      endMinutes: 2,
    );
    await db.replaceTermMemos(currentTermId, [manual]);
    final before = await db.loadMemos(currentTermId);
    final synced = StarActivity.fromTicket(ticket()).toMemos('a').single;
    await db.replaceTermMemos(currentTermId, [...before, synced]);
    final edited = Memo(
      id: manual.id,
      title: '已编辑',
      colorValue: 1,
      date: day,
      startMinutes: 1,
      endMinutes: 2,
    );
    await db.replaceTermMemos(currentTermId, [edited], previousMemos: before);
    final after = await db.loadMemos(currentTermId);
    expect(after, hasLength(2));
    expect(after.singleWhere((memo) => memo.source == 'star').title, '校园讲座');
  });
}
