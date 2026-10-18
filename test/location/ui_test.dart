import 'package:offline_course_schedule/presentation/app_theme.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/features/location/app.dart';
import 'package:offline_course_schedule/features/location/domain.dart';
import 'package:offline_course_schedule/features/location/location.dart';
import 'package:offline_course_schedule/features/location/store.dart';

class TestLocation extends LocationController {
  final bool ready;
  TestLocation({this.ready = true});
  @override
  Future<void> start({bool requestPermission = true}) async {
    active = true;
    state = ready
        ? LocationState(
            fix: Fix(31.281, 121.501, 6, DateTime.now()),
            heading: 18,
            headingAt: DateTime.now(),
            compassReliable: true,
            status: 'ready',
          )
        : const LocationState(status: 'deniedForever');
  }

  @override
  Future<void> stop() async {
    active = false;
    await Future<void>.value();
    if (mounted) state = const LocationState();
  }
}

class TestStore implements PlaceStore {
  final List<Place> items;
  final prefs = <String, String>{};
  TestStore(List<Place> initial) : items = List.of(initial);
  @override
  get database => throw UnimplementedError();
  @override
  Future<List<Place>> all() async => List.of(items);
  @override
  Future<void> delete(String id) async => items.removeWhere((p) => p.id == id);
  @override
  Future<void> insert(Place place) async => items.add(place);
  @override
  Future<void> edit(Place place) async {
    items[items.indexWhere((p) => p.id == place.id)] = place;
  }

