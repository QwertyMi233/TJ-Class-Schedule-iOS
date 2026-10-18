import 'dart:ui' as ui;
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/application/schedule_controller.dart';
import 'package:offline_course_schedule/data/schedule_database.dart';
import 'package:offline_course_schedule/presentation/schedule_background.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Path extends BackgroundImagePathController {
  _Path(this.path);
  final String? path;
  @override
  Future<String?> build() async => path;
  void setPath(String? value) => state = AsyncData(value);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  test('背景蒙层随深浅主题变化，不把浅色界面压成黑底', () {
    expect(
      scheduleBackgroundScrim(Brightness.light, .55),
      Colors.white.withValues(alpha: .55),
    );
    expect(
      scheduleBackgroundScrim(Brightness.dark, .55),
      Colors.black.withValues(alpha: .55),
    );
  });
  test('替换背景图片写入不同路径，旧文件在成功保存新设置前不被覆盖', () async {
    final dir = await Directory.systemTemp.createTemp(
      'schedule-background-store-',
    );
    addTearDown(() => dir.delete(recursive: true));
    final source = LocalBackgroundImageSource(
      supportDirectory: () async => dir,
    );
    final first = await source.store(Uint8List.fromList([1, 2, 3]));
    final second = await source.store(Uint8List.fromList([4, 5, 6]));
    expect(second, isNot(first));
    expect(await File(first).readAsBytes(), [1, 2, 3]);
    expect(await File(second).readAsBytes(), [4, 5, 6]);
  });
  test('新路径写入设置失败时保留旧图片与设置，删除未提交的新文件', () async {
    final dir = await Directory.systemTemp.createTemp(
      'schedule-background-rollback-',
    );
    addTearDown(() => dir.delete(recursive: true));
    final source = LocalBackgroundImageSource(
      supportDirectory: () async => dir,
    );
    final original = await source.store(Uint8List.fromList([1, 2, 3]));
    final db = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    await db.saveSetting('background_image_path', original);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        backgroundImageSourceProvider.overrideWithValue(source),
      ],
    );
    addTearDown(container.dispose);
    expect(await container.read(backgroundImagePathProvider.future), original);
    await db.close();
    await expectLater(
      container
          .read(backgroundImagePathProvider.notifier)
          .saveBackgroundImage(Uint8List.fromList([4, 5, 6])),
      throwsA(isA<Exception>()),
    );
    expect(container.read(backgroundImagePathProvider).valueOrNull, original);
    expect(await File(original).readAsBytes(), [1, 2, 3]);
    expect(await dir.list().length, 1);
  });

  test('模糊强度持久化并限制范围，不接受非有限数值', () async {
    final db = await ScheduleDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWith((ref) async => db)],
    );
    addTearDown(container.dispose);
    expect(await container.read(backgroundBlurProvider.future), 6);
    await container.read(backgroundBlurProvider.notifier).saveSettings(99);
    expect(await container.read(backgroundBlurProvider.future), 20);
    await container
        .read(backgroundBlurProvider.notifier)
        .saveSettings(double.nan);
    expect(
      (await container.read(backgroundBlurProvider.future)).isFinite,
      true,
    );
  });
  test('丢失或无法解码的背景不会启用半透明界面', () async {
    final dir = await Directory.systemTemp.createTemp(
      'schedule-background-invalid-',
    );
    addTearDown(() => dir.delete(recursive: true));
    final broken = File('${dir.path}/broken.png');
    await broken.writeAsString('not an image');
    for (final path in ['${dir.path}/missing.png', broken.path]) {
      final container = ProviderContainer(
        overrides: [
          backgroundImagePathProvider.overrideWith(() => _Path(path)),
        ],
      );
      try {
        expect(
          await container.read(scheduleBackgroundImageProvider.future),
          isNull,
        );
      } finally {
        container.dispose();
      }
    }
  });
  testWidgets('背景模糊不影响前景文字或按钮手势；清除后恢复完整底色', (tester) async {
    late Directory dir;
    late File file;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp(
        'schedule-background-widget-',
      );
      file = File('${dir.path}/valid.png');
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(32, 64);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await file.writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    final container = ProviderContainer(
      overrides: [
        backgroundImagePathProvider.overrideWith(() => _Path(file.path)),
      ],
    );
    addTearDown(container.dispose);
    final ready = await tester.runAsync(
      () => container.read(scheduleBackgroundImageProvider.future),
    );
    expect(ready, isNotNull);
    var taps = 0;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ScheduleBackdrop(
            child: Builder(
              builder: (context) => Scaffold(
                backgroundColor: Colors.transparent,
                body: TextButton(
                  onPressed: () => taps++,
                  child: Text(
                    ScheduleSurface.of(context).hasImage ? '背景已就绪' : '纯色背景',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('背景已就绪'), findsOneWidget);
    final filter = find.byType(ImageFiltered);
    expect(filter, findsOneWidget);
    expect(
      find.descendant(of: filter, matching: find.byType(Text)),
      findsNothing,
    );
    await tester.tap(find.text('背景已就绪'));
    expect(taps, 1);
    (container.read(backgroundImagePathProvider.notifier) as _Path).setPath(
      null,
    );
    await tester.pumpAndSettle();
    expect(find.text('纯色背景'), findsOneWidget);
    expect(
      tester.widget<ScheduleSurface>(find.byType(ScheduleSurface)).cardOpacity,
      1,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
