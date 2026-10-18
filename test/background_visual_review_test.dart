import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/data/schedule_database.dart';
import 'package:offline_course_schedule/domain/schedule_models.dart';
import 'package:offline_course_schedule/presentation/app_theme.dart';
import 'package:offline_course_schedule/presentation/full_timetable_page.dart';
import 'package:offline_course_schedule/presentation/home_page.dart';
import 'package:offline_course_schedule/presentation/schedule_background.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 生成实际组件树的审阅图，并覆盖带背景的页面导航、点按和主题切换。
/// 字体仅在本机审阅时加载系统字体，不打包或分发字体文件。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  for (final dark in [false, true]) {
    testWidgets('带背景的${dark ? '深色' : '浅色'}课表与整周页面保持清晰、可操作', (tester) async {
      final oldShadows = debugDisableShadows;
      debugDisableShadows = false;
      try {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late Directory dir;
        late File background;
        late ScheduleDatabase db;
        var hasFont = false;
        await tester.runAsync(() async {
          dir = await Directory.systemTemp.createTemp(
            'schedule-background-review-',
          );
          background = File('${dir.path}/review.png');
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          const bounds = Rect.fromLTWH(0, 0, 390, 844);
          canvas.drawRect(
            bounds,
            Paint()
              ..shader = const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF163E59),
                  Color(0xFF75A8A9),
                  Color(0xFFF1BD9B),
                ],
              ).createShader(bounds),
          );
          for (var i = 0; i < 18; i++) {
            canvas.drawCircle(
              Offset((i * 83 % 390).toDouble(), (i * 131 % 844).toDouble()),
              52,
              Paint()
                ..color = (i.isEven ? Colors.white : Colors.black).withValues(
                  alpha: .17,
                ),
            );
          }
          final picture = recorder.endRecording();
          final image = await picture.toImage(390, 844);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await background.writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
          picture.dispose();
          final font = File(
            '${Platform.environment['WINDIR'] ?? '/nonexistent'}/Fonts/msyh.ttc',
          );
          if (await font.exists()) {
            final loader = FontLoader('BackgroundReviewFont')
              ..addFont(
                font.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
              );
            await loader.load();
            hasFont = true;
          }
          final icons = File(
            '${Platform.environment['FLUTTER_ROOT'] ?? '${Directory.current.path}/work/flutter-sdk'}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
          );
          if (await icons.exists()) {
            final loader = FontLoader('MaterialIcons')
              ..addFont(
                icons.readAsBytes().then(
                  (bytes) => ByteData.sublistView(bytes),
                ),
              );
            await loader.load();
          }
          db = await ScheduleDatabase.open(
            factory: databaseFactoryFfi,
            path: inMemoryDatabasePath,
          );
          await db.saveSetting('background_image_path', background.path);
          await db.saveSetting('card_opacity', '.78');
        });
        addTearDown(() => dir.deleteSync(recursive: true));
        addTearDown(db.close);
        final today = DateTime(2026, 10, 12);
        final data = _fixture(today);
        final container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWith((ref) async => db),
            scheduleControllerProvider.overrideWith(() => _Schedule(data)),
            selectedDateProvider.overrideWith((ref) => today),
            clockProvider.overrideWith((ref) => Stream.value(today)),
          ],
        );
        addTearDown(container.dispose);
        await tester.runAsync(
          () => container.read(scheduleBackgroundImageProvider.future),
        );
        const seed = Color(0xFF607D8B);
        var theme = dark
            ? AppTheme.dark(seedColor: seed)
            : AppTheme.light(seedColor: seed);
        if (hasFont) {
          theme = theme.copyWith(
            textTheme: theme.textTheme.apply(
              fontFamily: 'BackgroundReviewFont',
            ),
          );
        }
        final boundary = GlobalKey();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(1.15)),
                child: RepaintBoundary(key: boundary, child: child!),
              ),
              home: const HomePage(),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('高等数学'), findsOneWidget);
        final footer = tester.getRect(find.text('Powered by Algernon'));
        for (final button in tester.widgetList<FloatingActionButton>(
          find.byType(FloatingActionButton),
        )) {
          expect(tester.getRect(find.byWidget(button)).overlaps(footer), false);
        }
        expect(
          tester.widget<ScheduleSurface>(find.byType(ScheduleSurface)).hasImage,
          true,
        );
        expect(
          find.descendant(
            of: find.byType(ImageFiltered),
            matching: find.byType(Text),
          ),
          findsNothing,
        );
        await _snapshot(
          tester,
          boundary,
          'preview-background-${dark ? 'dark' : 'light'}.png',
        );
        await tester.tap(find.text('整周课表'));
        await tester.pumpAndSettle();
        expect(find.byType(FullTimetablePage), findsOneWidget);
        final gridContext = tester.element(find.byType(FullTimetablePage));
        expect(ScheduleSurface.of(gridContext).hasImage, true);
        final gridScaffold = tester.widget<Scaffold>(
          find.descendant(
            of: find.byType(FullTimetablePage),
            matching: find.byType(Scaffold),
          ),
        );
        expect(gridScaffold.backgroundColor, Colors.transparent);
        expect(
          find.byKey(const ValueKey('schedule-background-scrim')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await _snapshot(
          tester,
          boundary,
          'preview-background-week-${dark ? 'dark' : 'light'}.png',
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('高等数学'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      } finally {
        debugDisableShadows = oldShadows;
      }
    });
  }
}

Future<void> _snapshot(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('artifacts').create(recursive: true);
    await File('artifacts/$name').writeAsBytes(png!.buffer.asUint8List());
    image.dispose();
  });
}

class _Schedule extends ScheduleController {
  _Schedule(this.data);
  final ScheduleData data;
  @override
  Future<ScheduleData> build() async => data;
}

ScheduleData _fixture(DateTime monday) => ScheduleData(
  term: Term(
    id: currentTermId,
    name: '我的课表',
    firstWeekMonday: monday,
    totalWeeks: 16,
    periodsByWeekday: {
      for (var day = 1; day <= 7; day++)
        day: [
          const LessonPeriod(number: 1, startMinutes: 480, endMinutes: 530),
          const LessonPeriod(number: 2, startMinutes: 540, endMinutes: 590),
          const LessonPeriod(number: 3, startMinutes: 600, endMinutes: 650),
          const LessonPeriod(number: 4, startMinutes: 660, endMinutes: 710),
        ],
    },
  ),
  courses: [
    for (var i = 0; i < 3; i++)
      Course(
        id: 'c$i',
        name: ['高等数学', '大学物理', '英语写作'][i],
        teacher: '张老师',
        colorValue: [0xFF7D9DCE, 0xFF7FB69D, 0xFFD0B36C][i],
        sessions: [
          CourseSession(
            id: 's$i',
            weekday: i == 2 ? 3 : 1,
            startPeriod: i == 1 ? 3 : 1,
            endPeriod: i == 1 ? 4 : 2,
            weekRule: WeekRule(startWeek: 1, endWeek: 16, type: WeekType.every),
            location: '教学楼 A101',
          ),
        ],
      ),
  ],
);
