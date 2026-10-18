import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/data/canvas_session_manager.dart';
import 'package:offline_course_schedule/presentation/canvas_session_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('进入设置不轮换；必须读取、选择并同意后才允许连接', (tester) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      CanvasSessionManager.channel,
      (call) async {
        calls.add(call.method);
        if (call.method == 'status') return {'enabled': false};
        if (call.method == 'list') {
          return {
            'accountId': '42',
            'tokens': [
              {'id': '7', 'purpose': '课表专用'},
            ],
          };
        }
        throw PlatformException(code: 'unexpected_mutation');
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        CanvasSessionManager.channel,
        null,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: CanvasSessionPage(confirmSwitch: (_, _) async => false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, ['status']);
    FilledButton connect() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '连接并开启自动同步'),
    );
    expect(connect().onPressed, isNull);
    await tester.tap(find.text('2. 读取可选令牌'));
    await tester.pumpAndSettle();
    expect(calls, ['status', 'list']);
    expect(connect().onPressed, isNull);
    await tester.ensureVisible(
      find.byType(DropdownButtonFormField<CanvasTokenOption>),
    );
    await tester.tap(find.byType(DropdownButtonFormField<CanvasTokenOption>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课表专用').last);
    await tester.pumpAndSettle();
    expect(connect().onPressed, isNull);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(connect().onPressed, isNotNull);
    expect(calls, ['status', 'list']);
  });
}
