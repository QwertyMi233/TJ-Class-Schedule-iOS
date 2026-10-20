import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/task_sync_controller.dart';
import 'package:offline_course_schedule/data/haoke_password_login.dart';
import 'package:offline_course_schedule/data/platform_credential_store.dart';
import 'package:offline_course_schedule/data/platform_task_client.dart';
import 'package:offline_course_schedule/data/schedule_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'task_sync_service_test.dart' show FakeClient, batch;

class PasswordTasks extends FakeClient {
  Object? renewalError;
  @override
  Future<HaokeCredentials> renewHaoke(HaokeCredentials credentials) async {
    renewals++;
    if (renewalError != null) throw renewalError!;
    return const HaokeCredentials(token: 'rotated', ticket: 'new-ticket');
  }
}

class PasswordClient extends PasswordLoginClient {
  int calls = 0;
  String accountId = 'a';
  LoginFailure? failure;
  @override
  Future<({String accountId, HaokeCredentials pair})> login(
    String account,
    String password,
    String mode,
  ) async {
    calls++;
    if (failure != null) throw failure!;
    return (
      accountId: accountId,
      pair: HaokeCredentials(
        token: 'password-token-$calls',
        ticket: 'password-ticket-$calls',
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late ScheduleDatabase db;
  late PlatformCredentialStore store;
  late PasswordTasks client;
  late PasswordClient password;
  late TaskSyncService sync;
  late DateTime now;
  const login = HaokePasswordCredentials(
    username: 'fixture-user',
    password: 'fixture-password',
    mode: 'userno',
  );
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    db = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    store = PlatformCredentialStore(db);
    client = PasswordTasks();
    password = PasswordClient();
    now = DateTime.utc(2026, 10, 20);
    sync = TaskSyncService(
      db,
      client: client,
      credentials: store,
      passwordLogin: password,
      clock: () => now,
    );
  });
  tearDown(() async {
    sync.close();
    await db.close();
  });
  Future<bool> connect() =>
      sync.connectHaokePassword(login, confirmSwitch: (_, _) async => true);

  test('密码连接后启用自动同步，密码只进入系统安全存储', () async {
    expect(await connect(), true);
    expect(await db.loadSetting('task_auto_sync'), 'true');
    expect(await db.loadSetting('task_haoke_password_login'), 'true');
    expect(
      jsonDecode((await store.read('haoke'))!)['passwordLogin']['password'],
      login.password,
    );
    final settings = jsonEncode(await db.database.query('app_settings'));
    expect(settings, isNot(contains(login.password)));
    expect(settings, isNot(contains(login.username)));
  });
  test('健康配对票据优先续期，同时保留密码以供以后恢复', () async {
    await connect();
    now = now.add(const Duration(minutes: 31));
    await sync.refresh();
    expect(client.renewals, 1);
    expect(password.calls, 1);
    final saved = jsonDecode((await store.read('haoke'))!);
    expect(saved['token'], 'rotated');
    expect(saved['passwordLogin']['password'], login.password);
  });
  test('票据续期接口403时允许一次已授权的密码恢复，不直接阻断自动同步', () async {
    await connect();
    client.renewalError = const PlatformRequestException(
      'ticket rejected',
      403,
    );
    now = now.add(const Duration(minutes: 31));
    await sync.refresh();
    expect(password.calls, 2);
    expect(await db.loadSetting('task_haoke_login_blocked'), isNull);
    expect(await db.loadSetting('task_haoke_needs_auth'), 'false');
    expect(
      jsonDecode((await store.read('haoke'))!)['token'],
      'password-token-2',
    );
  });
  test('重启进程后票据失效，自动使用加密保存的密码重新登录并同步', () async {
    await connect();
    sync.close();
    client = PasswordTasks()
      ..renewalError = const PlatformRequestException(
        'expired',
        401,
        false,
        true,
      );
    password = PasswordClient();
    now = now.add(const Duration(minutes: 31));
    sync = TaskSyncService(
      db,
      client: client,
      credentials: store,
      passwordLogin: password,
      backgroundTick: true,
      clock: () => now,
    );
    await sync.refresh();
    expect(password.calls, 1);
    expect(client.haokeCalls, 1);
    expect(await db.loadSetting('task_haoke_needs_auth'), 'false');
    expect(
      jsonDecode((await store.read('haoke'))!)['passwordLogin']['password'],
      login.password,
    );
  });
  test('网络失败后保留已经保存的密码和新票据，按现有有限重试恢复', () async {
    client.haoke = () async =>
        throw const PlatformRequestException('network', 503, true);
    await expectLater(connect(), throwsA(isA<PlatformRequestException>()));
    expect(await store.activeAccount('haoke'), 'a');
    expect(await db.loadSetting('task_auto_sync'), 'true');
    expect(
      jsonDecode((await store.read('haoke'))!)['passwordLogin']['password'],
      login.password,
    );
    expect(await sync.hasPendingHaokeRetry(), true);
    client.haoke = () async => batch();
    now = now.add(const Duration(minutes: 5));
    await sync.refresh();
    expect(await db.loadSetting('task_haoke_error'), '');
  });
  test('密码被拒绝或要求验证码后停止自动重登，不循环提交旧密码', () async {
    await connect();
    client.renewalError = const PlatformRequestException(
      'expired',
      401,
      false,
      true,
    );
    password.failure = const LoginFailure('userNoLogin', 603);
    now = now.add(const Duration(minutes: 31));
    await sync.refresh();
    final calls = password.calls;
    expect(await db.loadSetting('task_haoke_login_blocked'), 'true');
    now = now.add(const Duration(minutes: 31));
    await sync.refresh();
    expect(password.calls, calls);
  });
  test('账号切换可取消，拒绝后保留原账号与密码', () async {
    await connect();
    final saved = await store.read('haoke');
    password.accountId = 'b';
    expect(
      await sync.connectHaokePassword(
        login,
        confirmSwitch: (_, _) async => false,
      ),
      false,
    );
    expect(await store.read('haoke'), saved);
    expect(await store.activeAccount('haoke'), 'a');
  });
  test('切换账号后删除旧账号保存的密码，不影响新连接', () async {
    await connect();
    password.accountId = 'b';
    client.haoke = () async => batch(account: 'b');
    const other = HaokePasswordCredentials(
      username: 'other-user',
      password: 'other-password',
      mode: 'username',
    );
    expect(
      await sync.connectHaokePassword(
        other,
        confirmSwitch: (_, _) async => true,
      ),
      true,
    );
    final secrets = (await store.storage.readAll()).values.join();
    expect(secrets, isNot(contains(login.password)));
    expect(secrets, contains(other.password));
    expect(await store.activeAccount('haoke'), 'b');
  });
  test('自动重登返回不同账号时停止恢复，保留原凭据', () async {
    await connect();
    final saved = await store.read('haoke');
    client.renewalError = const PlatformRequestException(
      'expired',
      401,
      false,
      true,
    );
    password.accountId = 'b';
    now = now.add(const Duration(minutes: 31));
    await sync.refresh();
    expect(await store.read('haoke'), saved);
    expect(await db.loadSetting('task_haoke_login_blocked'), 'true');
  });
  test('密码登录网络错误保留自动恢复能力，按有限补试再次登录', () async {
    await connect();
    client.renewalError = const PlatformRequestException(
      'expired',
      401,
      false,
      true,
    );
    password.failure = const LoginFailure(
      'getRsaKey',
      'timeout',
      retryable: true,
    );
    now = now.add(const Duration(minutes: 31));
    await sync.refresh();
    expect(await sync.hasPendingHaokeRetry(), true);
    expect(await db.loadSetting('task_haoke_login_blocked'), isNull);
    password.failure = null;
    now = now.add(const Duration(minutes: 5));
    await sync.refresh();
    expect(password.calls, 3);
    expect(await db.loadSetting('task_haoke_retry_login'), isNull);
  });
  test('断开连接会清除密码，重新使用网页登录时不继续保存旧密码', () async {
    await connect();
    await sync.connectHaoke(
      const HaokeCredentials(token: 'manual', ticket: 'manual-ticket'),
      confirmSwitch: (_, _) async => true,
    );
    expect((await store.read('haoke'))!, isNot(contains(login.password)));
    expect(await db.loadSetting('task_haoke_password_login'), 'false');
    await connect();
    await sync.disconnect('haoke');
    expect(await store.read('haoke'), isNull);
    expect(await db.loadSetting('task_haoke_password_login'), isNull);
    expect(
      (await store.storage.readAll()).values.join(),
      isNot(contains(login.password)),
    );
  });
}