  @override
  Future<String?> preference(String key) async => prefs[key];
  @override
  Future<void> setPreference(String key, String value) async {
    prefs[key] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  bool previewFontLoaded = false;
  setUpAll(() async {
    // 仅测试预览使用电脑字体；安装包使用手机系统字体，不打包这些字体。
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (font.existsSync()) {
      final loader = FontLoader('PreviewChinese')
        ..addFont(Future.value(ByteData.sublistView(await font.readAsBytes())));
      await loader.load();
      previewFontLoaded = true;
    }
    final root = Platform.environment['FLUTTER_ROOT'];
    if (root != null) {
      final icons = File(
        '$root/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      );
      if (icons.existsSync()) {
        final loader = FontLoader('MaterialIcons')
          ..addFont(
            Future.value(ByteData.sublistView(await icons.readAsBytes())),
          );
        await loader.load();
      }
    }
  });
  final now = DateTime(2026, 10, 14, 9, 41);
  final bike = Place(
    id: 'bike',
    name: '图书馆入口',
    note: '图书馆东门，靠近台阶',
    color: placeColors[0],
    fix: Fix(31.28175, 121.50124, 5, now),
    createdAt: now,
  );
  final entrance = Place(
    id: 'entry',
    name: '宿舍入口',
    note: '靠近便利店的门',
    color: placeColors[1],
    fix: Fix(31.29, 121.5, 8, now),
    createdAt: now,
  );
  Future<void> load(
    WidgetTester tester, {
    bool ready = true,
    List<Place>? items,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWithValue(TestStore(items ?? [bike, entrance])),
          locationProvider.overrideWith((ref) => TestLocation(ready: ready)),
        ],
        child: RepaintBoundary(
          key: ValueKey('preview'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(seedColor: accent).copyWith(
              textTheme: AppTheme.light(seedColor: accent).textTheme.apply(
                fontFamily: previewFontLoaded ? 'PreviewChinese' : null,
              ),
            ),
            home: const LocationHomePage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('preview')),
    );
    await tester.runAsync(() async {
      final picture = await boundary.toImage(pixelRatio: 2);
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      await Directory('artifacts').create(recursive: true);
      await File('artifacts/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      picture.dispose();
    });
  }

  testWidgets('定位点列表和追踪界面可操作，输出实际 Flutter 布局预览', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await load(tester);
    expect(find.text('图书馆入口'), findsOneWidget);
    expect(find.text('宿舍入口'), findsOneWidget);
    await capture(tester, 'preview-home');
    await tester.tap(find.text('图书馆入口'));
    await tester.pumpAndSettle();
    expect(find.text('米 · 直线距离'), findsOneWidget);
    expect(find.text('图书馆东门，靠近台阶'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, 'preview-tracking');
    await tester.tap(find.text('方向高亮'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<DynamicDirection>(find.byType(DynamicDirection)).style,
      DirectionStyle.highlight,
    );
    await capture(tester, 'preview-highlight');
    await tester.tap(find.text('结束寻找'));
    await tester.pumpAndSettle();
    expect(find.text('我的定位点'), findsOneWidget);
  });
  testWidgets('主界面长按取消保留两点，确认只删除被按的点', (tester) async {
    await load(tester);
    await tester.longPress(find.text('图书馆入口'));
    await tester.pumpAndSettle();
    expect(find.byType(TrackingPage), findsNothing);
    expect(find.text('删除这个定位点？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('图书馆入口'), findsOneWidget);
    await tester.longPress(find.text('图书馆入口'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('图书馆入口'), findsNothing);
    expect(find.text('宿舍入口'), findsOneWidget);
  });
  testWidgets('手机朝向变化同时更新箭头与高亮，模式跨定位点保留', (tester) async {
    await load(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LocationHomePage)),
    );
    await tester.tap(find.text('图书馆入口'));
    await tester.pumpAndSettle();
    final before = tester
        .widget<DynamicDirection>(find.byType(DynamicDirection))
        .angle;
    final locator = container.read(locationProvider.notifier);
    final originalFix = container.read(locationProvider).fix;
    locator.onEvent({'type': 'heading', 'heading': 108, 'reliable': true});
    await tester.pumpAndSettle();
    final after = tester
        .widget<DynamicDirection>(find.byType(DynamicDirection))
        .angle;
    expect(turnAngle(after, before), closeTo(-90, .001));
    expect(container.read(locationProvider).fix, originalFix);
    await tester.tap(find.text('方向高亮'));
    await tester.pumpAndSettle();
    locator.onEvent({'type': 'heading', 'heading': 198, 'reliable': true});
    await tester.pumpAndSettle();
    expect(
      turnAngle(
        tester.widget<DynamicDirection>(find.byType(DynamicDirection)).angle,
        after,
      ),
      closeTo(-90, .001),
    );
    locator.onEvent({'type': 'heading', 'heading': null, 'reliable': false});
    await tester.pumpAndSettle();
    expect(find.byType(DynamicDirection), findsNothing);
    await tester.tap(find.text('结束寻找'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('宿舍入口'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<DynamicDirection>(find.byType(DynamicDirection)).style,
      DirectionStyle.highlight,
    );
  });
  testWidgets('权限未授权时不会出现虚假的米数与方向箭头', (tester) async {
    await load(tester, ready: false);
    await tester.tap(find.text('图书馆入口'));
    await tester.pumpAndSettle();
    expect(find.text('等待定位'), findsOneWidget);
    expect(find.text('米 · 直线距离'), findsNothing);
    expect(find.text('打开设置'), findsOneWidget);
  });
  testWidgets('没有定位时不能保存，表单仍可填写', (tester) async {
    await load(tester, ready: false, items: []);
    await tester.tap(find.text('记住当前位置'));
    await tester.pumpAndSettle();
    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '保存这个位置'),
    );
    expect(save.onPressed, isNull);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
  testWidgets('窄屏大字体与长备注可滚动，无布局溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await load(
      tester,
      items: [bike.renamed('很长很长的图书馆门口位置定位点', '这是为了返回此处而记录的详细位置备注。' * 7)],
    );
    await tester.tap(find.text('很长很长的图书馆门口位置定位点'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -1200),
    );
    await tester.pumpAndSettle();
    expect(find.text('结束寻找'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
