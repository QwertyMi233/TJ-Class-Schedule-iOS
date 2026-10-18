import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/data/schedule_database.dart';
import 'package:offline_course_schedule/presentation/task_connections_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test('好课提示区分补试、认证和普通失败，不暴露接口详情', () {
    expect(haokeConnectionNotice({}), isNull);
    expect(
      haokeConnectionNotice({
        'task_haoke_error': 'HTTP 503 /api/auth/tokenLogin',
      }),
      '暂时无法更新，稍后再试',
    );
    expect(
      haokeConnectionNotice({'task_haoke_session_error': '网络不稳定，稍后自动重试'}),
      '网络不稳定，稍后自动重试',
    );
    expect(
      haokeConnectionNotice({
        'task_haoke_needs_auth': 'true',
        'task_haoke_error': '网络不稳定，稍后自动重试',
      }),
      '请重新登录好课',
    );
  });
  testWidgets('登录与读取同时失败只显示一条简短提示，恢复后移除', (tester) async {
    late ScheduleDatabase db;
    await tester.runAsync(() async {
      db = await ScheduleDatabase.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      await db.saveSetting('task_haoke_error', '网络不稳定，稍后自动重试');
      await db.saveSetting('task_haoke_session_error', '网络不稳定，稍后自动重试');
      await db.saveSetting('task_haoke_error_at', '2026-10-18T10:00:00Z');
    });
    addTearDown(db.close);
    Future<void> showPage() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWith((ref) async => db)],
          child: const MaterialApp(home: TaskConnectionsPage()),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
    }

    await showPage();
    expect(find.text('网络不稳定，稍后自动重试'), findsOneWidget);
    expect(find.textContaining('上次尝试：'), findsOneWidget);
    expect(find.textContaining('2026-10-18T'), findsNothing);
    expect(tester.takeException(), isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.runAsync(() async {
      await db.deleteSetting('task_haoke_error');
      await db.deleteSetting('task_haoke_session_error');
      await db.deleteSetting('task_haoke_error_at');
    });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('网络不稳定，稍后自动重试'), findsNothing);
    expect(find.textContaining('上次尝试：'), findsNothing);
  });
}
