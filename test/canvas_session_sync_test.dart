import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/task_sync_controller.dart';
import 'package:offline_course_schedule/data/canvas_session_manager.dart';
import 'package:offline_course_schedule/data/platform_credential_store.dart';
import 'package:offline_course_schedule/data/platform_task_client.dart';
import 'package:offline_course_schedule/data/schedule_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class SessionFake extends CanvasSessionManager {
  String? renewed = 'new-value';
  int calls = 0, disabled = 0;
  Object? failure;
  int configured = 0;
  @override
  Future<String> configure(CanvasTokenOption option) async {
    configured++;
    return renewed!;
  }

  @override
  Future<String?> prepare(String account) async {
    calls++;
    if (failure != null) throw failure!;
    return renewed;
  }

  @override
  Future<void> disable() async {
    disabled++;
  }

  @override
  Future<void> clear() async {
    disabled++;
  }
}

class SessionClient extends PlatformTaskClient {
  final tokens = <String>[];
  bool unavailable = false;
  @override
  Future<PlatformTaskBatch> collectCanvas(String token) async {
    tokens.add(token);
    if (unavailable) throw const PlatformRequestException('网络暂不可用', 503);
    return PlatformTaskBatch(
      accountId: 'a',
      tasks: const [],
      warnings: const [],
      courseCount: 1,
      successfulCourses: 1,
      syncedAt: DateTime.now(),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late ScheduleDatabase db;
  late PlatformCredentialStore credentials;
  late SessionFake session;
  late SessionClient client;
  late TaskSyncService service;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    db = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    credentials = PlatformCredentialStore(db);
    session = SessionFake();
    client = SessionClient();
    service = TaskSyncService(
      db,
      credentials: credentials,
      client: client,
      canvasSession: session,
    );
    await credentials.save('canvas', 'a', 'old-value');
    await db.saveSetting('task_auto_sync', 'true');
  });
  tearDown(() async {
    service.close();
    await db.close();
  });
  test('新值先保存，作业读取503后仍能使用已轮换凭证', () async {
    client.unavailable = true;
    await service.refresh(manual: true);
    expect(client.tokens, ['new-value']);
    expect(await credentials.read('canvas'), 'new-value');
  });
  test('旧状态已提示认证失效时，先尝试静默恢复再同步', () async {
    await db.saveSetting('task_canvas_needs_auth', 'true');
    await service.refresh();
    expect(session.calls, 1);
    expect(client.tokens, ['new-value']);
    expect(await db.loadSetting('task_canvas_needs_auth'), 'false');
  });
  test('30分钟作业节流不阻止15分钟连接维护', () async {
    await db.saveSetting(
      'task_canvas_attempt',
      DateTime.now().toIso8601String(),
    );
    await service.refresh();
    expect(session.calls, 1);
    expect(client.tokens, isEmpty);
    expect(await credentials.read('canvas'), 'new-value');
  });
  test('关闭自动同步时不续期，手动刷新仍可恢复', () async {
    await db.saveSetting('task_auto_sync', 'false');
    await service.refresh();
    expect(session.calls, 0);
    await service.refresh(manual: true);
    expect(session.calls, 1);
  });
  test('网页登录过期但现有Bearer有效时仍保留读取能力', () async {
    session.failure = const CanvasSessionException('login_required');
    await service.refresh(manual: true);
    expect(client.tokens, ['old-value']);
    expect(await db.loadSetting('task_canvas_session_error'), isNotEmpty);
  });
  test('手动换票和断开连接不再让旧续期配置覆盖新连接', () async {
    await service.connectCanvas(
      'manual-value',
      confirmSwitch: (_, _) async => true,
    );
    expect(session.disabled, 1);
    await service.disconnect('canvas');
    expect(session.disabled, 2);
    expect(await credentials.activeAccount('canvas'), isNull);
  });
  test('取消账号切换在服务器令牌变更之前生效', () async {
    final saved = await service.connectCanvasSession(
      const CanvasTokenOption(id: '7', purpose: 'dedicated', accountId: 'b'),
      confirmSwitch: (_, _) async => false,
    );
    expect(saved, false);
    expect(session.configured, 0);
    expect(await credentials.activeAccount('canvas'), 'a');
    expect(await credentials.read('canvas'), 'old-value');
  });
  test('启用续期后首次数据读取失败也保留新凭证', () async {
    client.unavailable = true;
    await expectLater(
      service.connectCanvasSession(
        const CanvasTokenOption(id: '7', purpose: 'dedicated', accountId: 'a'),
        confirmSwitch: (_, _) async => true,
      ),
      throwsA(isA<PlatformRequestException>()),
    );
    expect(session.configured, 1);
    expect(await credentials.read('canvas'), 'new-value');
  });
}
