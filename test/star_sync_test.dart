import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/star_sync_service.dart';
import 'package:offline_course_schedule/data/platform_credential_store.dart';
import 'package:offline_course_schedule/data/schedule_database.dart';
import 'package:offline_course_schedule/data/star_activity_client.dart';
import 'package:offline_course_schedule/domain/schedule_engine.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/domain/star_activity.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'star_activity_test.dart' show ticket;

class FakeStarClient extends StarActivityClient {
  String accountId = 'a';
  List<StarActivity> rows = [StarActivity.fromTicket(ticket())];
  int renewals = 0;
  int reads = 0;
  bool fail = false;
  bool expired = false;
  bool accountExpired = false;
  String? renewedAccount;
  @override
  Future<StarSession> renew(String refreshToken) async {
    renewals++;
    if (renewedAccount != null) accountId = renewedAccount!;
    return StarSession(
      accessToken: 'access-$renewals',
      refreshToken: 'refresh-$renewals',
    );
  }

  @override
  Future<String> account(String accessToken) async {
    if (accountExpired) {
      accountExpired = false;
      throw const StarRequestException('expired', needsAuth: true);
    }
    return accountId;
  }

  @override
  Future<List<StarActivity>> activities(String accessToken) async {
    reads++;
    if (expired) {
      expired = false;
      throw const StarRequestException('expired', needsAuth: true);
    }
    if (fail) throw const StarRequestException('network');
    return rows;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late ScheduleDatabase db;
  late FakeStarClient client;
  late StarSyncService sync;
  late PlatformCredentialStore credentials;
  final now = DateTime.utc(2026, 10, 20);
  final term = Term(
    id: 'current-term',
    name: '秋季',
    firstWeekMonday: DateTime(2026, 9, 7),
    totalWeeks: 20,
    periodsByWeekday: {},
  );
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    db = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    await db.replaceTermSchedule(term, []);
    client = FakeStarClient();
    credentials = PlatformCredentialStore(db);
    sync = StarSyncService(
      db,
      client: client,
      credentials: credentials,
      clock: () => now,
    );
  });
  tearDown(() async {
    sync.close();
    await db.close();
  });

  Future<void> connect() =>
      sync.connect('fixture-refresh', confirmSwitch: (_, _) async => true);

  const captured = StarSession(
    accessToken: 'fixture-access-token',
    refreshToken: 'fixture-refresh-token',
  );

  test('网页登录直接使用已有 access token，不额外轮换刷新令牌', () async {
    await sync.connectSession(captured, confirmSwitch: (_, _) async => true);
    expect(client.renewals, 0);
    expect(await credentials.read('star'), captured.encode());
    expect(await db.loadMemos(term.id), hasLength(1));
  });

  test('网页登录令牌在账号校验时过期，续期后保存新凭据并同步', () async {
    client.accountExpired = true;
    await sync.connectSession(captured, confirmSwitch: (_, _) async => true);
    expect(client.renewals, 1);
    expect(
      StarSession.decode((await credentials.read('star'))!).refreshToken,
      'refresh-1',
    );
    expect(await db.loadMemos(term.id), hasLength(1));
  });

  test('网页登录令牌在读取活动时过期，只续期一次并先保存新凭据', () async {
    client.expired = true;
    await sync.connectSession(captured, confirmSwitch: (_, _) async => true);
    expect(client.renewals, 1);
    expect(
      StarSession.decode((await credentials.read('star'))!).refreshToken,
      'refresh-1',
    );
    expect(await db.loadMemos(term.id), hasLength(1));
  });

  test('首次连接在活动读取时续期也必须复核账号，不导入其他账号活动', () async {
    client.expired = true;
    client.renewedAccount = 'b';
    await expectLater(
      sync.connectSession(captured, confirmSwitch: (_, _) async => true),
      throwsA(isA<StarRequestException>()),
    );
    expect(client.renewals, 1);
    expect(client.reads, 1);
    expect(await db.loadSetting('task_star_needs_auth'), 'true');
    expect(await db.loadMemos(term.id), isEmpty);
  });

  test('网页登录取消切换账号时不覆盖原凭据和活动', () async {
    await connect();
    final saved = await credentials.read('star');
    client.accountId = 'b';
    await expectLater(
      sync.connectSession(captured, confirmSwitch: (_, _) async => false),
      throwsA(isA<StarRequestException>()),
    );
    expect(await credentials.activeAccount('star'), 'a');
    expect(await credentials.read('star'), saved);
    expect(
      (await db.loadMemos(term.id)).single.id,
      startsWith(StarActivity.accountPrefix('a')),
    );
  });

  test('网页登录在账号和活动两处均拒绝认证时，不重复续期', () async {
    client.accountExpired = true;
    client.expired = true;
    await expectLater(
      sync.connectSession(captured, confirmSwitch: (_, _) async => true),
      throwsA(isA<StarRequestException>()),
    );
    expect(client.renewals, 1);
    expect(await db.loadSetting('task_star_needs_auth'), 'true');
    expect(await db.loadMemos(term.id), isEmpty);
  });

  test('网页登录已保存凭据但活动请求断网，重试同步可恢复', () async {
    client.fail = true;
    await expectLater(
      sync.connectSession(captured, confirmSwitch: (_, _) async => true),
      throwsA(isA<StarRequestException>()),
    );
    expect(await credentials.read('star'), captured.encode());
    expect(await db.loadSetting('star_enabled'), 'true');
    client.fail = false;
    await sync.refresh(manual: true);
    expect(await db.loadMemos(term.id), hasLength(1));
  });

  test('接入后立即写入一次性备忘录，重复同步不新增，改期更新原记录', () async {
    await db.replaceTermMemos(term.id, [
      Memo(
        id: 'manual',
        title: '自建',
        colorValue: 1,
        date: DateTime(2026, 10, 21),
        startMinutes: 60,
        endMinutes: 120,
      ),
    ]);
    await connect();
    await sync.refresh(manual: true);
    var memos = await db.loadMemos(term.id);
    expect(memos, hasLength(2));
    final id = memos.singleWhere((m) => m.source == 'star').id;
    client.rows = [StarActivity.fromTicket(ticket(hour: 20))];
    await sync.refresh(manual: true);
    memos = await db.loadMemos(term.id);
    expect(memos.singleWhere((m) => m.id == id).startMinutes, 20 * 60);
    expect(memos.singleWhere((m) => m.id == 'manual').title, '自建');
    expect(
      jsonDecode((await credentials.read('star'))!)['refreshToken'],
      'refresh-1',
    );
  });

  test('完整空快照移除未来活动，已开始活动和自建备忘录保留', () async {
    await connect();
    final old = Memo(
      id: '${StarActivity.accountPrefix('a')}old:2026-10-19',
      title: '已开始',
      source: 'star',
      colorValue: 1,
      date: DateTime(2026, 10, 19),
      startMinutes: 60,
      endMinutes: 120,
    );
    await db.replaceTermMemos(term.id, [...await db.loadMemos(term.id), old]);
    client.rows = [];
    await sync.refresh(manual: true);
    expect((await db.loadMemos(term.id)).single.id, old.id);
  });

  test('网络失败保留本地活动和已成功时间，断开只清除凭据', () async {
    await connect();
    final last = await db.loadSetting('star_last_sync');
    client.fail = true;
    await expectLater(
      sync.refresh(manual: true),
      throwsA(isA<StarRequestException>()),
    );
    expect(await db.loadMemos(term.id), hasLength(1));
    expect(await db.loadSetting('star_last_sync'), last);
    await sync.disconnect();
    expect(await credentials.read('star'), isNull);
    expect(await db.loadMemos(term.id), hasLength(1));
    expect(await db.loadSetting('star_enabled'), 'false');
  });

  test('切换账号后读取失败，重试成功才移除旧账号未来活动', () async {
    await connect();
    client.accountId = 'b';
    client.fail = true;
    await expectLater(connect(), throwsA(isA<StarRequestException>()));
    expect(
      (await db.loadMemos(term.id)).single.id,
      startsWith(StarActivity.accountPrefix('a')),
    );
    client.fail = false;
    await sync.refresh(manual: true);
    expect(
      (await db.loadMemos(term.id)).single.id,
      startsWith(StarActivity.accountPrefix('b')),
    );
    expect(await db.loadSetting('star_previous_account'), isNull);
  });

  test('access token失效只续期一次并保存轮换令牌', () async {
    await connect();
    client.expired = true;
    await sync.refresh(manual: true);
    expect(client.renewals, 2);
    expect(
      jsonDecode((await credentials.read('star'))!)['refreshToken'],
      'refresh-2',
    );
    expect(await db.loadMemos(term.id), hasLength(1));
  });

  test('自动同步有间隔，手动同步不受间隔限制，跨实例锁阻止重复续期', () async {
    await connect();
    final reads = client.reads;
    await sync.refresh();
    expect(client.reads, reads);
    await sync.refresh(manual: true);
    expect(client.reads, reads + 1);
    await db.saveSetting(
      'star_sync_lease',
      DateTime.now().microsecondsSinceEpoch.toString(),
    );
    await expectLater(
      sync.refresh(manual: true),
      throwsA(isA<StarRequestException>()),
    );
    expect(client.reads, reads + 1);
  });

  test('平台活动在节假日和学期外仍按真实日期显示', () {
    final memo = StarActivity.fromTicket(ticket()).toMemos('a').single;
    final engine = ScheduleEngine(
      term: Term(
        id: 't',
        name: 't',
        firstWeekMonday: DateTime(2026, 9, 7),
        totalWeeks: 1,
        periodsByWeekday: {},
      ),
      courses: [],
      memos: [memo],
      adjustments: [ScheduleAdjustment(date: memo.date!, isHoliday: true)],
    );
    expect(engine.getCoursesForDate(memo.date!), isEmpty);
    expect(engine.getEntriesForDate(memo.date!).single.title, '校园讲座');
  });
  test('损坏凭据进入重新登录状态，不发起活动请求', () async {
    await connect();
    final reads = client.reads;
    await credentials.save(
      'star',
      'a',
      '{"accessToken":123,"refreshToken":"bad"}',
    );
    await expectLater(
      sync.refresh(manual: true),
      throwsA(isA<StarRequestException>()),
    );
    expect(await db.loadSetting('task_star_needs_auth'), 'true');
    expect(client.reads, reads);
    expect(await db.loadMemos(term.id), hasLength(1));
  });
  test('续期后账号异常时保留原活动，不导入其他账号的列表', () async {
    await connect();
    client.accountId = 'b';
    client.expired = true;
    client.rows = [];
    await expectLater(
      sync.refresh(manual: true),
      throwsA(isA<StarRequestException>()),
    );
    expect(await db.loadSetting('task_star_needs_auth'), 'true');
    expect(await db.loadMemos(term.id), hasLength(1));
  });
}
