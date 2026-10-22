import 'dart:io';
import 'dart:ui' as graphics;

import 'package:flutter/cupertino.dart' as c;
import 'package:flutter/material.dart' as m;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/platform/ios_icons.dart';
import 'package:offline_course_schedule/platform/platform_ui.dart' as ui;
import 'package:offline_course_schedule/presentation/app_theme.dart';
import 'package:offline_course_schedule/presentation/tongji_timetable_page.dart';

void main() {
  var previewFont = false;
  setUpAll(() async {
    final icons = FontLoader('packages/cupertino_icons/CupertinoIcons')
      ..addFont(rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'));
    await icons.load();
    // Preview font is read from the build host, never bundled into the app.
    final chinese = File('/System/Library/Fonts/PingFang.ttc');
    if (chinese.existsSync()) {
      final font = FontLoader('ToolbarPreview')
        ..addFont(Future.value(ByteData.sublistView(await chinese.readAsBytes())));
      await font.load();
      previewFont = true;
    }
  });

  test('unmapped toolbar glyphs retain their actual icon', () {
    const original = m.Icon(m.Icons.sports_esports_outlined);
    final converted = iosIcon(original) as m.Icon;
    expect(converted.icon, original.icon);
    expect(converted.icon, isNot(c.CupertinoIcons.ellipsis));
  });

  testWidgets('Tongji mode, reload and logout remain distinct and actionable', (tester) async {
    final calls = <String>[];
    var desktop = true;
    await tester.pumpWidget(m.MaterialApp(
      home: m.StatefulBuilder(builder: (context, setState) => m.Scaffold(
        appBar: ui.AppBar(
          title: const m.Text('从同济1系统导入'),
          actions: [TongjiTimetableActions(
            desktopMode: desktop,
            onToggleMode: () {
              calls.add('mode');
              setState(() => desktop = !desktop);
            },
            onReload: () => calls.add('reload'),
            onLogout: () => calls.add('logout'),
          )],
        ),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.byIcon(c.CupertinoIcons.ellipsis), findsNothing);
    await tester.tap(find.byIcon(c.CupertinoIcons.desktopcomputer));
    await tester.pumpAndSettle();
    expect(find.byIcon(c.CupertinoIcons.device_phone_portrait), findsOneWidget);
    await tester.tap(find.byIcon(c.CupertinoIcons.arrow_clockwise));
    await tester.tap(find.byIcon(c.CupertinoIcons.square_arrow_right));
    expect(calls, ['mode', 'reload', 'logout']);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(m.TargetPlatform.iOS));

  final layouts = [
    for (final size in const [m.Size(320, 568), m.Size(390, 844), m.Size(430, 932),
      m.Size(852, 393), m.Size(744, 1133), m.Size(1024, 768)]) (size, 1.0),
    (const m.Size(320, 568), 2.0),
    (const m.Size(430, 932), 2.0),
  ];
  for (final (size, scale) in layouts) {
    for (final dark in [false, true]) {
      testWidgets('flat toolbar and compact buttons fit $size scale $scale dark $dark', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final boundary = m.GlobalKey();
        var theme = dark ? AppTheme.dark(seedColor: m.Colors.blue) : AppTheme.light(seedColor: m.Colors.blue);
        if (previewFont) {
          theme = theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'ToolbarPreview'),
            cupertinoOverrideTheme: c.CupertinoThemeData(
              brightness: theme.brightness,
              textTheme: const c.CupertinoTextThemeData(
                textStyle: m.TextStyle(fontFamily: 'ToolbarPreview', fontSize: 16),
                navTitleTextStyle: m.TextStyle(fontFamily: 'ToolbarPreview', fontSize: 17, fontWeight: m.FontWeight.w600),
              ),
            ),
          );
        }
        await tester.pumpWidget(m.MaterialApp(
          theme: theme,
          builder: (context, child) => m.MediaQuery(
            data: m.MediaQuery.of(context).copyWith(textScaler: m.TextScaler.linear(scale)),
            child: m.RepaintBoundary(key: boundary, child: child!),
          ),
          home: m.Scaffold(
            appBar: ui.AppBar(
              leading: ui.IconButton(onPressed: () {}, icon: const m.Icon(m.Icons.chevron_left)),
              title: const m.Text('从同济1系统导入'),
              actions: [TongjiTimetableActions(desktopMode: true, onToggleMode: () {}, onReload: () {}, onLogout: () {})],
            ),
            body: m.ListView(
              padding: const m.EdgeInsets.all(16),
              children: [
                const m.Text('按键布局检查'),
                const m.SizedBox(height: 16),
                ui.FilledButton.icon(onPressed: () {}, icon: const m.Icon(m.Icons.table_view_rounded), label: const m.Text('读取当前课表')),
              ],
            ),
            floatingActionButton: m.SizedBox(
              width: size.width - 32,
              child: m.Row(mainAxisAlignment: m.MainAxisAlignment.spaceBetween, children: [
                ui.FloatingActionButton.extended(heroTag: 'week', onPressed: () {}, icon: const m.Icon(m.Icons.grid_view_rounded), label: const m.Text('整周课表')),
                ui.FloatingActionButton.extended(heroTag: 'add', onPressed: () {}, icon: const m.Icon(m.Icons.add_rounded), label: const m.Text('添加课程')),
              ]),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final glyph in [c.CupertinoIcons.desktopcomputer, c.CupertinoIcons.arrow_clockwise, c.CupertinoIcons.square_arrow_right]) {
          final button = find.ancestor(of: find.byIcon(glyph), matching: find.byType(c.CupertinoButton));
          expect(tester.getSize(button), const m.Size(44, 44));
          expect(tester.getSize(find.byIcon(glyph)), const m.Size(20, 20));
          final rect = tester.getRect(button);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width));
        }
        for (final label in ['整周课表', '添加课程']) {
          final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
          final required = paragraph.getDryLayout(m.BoxConstraints(maxWidth: paragraph.size.width));
          expect(paragraph.size.height + 0.000001, greaterThanOrEqualTo(required.height));
        }
        final buttons = find.byType(ui.FloatingActionButton);
        expect(buttons, findsNWidgets(2));
        if (scale == 1) {
          expect(tester.getSize(buttons.first).height, 48);
          expect(tester.getSize(buttons.last).height, 48);
          expect(tester.getSize(buttons.first).width, lessThanOrEqualTo(150));
        }
        expect(tester.getRect(buttons.first).right + 16, lessThanOrEqualTo(tester.getRect(buttons.last).left + 0.000001));
        if (size.width == 390 && scale == 1) {
          final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final picture = await render.toImage(pixelRatio: 2);
            final data = await picture.toByteData(format: graphics.ImageByteFormat.png);
            await Directory('artifacts/ios-toolbar').create(recursive: true);
            await File('artifacts/ios-toolbar/${dark ? 'dark' : 'light'}.png').writeAsBytes(data!.buffer.asUint8List());
            picture.dispose();
          });
        }
      }, variant: TargetPlatformVariant.only(m.TargetPlatform.iOS));
    }
  }
}
