import 'package:flutter/cupertino.dart' as c;
import 'package:flutter/material.dart' as m;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:offline_course_schedule/platform/platform_ui.dart' as ui;
import 'package:offline_course_schedule/presentation/app_theme.dart';
import 'package:offline_course_schedule/presentation/widget_status_page.dart';

void main() {
  testWidgets(
    'missing App Group is explained instead of reporting a successful sync',
    (tester) async {
      const channel = MethodChannel('offline_course_schedule/widget');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => {
          'containerAvailable': false,
          'configuredGroup': 'group.test',
          'resolvedGroup': '',
          'courseCount': 0,
          'taskCount': 0,
          'coursesUpdated': 0,
          'tasksUpdated': 0,
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          child: m.MaterialApp(
            theme: AppTheme.light(seedColor: m.Colors.blue),
            home: const WidgetStatusPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('小组件共享权限未授权'), findsOneWidget);
      expect(find.textContaining('当前签名没有给主应用和小组件授权'), findsOneWidget);
      expect(find.text('共享容器已连接'), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(m.TargetPlatform.iOS),
  );
  testWidgets('iOS uses system typography, Cupertino input and menu actions', (
    tester,
  ) async {
    final theme = AppTheme.light(seedColor: m.Colors.blue);
    expect(
      theme.textTheme.bodyMedium!.fontFamily,
      const c.CupertinoThemeData().textTheme.textStyle.fontFamily,
    );
    var selected = '';
    await tester.pumpWidget(
      m.MaterialApp(
        theme: theme,
        home: m.Scaffold(
          appBar: ui.AppBar(
            title: const m.Text('测试学期'),
            actions: [
              ui.PopupMenuButton<String>(
                onSelected: (value) => selected = value,
                itemBuilder: (_) => const [
                  m.PopupMenuItem(value: 'widgets', child: m.Text('小组件同步')),
                ],
              ),
            ],
          ),
          body: const ui.TextField(
            decoration: m.InputDecoration(labelText: '课程名称'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(c.CupertinoNavigationBar), findsOneWidget);
    expect(find.byType(c.CupertinoTextField), findsOneWidget);
    expect(find.byType(m.PopupMenuButton<String>), findsNothing);
    await tester.tap(find.byIcon(c.CupertinoIcons.ellipsis));
    await tester.pumpAndSettle();
    expect(find.byType(c.CupertinoActionSheet), findsOneWidget);
    await tester.tap(find.text('小组件同步'));
    await tester.pumpAndSettle();
    expect(selected, 'widgets');
  }, variant: TargetPlatformVariant.only(m.TargetPlatform.iOS));

  for (final size in const [
    m.Size(320, 568),
    m.Size(430, 932),
    m.Size(852, 393),
    m.Size(744, 1133),
  ]) {
    testWidgets('iOS navigation, segments and capsule actions fit $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        m.MaterialApp(
          theme: AppTheme.dark(seedColor: m.Colors.blue),
          home: m.DefaultTabController(
            length: 2,
            child: m.Scaffold(
              appBar: ui.AppBar(
                title: const m.Text('大一上'),
                bottom: const ui.TabBar(
                  tabs: [
                    m.Tab(text: '今日'),
                    m.Tab(text: '本周'),
                  ],
                ),
                actions: [
                  ui.IconButton(
                    tooltip: '作业',
                    icon: const m.Icon(m.Icons.assignment_outlined),
                    onPressed: () {},
                  ),
                  ui.PopupMenuButton<String>(
                    itemBuilder: (_) => const [
                      m.PopupMenuItem(value: 'settings', child: m.Text('外观设置')),
                    ],
                  ),
                ],
              ),
              body: const m.TabBarView(
                children: [m.Text('今日课程'), m.Text('本周课程')],
              ),
              floatingActionButton: m.SizedBox(
                width: size.width - 32,
                child: m.Row(
                  mainAxisAlignment: m.MainAxisAlignment.spaceBetween,
                  children: [
                    ui.FloatingActionButton.extended(
                      heroTag: 'week',
                      onPressed: () {},
                      icon: const m.Icon(m.Icons.grid_view_rounded),
                      label: const m.Text('整周课表'),
                    ),
                    ui.FloatingActionButton.extended(
                      heroTag: 'add',
                      onPressed: () {},
                      icon: const m.Icon(m.Icons.add),
                      label: const m.Text('添加课程'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('整周课表'), findsOneWidget);
      expect(find.byType(m.FloatingActionButton), findsNothing);
      await tester.tap(find.text('本周'));
      await tester.pumpAndSettle();
      expect(find.text('本周课程'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(m.TargetPlatform.iOS));
  }
}
