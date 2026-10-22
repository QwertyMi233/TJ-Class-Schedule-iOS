// 背景分层、深浅蒙层和仅模糊图片的思路参考 HITable（MIT）。
// 来源与许可见 assets/LICENSE_HITable.txt、BACKGROUND_TEST_0.3.0.md。
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import '../platform/platform_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/schedule_controller.dart';

Color scheduleBackgroundScrim(Brightness brightness, double opacity) =>
    (brightness == Brightness.dark ? Colors.black : Colors.white).withValues(
      alpha: opacity.isFinite ? opacity.clamp(0.0, 1.0) : .55,
    );

/// 只在图片切换时验证和预解码一次，卡片不各自读取磁盘或判断文件存在。
final scheduleBackgroundImageProvider = FutureProvider<ImageProvider<Object>?>((
  ref,
) async {
  final ready = Completer<bool>();
  ref.onDispose(() {
    if (!ready.isCompleted) ready.complete(false);
  });
  final path = await ref.watch(backgroundImagePathProvider.future);
  if (path == null || !await File(path).exists() || ready.isCompleted) {
    return null;
  }
  final ImageProvider<Object> image = ResizeImage(
    FileImage(File(path)),
    width: 1440,
    height: 2560,
    policy: ResizeImagePolicy.fit,
    allowUpscaling: false,
  );
  final stream = image.resolve(ImageConfiguration.empty);
  final listener = ImageStreamListener(
    (info, _) {
      info.dispose();
      if (!ready.isCompleted) ready.complete(true);
    },
    onError: (Object error, StackTrace? stack) {
      if (!ready.isCompleted) ready.complete(false);
    },
  );
  stream.addListener(listener);
  try {
    return await ready.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () => false,
        )
        ? image
        : null;
  } finally {
    stream.removeListener(listener);
  }
});

/// 前景只调整底色透明度，文字、按钮和手势不经过模糊或整层 Opacity。
class ScheduleSurface extends InheritedWidget {
  const ScheduleSurface({
    required this.hasImage,
    required this.cardOpacity,
    required super.child,
    super.key,
  });
  final bool hasImage;
  final double cardOpacity;
  static ScheduleSurface of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ScheduleSurface>() ??
      const ScheduleSurface(hasImage: false, cardOpacity: 1, child: SizedBox());
  Color headerColor(BuildContext context) => hasImage
      ? Theme.of(context).colorScheme.surface.withValues(alpha: .78)
      : Theme.of(context).scaffoldBackgroundColor;
  @override
  bool updateShouldNotify(ScheduleSurface oldWidget) =>
      oldWidget.hasImage != hasImage || oldWidget.cardOpacity != cardOpacity;
}

class ScheduleBackdrop extends ConsumerWidget {
  const ScheduleBackdrop({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(backgroundImagePathProvider).valueOrNull;
    final resolved = ref.watch(scheduleBackgroundImageProvider).valueOrNull;
    final image = path == null ? null : resolved;
    final theme = Theme.of(context);
    final blur =
        ref.watch(backgroundBlurProvider).valueOrNull ??
        BackgroundBlurController.defaultBlur;
    final opacity =
        ref.watch(backgroundOverlayOpacityProvider).valueOrNull ??
        BackgroundOverlayOpacityController.defaultOpacity;
    final cardOpacity =
        ref.watch(cardOpacityProvider).valueOrNull ??
        CardOpacityController.defaultOpacity;
    return ScheduleSurface(
      hasImage: image != null,
      cardOpacity: image == null ? 1 : cardOpacity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            key: const ValueKey('schedule-background-base'),
            color: theme.scaffoldBackgroundColor,
          ),
          if (image != null)
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: ClipRect(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        scheduleBlurredImage(
                          Image(
                            image: image,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            errorBuilder: (_, _, _) => ColoredBox(
                              color: theme.scaffoldBackgroundColor,
                            ),
                          ),
                          blur,
                        ),
                        ColoredBox(
                          key: const ValueKey('schedule-background-scrim'),
                          color: scheduleBackgroundScrim(
                            theme.brightness,
                            opacity,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

Widget scheduleBlurredImage(Widget image, double blur) => blur <= 0
    ? image
    : ClipRect(
        child: Transform.scale(
          scale: 1 + blur / 100,
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: blur,
              sigmaY: blur,
              tileMode: TileMode.clamp,
            ),
            child: image,
          ),
        ),
      );
