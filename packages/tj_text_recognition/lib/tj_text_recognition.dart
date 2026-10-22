import 'package:flutter/services.dart';

/// Both native implementations process a local image without uploading it.
abstract final class ScreenshotTextRecognition {
  static const _channel = MethodChannel(
    'offline_course_schedule/text_recognition',
  );

  static Future<String> recognizeFile(String path) async {
    if (path.isEmpty) throw ArgumentError.value(path, 'path');
    final text = await _channel.invokeMethod<String>('recognizeFile', {
      'path': path,
    });
    if (text == null) throw const FormatException('无法读取图片文字');
    return text;
  }
}
