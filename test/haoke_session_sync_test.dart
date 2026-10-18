import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/task_sync_controller.dart';
import 'package:offline_course_schedule/data/platform_credential_store.dart';
import 'package:offline_course_schedule/data/platform_task_client.dart';
import 'package:offline_course_schedule/data/schedule_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class LoginClient extends PlatformTaskClient {
  int logins = 0, checks = 0, reads = 0;
  String account = 'a';
  Object? loginFailure, checkFailure, readFailure;
  final readTokens = <String>[];
  @override
  Future<HaokeCredentials> renewHaoke(HaokeCredentials pair) async {
    logins++;
    if (loginFailure != null) throw loginFailure!;
    return const HaokeCredentials(token: 'new-token', ticket: 'new-ticket');
  }

  @override
  Future<String> verifyHaokeAccount(String token) async {
    checks++;
    if (checkFailure != null) throw checkFailure!;
    return account;
  }

  @override
  Future<PlatformTaskBatch> collectHaoke(String token) async {
    reads++;
    readTokens.add(token);
    if (readFailure != null) throw readFailure!;
    return PlatformTaskBatch(
      accountId: 'a',
      tasks: const [],
      warnings: const [],
      courseCount: 0,
      successfulCourses: 0,
      syncedAt: DateTime.now(),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late ScheduleDatabase db;
  late PlatformCredentialStore store;
  late LoginClient client;
  late TaskSyncService service;
  late DateTime now;
  setUp(() async {
    now = DateTime.now();
    FlutterSecureStorage.setMockInitialValues({});
    db = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    store = PlatformCredentialStore(db);
    client = LoginClient();
    service = TaskSyncService(
      db,
      credentials: store,
      client: client,
      backgroundTick: true,
      clock: () => now,
    );
    await store.save(
      'haoke',
      'a',
      jsonEncode({'version': 1, 'token': 'old-token', 'ticket': 'old-ticket'}),
    );
    await db.saveSetting('task_auto_sync', 'true');
  });
  tearDown(() async {
    service.close();
    await db.close();
  });

  test('健康凭证也主动登录，新凭证先保存再读取作业', () async {
    client.readFailure = const PlatformRequestException('暂时不可用', 503);
    await service.refresh();
    expect(client.logins, 1);
    expect(client.checks, 1);
    expect(client.readTokens, ['new-token']);
    expect(jsonDecode((await store.read('haoke'))!)['ticket'], 'new-ticket');
  });
  test('后台临时失败五分钟后补试，最多补两次，不被30分钟窗口跳过', () async {
    client.readFailure = const PlatformRequestException('超时', 503, true);
    await service.refresh();
    expect(await service.hasPendingHaokeRetry(), true);
    now = now.add(const Duration(minutes: 4));
    await service.refresh();
    expect(client.reads, 1);
    now = now.add(const Duration(minutes: 2));
    await service.refresh();
    expect(client.reads, 2);
    now = now.add(const Duration(minutes: 5));
    await service.refresh();
    expect(client.reads, 3);
    expect(await service.hasPendingHaokeRetry(), false);
    await service.refresh();
    expect(client.reads, 3);
    expect(client.logins, 1);
    expect(await db.loadSetting('task_haoke_error'), '网络不稳定，稍后再试');
    now = now.add(const Duration(minutes: 31));
    await service.refresh();
    expect(client.reads, 4);
    expect(await service.hasPendingHaokeRetry(), true);
  });
  test('重启后补试恢复，清除错误和补试状态，保留本机诊断', () async {
    client.readFailure = const PlatformRequestException('超时', 503, true);
    await service.refresh();
    expect(await db.loadSetting('task_haoke_error_at'), isNotNull);
    client.readFailure = null;
    now = now.add(const Duration(minutes: 6));
    final reopened = TaskSyncService(
      db,
      credentials: store,
      client: client,
      backgroundTick: true,
      clock: () => now,
    );
    await reopened.refresh();
    expect(client.reads, 2);
    expect(await reopened.hasPendingHaokeRetry(), false);
    expect(await db.loadSetting('task_haoke_error'), '');
    expect(await db.loadSetting('task_haoke_error_at'), isNull);
    expect(await db.loadSetting('task_haoke_read_diagnostic'), isNotNull);
  });
  test('登录验证断网后优先恢复候选，不重复生成新票据', () async {
    client.checkFailure = const PlatformRequestException('连接中断', 503, true);
    await service.refresh();
    expect(await service.hasPendingHaokeRetry(), true);
    expect(await store.readHaokeCandidate('a'), isNotNull);
    client.checkFailure = null;
    now = now.add(const Duration(minutes: 6));
    await service.refresh();
    expect(client.logins, 1);
    expect(client.checks, 2);
    expect(await db.loadSetting('task_haoke_session_error'), isNull);
    expect(await service.hasPendingHaokeRetry(), false);
  });
  test('候选等待网络验证时旧票据401不误报重新登录，补试后直接恢复读取', () async {
    var notified = 0;
    final subject = TaskSyncService(
      db,
      credentials: store,
      client: client,
      backgroundTick: true,
      clock: () => now,
      onAuthRequired: (_) async {
        notified++;
      },
    );
    client.checkFailure = const PlatformRequestException('验证超时', 503, true);
    client.readFailure = const PlatformRequestException('旧票据失效', 401);
    final result = await subject.refresh();
    expect(result['haoke'], '网络不稳定，稍后自动重试');
    expect(await db.loadSetting('task_haoke_needs_auth'), isNot('true'));
    expect(notified, 0);
    client.checkFailure = null;
    client.readFailure = null;
    now = now.add(const Duration(minutes: 6));
    await subject.refresh();
    expect(client.logins, 1);
    expect(client.reads, 2);
    expect(await subject.hasPendingHaokeRetry(), false);
    expect(await db.loadSetting('task_haoke_error'), '');
    expect(await db.loadSetting('task_haoke_session_error'), isNull);
  });
  test('认证拒绝不安排网络补试，断开后清理补试和诊断', () async {
    client.loginFailure = const PlatformRequestException('拒绝访问', 403);
    client.readFailure = const PlatformRequestException('拒绝访问', 403);
    await service.refresh();
    expect(await service.hasPendingHaokeRetry(), false);
    await service.disconnect('haoke');
    expect(await db.loadSetting('task_haoke_login_diagnostic'), isNull);
  });
  test('手动刷新可立即恢复，不等待后台补试时间', () async {
    client.readFailure = const PlatformRequestException('超时', 503, true);
    await service.refresh();
    client.readFailure = null;
    await service.refresh(manual: true);
    expect(client.reads, 2);
    expect(await service.hasPendingHaokeRetry(), false);
  });
  test('15分钟维护不受30分钟作业间隔影响，跨服务实例不重复登录', () async {
    await db.saveSetting(
      'task_haoke_attempt',
      DateTime.now().toIso8601String(),
    );
    await service.refresh();
    expect(client.logins, 1);
    expect(client.reads, 0);
    final reopened = TaskSyncService(
      db,
      credentials: store,
      client: client,
      backgroundTick: true,
    );
    await reopened.refresh();
    expect(client.logins, 1);
    await db.saveSetting(
      'task_haoke_login_attempt',
      DateTime.now().subtract(const Duration(minutes: 16)).toIso8601String(),
    );
    await reopened.refresh();
    expect(client.logins, 2);
    expect(client.reads, 0);
  });
  test('新值验证503保留候选，重建服务后先验证候选而不再次登录', () async {
    client.checkFailure = const PlatformRequestException('暂时不可用', 503);
    await service.refresh(manual: true);
    expect(jsonDecode((await store.read('haoke'))!)['token'], 'old-token');
    client.checkFailure = null;
    final reopened = TaskSyncService(db, credentials: store, client: client);
    await reopened.refresh(manual: true);
    expect(client.logins, 1);
    expect(client.checks, 2);
    expect(jsonDecode((await store.read('haoke'))!)['token'], 'new-token');
  });
  test('已标记401时先尝试主动登录恢复，再解除暂停', () async {
    await db.saveSetting('task_haoke_needs_auth', 'true');
    await service.refresh();
    expect(client.logins, 1);
    expect(client.reads, 1);
    expect(await db.loadSetting('task_haoke_needs_auth'), 'false');
  });
  test('关闭自动同步不登录，手动刷新仍可维护', () async {
    await db.saveSetting('task_auto_sync', 'false');
    await service.refresh();
    expect(client.logins, 0);
    expect(client.reads, 0);
    await service.refresh(manual: true);
    expect(client.logins, 1);
  });
  test('登录接口失败时现有凭证仍可同步，保留单独续期提示', () async {
    client.loginFailure = const PlatformRequestException('登录暂时失败', 503);
    await service.refresh();
    expect(client.readTokens, ['old-token']);
    expect(await db.loadSetting('task_haoke_session_error'), isNotEmpty);
  });
  test('返回不同账号不覆盖原凭证，并暂停自动登录等待重新连接', () async {
    client.account = 'b';
    await service.refresh();
    expect(jsonDecode((await store.read('haoke'))!)['token'], 'old-token');
    expect(client.reads, 0);
    expect(await db.loadSetting('task_haoke_login_blocked'), 'true');
    await db.deleteSetting('task_haoke_login_attempt');
    await service.refresh();
    expect(client.logins, 1);
  });
  test('连续手动刷新健康连接不会重复免密码登录', () async {
    await service.refresh(manual: true);
    await service.refresh(manual: true);
    expect(client.logins, 1);
    expect(client.reads, 2);
  });
  test('断开连接删除未验证候选，并停止后续维护', () async {
    client.checkFailure = const PlatformRequestException('网络不可用', 503);
    await service.refresh();
    expect(await store.readHaokeCandidate('a'), isNotNull);
    await service.disconnect('haoke');
    expect(await store.readHaokeCandidate('a'), isNull);
    expect(await db.loadSetting('task_haoke_login_attempt'), isNull);
    await service.refresh();
    expect(client.logins, 1);
  });
  test('重新连接清理旧候选和暂停状态，不会回用旧票据', () async {
    await store.saveHaokeCandidate(
      'a',
      jsonEncode({
        'version': 1,
        'token': 'obsolete',
        'ticket': 'obsolete-ticket',
      }),
    );
    await db.saveSetting('task_haoke_login_blocked', 'true');
    await service.connectHaoke(
      const HaokeCredentials(token: 'manual', ticket: 'manual-ticket'),
      confirmSwitch: (_, _) async => true,
    );
    expect(await store.readHaokeCandidate('a'), isNull);
    expect(await db.loadSetting('task_haoke_login_blocked'), isNull);
    await service.refresh();
    expect(client.logins, 0);
    expect(jsonDecode((await store.read('haoke'))!)['token'], 'manual');
  });
  test('权限拒绝后不因下一个周期再次自动登录', () async {
    client.loginFailure = const PlatformRequestException('权限拒绝', 403);
    await service.refresh();
    await db.deleteSetting('task_haoke_login_attempt');
    await service.refresh();
    expect(client.logins, 1);
    expect(await db.loadSetting('task_haoke_login_blocked'), 'true');
  });
  test('一次主动登录失败加作业401不会在同轮再次登录', () async {
    client.loginFailure = const PlatformRequestException('凭证被拒绝', 401);
    client.readFailure = const PlatformRequestException('凭证失效', 401);
    await service.refresh();
    expect(client.logins, 1);
    await service.refresh();
    expect(client.logins, 1);
  });
}
