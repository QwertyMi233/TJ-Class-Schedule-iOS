import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/application/task_sync_controller.dart';
import 'package:offline_course_schedule/data/haoke_password_login.dart';
import 'package:offline_course_schedule/data/schedule_database.dart';
import 'package:offline_course_schedule/presentation/haoke_password_page.dart';
import 'package:offline_course_schedule/presentation/task_connections_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FormSync extends TaskSyncService {
  FormSync(super.database);
  int calls = 0;
  bool accept = true;
  HaokePasswordCredentials? saved;
  @override
  Future<bool> connectHaokePassword(
    HaokePasswordCredentials login, {
    required Future<bool> Function(String oldAccount, String newAccount)
    confirmSwitch,
  }) async {
    calls++;
    saved = login;
    return accept;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var previewFontLoaded = false;
  setUpAll(() async {
    sqfliteFfiInit();
    final windows = Platform.environment['WINDIR'];
    if (windows != null) {
      final font = File('$windows/Fonts/msyh.ttc');
      if (font.existsSync()) {
        await (FontLoader('ReviewChinese')..addFont(
              Future.value(ByteData.sublistView(await font.readAsBytes())),
            ))
            .load();
        previewFontLoaded = true;
      }
    }
    final configFile = File('.dart_tool/package_config.json').absolute;
    final config = jsonDecode(configFile.readAsStringSync()) as Map;
    final flutter =
        (config['packages'] as List).singleWhere((p) => p['name'] == 'flutter')
            as Map;
    final flutterUri = configFile.uri.resolve('${flutter['rootUri']}/');
    final directory = Directory.fromUri(
      flutterUri.resolve('../../bin/cache/artifacts/material_fonts/'),
    );
    if (directory.existsSync()) {
      for (final file in directory.listSync().whereType<File>()) {
        if (file.path.toLowerCase().endsWith('materialicons-regular.otf')) {
          await (FontLoader('MaterialIcons')..addFont(
                Future.value(ByteData.sublistView(await file.readAsBytes())),
              ))
              .load();
        }
      }
    }
  });
  late ScheduleDatabase db;
  late FormSync sync;
  setUp(() async {
    db = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    sync = FormSync(db);
  });
  tearDown(() async {
    sync.close();
    await db.close();
  });

  Future<void> open(
    WidgetTester tester, {
    GlobalKey? boundary,
    bool largeText = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) async => db),
          taskSyncServiceProvider.overrideWith((ref) async => sync),
        ],
        child: RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              fontFamily: previewFontLoaded ? 'ReviewChinese' : null,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(largeText ? 1.8 : 1)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HaokePasswordPage(
                        confirmSwitch: (_, _) async => true,
                      ),
                    ),
                  ),
                  child: const Text('密码登录'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('密码登录'));
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).at(0), 'fixture-user');
    await tester.enterText(find.byType(TextField).at(1), 'fixture-password');
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, GlobalKey boundary, String name) =>
      tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final frame = await render.toImage(pixelRatio: 1);
        final png = await frame.toByteData(format: ui.ImageByteFormat.png);
        await Directory('artifacts/review').create(recursive: true);
        await File(
          'artifacts/review/$name.png',
        ).writeAsBytes(png!.buffer.asUint8List());
        frame.dispose();
      });

  testWidgets('保存需要本机加密同意，未同意不提交密码', (tester) async {
    await open(tester);
    await fill(tester);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).obscureText,
      true,
    );
    await tester.ensureVisible(find.text('保存并启用自动同步'));
    await tester.tap(find.text('保存并启用自动同步'));
    await tester.pumpAndSettle();
    expect(sync.calls, 0);
    expect(find.text('请填写账号密码，并勾选本机加密保存'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('确认保存后只提交一次并返回，表单不留下密码文本', (tester) async {
    await open(tester);
    await fill(tester);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.ensureVisible(find.text('保存并启用自动同步'));
    await tester.tap(find.text('保存并启用自动同步'));
    await settle(tester);
    expect(sync.calls, 1);
    expect(sync.saved?.username, 'fixture-user');
    expect(find.byType(HaokePasswordPage), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('取消账号切换时保留表单并给出明确反馈', (tester) async {
    sync.accept = false;
    await open(tester);
    await fill(tester);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.ensureVisible(find.text('保存并启用自动同步'));
    await tester.tap(find.text('保存并启用自动同步'));
    await settle(tester);
    expect(find.text('已取消账号切换，原连接保留'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('320 窄屏大字号下表单与按钮可滚动且不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    await open(tester, boundary: boundary, largeText: true);
    await tester.scrollUntilVisible(
      find.text('保存并启用自动同步'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await capture(tester, boundary, 'haoke-password-320');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('连接页保留单一密码入口，网页登录与断开放在更多菜单', (tester) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await db.saveSetting('task_haoke_account', 'a');
      await db.saveSetting('task_haoke_password_login', 'true');
    });
    final boundary = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) async => db),
          taskSyncServiceProvider.overrideWith((ref) async => sync),
        ],
        child: RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              fontFamily: previewFontLoaded ? 'ReviewChinese' : null,
            ),
            home: const TaskConnectionsPage(),
          ),
        ),
      ),
    );
    await settle(tester);
    expect(find.text('账号密码自动同步'), findsOneWidget);
    expect(find.text('已连接 · 密码自动登录'), findsOneWidget);
    expect(find.text('网页登录（备用）'), findsNothing);
    await tester.ensureVisible(find.byTooltip('更多连接操作'));
    await tester.tap(find.byTooltip('更多连接操作'));
    await tester.pumpAndSettle();
    expect(find.text('网页登录（备用）'), findsOneWidget);
    expect(find.text('断开连接'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await capture(tester, boundary, 'platform-connections-320');
    await tester.tap(find.text('账号密码自动同步'));
    await tester.pumpAndSettle();
    expect(find.byType(HaokePasswordPage), findsOneWidget);
    expect(sync.calls, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
