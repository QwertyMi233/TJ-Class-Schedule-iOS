import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tj_text_recognition/tj_text_recognition.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('offline_course_schedule/text_recognition');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('图片路径传给本机识别器，中文和英文识别结果原样保留', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'recognizeFile');
      expect(call.arguments, {'path': '/tmp/课表.heic'});
      return '第1至18周\n数学 08:00-09:35\nPhysics';
    });
    expect(
      await ScreenshotTextRecognition.recognizeFile('/tmp/课表.heic'),
      '第1至18周\n数学 08:00-09:35\nPhysics',
    );
  });

  test('原生识别失败保留错误，空路径不调用原生识别器', () async {
    var called = false;
    messenger.setMockMethodCallHandler(channel, (_) async {
      called = true;
      throw PlatformException(code: 'recognition_failed');
    });
    await expectLater(
      ScreenshotTextRecognition.recognizeFile(''),
      throwsArgumentError,
    );
    expect(called, isFalse);
    await expectLater(
      ScreenshotTextRecognition.recognizeFile('/tmp/invalid.png'),
      throwsA(isA<PlatformException>()),
    );
  });
}
