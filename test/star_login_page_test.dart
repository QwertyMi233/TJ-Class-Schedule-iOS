import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/application/star_sync_service.dart';
import 'package:offline_course_schedule/data/platform_credential_store.dart';
import 'package:offline_course_schedule/data/schedule_database.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/presentation/star_connection_page.dart';
import 'package:offline_course_schedule/presentation/star_login_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'star_sync_test.dart' show FakeStarClient;

const _origin = 'https://star.tongji.edu.cn';
final _pair = jsonEncode({
  'origin': _origin,
  'snapshots': [
    (jsonDecode(File('test/fixtures/star-login-cache.json').readAsStringSync())
        as Map)['encrypted'],
  ],
});

class _WebPlatform extends WebViewPlatform {
  late _WebController controller;
  late _Navigation navigation;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => controller = _WebController(params);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => navigation = _Navigation(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _WebWidget(params);
}

class _WebWidget extends PlatformWebViewWidget {
  _WebWidget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class _Navigation extends PlatformNavigationDelegate {
  _Navigation(super.params) : super.implementation();
  late PageEventCallback started;
  late PageEventCallback finished;
  late NavigationRequestCallback requested;
  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {
    requested = callback;
  }

  @override
  Future<void> setOnPageStarted(PageEventCallback callback) async {
    started = callback;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    finished = callback;
  }

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {}
}

class _WebController extends PlatformWebViewController {
  _WebController(super.params) : super.implementation();
  String? url;
  Object result = '';
  int reads = 0;
  Future<Object> Function()? read;
  Future<String?> Function()? current;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}
  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    url = params.uri.toString();
  }

  @override
  Future<void> reload() async {}
  @override
  Future<String?> currentUrl() async =>
      current == null ? url : await current!();
  @override
  Future<Object> runJavaScriptReturningResult(String script) async {
    reads++;
    return read == null ? result : await read!();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  late ScheduleDatabase db;
  late FakeStarClient client;
  late _WebPlatform web;
  WebViewPlatform? previousPlatform;

  setUp(() async {
    previousPlatform = WebViewPlatform.instance;
    web = _WebPlatform();
    WebViewPlatform.instance = web;
    FlutterSecureStorage.setMockInitialValues({});
    db = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    await db.replaceTermSchedule(
      Term(
        id: currentTermId,
        name: '测试学期',
        firstWeekMonday: DateTime(2026, 10, 19),
        totalWeeks: 2,
        periodsByWeekday: {},
      ),
      [],
    );
    client = FakeStarClient();
  });
  tearDown(() async {
    if (previousPlatform != null) WebViewPlatform.instance = previousPlatform;
    client.close();
    await db.close();
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) async => db),
          starSyncServiceProvider.overrideWith(
            (ref) async => StarSyncService(
              db,
              client: client,
              clock: () => DateTime.utc(2026, 10, 20),
            ),
          ),
        ],
        child: const MaterialApp(home: StarConnectionPage()),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    expect(find.text('官方网页登录'), findsOneWidget);
    await tester.tap(find.text('官方网页登录'));
    await tester.pumpAndSettle();
    expect(find.byType(StarLoginPage), findsOneWidget);
    expect(web.controller.url, '$_origin/app/pages/login/login');
  }

  Future<void> waitForConnection(WidgetTester tester) async {
    for (var i = 0; i < 100 && find.text('已连接卓越星').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('已连接卓越星'), findsOneWidget);
  }

  testWidgets('官方登录后自动保存两个令牌并同步，取消登录保留手动入口', (tester) async {
    await open(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      expect(await PlatformCredentialStore(db).read('star'), isNull);
    });
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('手动令牌（备用）'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Refresh Token'), findsOneWidget);
    await tester.tap(find.text('官方网页登录'));
    await tester.pumpAndSettle();
    final fixture =
        jsonDecode(
              File('test/fixtures/star-login-cache.json').readAsStringSync(),
            )
            as Map;
    web.controller.result = jsonEncode({
      'origin': _origin,
      'snapshots': [fixture['encrypted']],
    });
    web.navigation.finished(web.controller.url!);
    await waitForConnection(tester);
    await tester.runAsync(() async {
      final saved = jsonDecode(
        (await PlatformCredentialStore(db).read('star'))!,
      );
      expect(saved['accessToken'], 'fixture-access-token');
      expect(saved['refreshToken'], 'fixture-refresh-token');
      expect(await db.loadMemos(currentTermId), hasLength(1));
      expect(await db.loadSetting('star_enabled'), 'true');
      final settings = jsonEncode(await db.database.query('app_settings'));
      expect(settings, isNot(contains('fixture-access-token')));
      expect(settings, isNot(contains('fixture-refresh-token')));
    });
    expect(client.renewals, 0);
    expect(find.textContaining('fixture-access-token'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('统一认证页不执行读取脚本，返回卓越星后才读取', (tester) async {
    await open(tester);
    web.controller.url = 'https://iam.tongji.edu.cn/login';
    web.controller.result = _pair;
    web.navigation.finished(web.controller.url!);
    await tester.pump(const Duration(milliseconds: 800));
    expect(web.controller.reads, 0);
    await tester.runAsync(() async {
      expect(await PlatformCredentialStore(db).read('star'), isNull);
    });
    expect(
      await web.navigation.requested(
        const NavigationRequest(
          url: 'http://star.tongji.edu.cn/',
          isMainFrame: true,
        ),
      ),
      NavigationDecision.prevent,
    );
    web.controller.url = '$_origin/app/';
    web.navigation.finished(web.controller.url!);
    await waitForConnection(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('读取中跳转页面会丢弃旧结果，即使跳回同一域名', (tester) async {
    await open(tester);
    final pending = Completer<Object>();
    web.controller.read = () => pending.future;
    web.navigation.finished(web.controller.url!);
    await tester.pump();
    web.navigation.started('https://iam.tongji.edu.cn/login');
    web.navigation.started('$_origin/app/');
    pending.complete(_pair);
    await tester.pump();
    expect(find.byType(StarLoginPage), findsOneWidget);
    await tester.runAsync(() async {
      expect(await PlatformCredentialStore(db).read('star'), isNull);
    });
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('退到后台时不消费正在读取的令牌，恢复后重新读取', (tester) async {
    await open(tester);
    final pending = Completer<Object>();
    web.controller.read = () => pending.future;
    web.navigation.finished(web.controller.url!);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    pending.complete(_pair);
    await tester.pump();
    expect(find.byType(StarLoginPage), findsOneWidget);
    await tester.runAsync(() async {
      expect(await PlatformCredentialStore(db).read('star'), isNull);
    });
    web.controller.read = null;
    web.controller.result = _pair;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await waitForConnection(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('关闭登录页面的动画期间，迟到结果不会同步或再次返回', (tester) async {
    await open(tester);
    final pending = Completer<Object>();
    web.controller.read = () => pending.future;
    web.navigation.finished(web.controller.url!);
    await tester.pump();
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 100));
    pending.complete(_pair);
    await tester.pumpAndSettle();
    expect(find.byType(StarConnectionPage), findsOneWidget);
    await tester.runAsync(() async {
      expect(await PlatformCredentialStore(db).read('star'), isNull);
    });
    expect(client.reads, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
