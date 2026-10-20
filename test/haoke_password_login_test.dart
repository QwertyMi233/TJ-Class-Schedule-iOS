import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/data/haoke_password_login.dart';

import 'platform_task_client_test.dart' show FakeHttpClient, Reply;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('密码加密与已验证的 Android 和官网向量一致', () {
    final key = base64Encode(List<int>.generate(32, (i) => i));
    expect(
      encryptHaokePassword('test-password', key),
      'ppVfAUQs2UpG5vwPWbA+HQ==',
    );
    expect(
      encryptHaokePassword('test-password', '$key,unused'),
      'ppVfAUQs2UpG5vwPWbA+HQ==',
    );
  });
  test('密码仅提交账号中心，入站票据换取课程站凭证后读取完整配对', () async {
    final http = FakeHttpClient((request) {
      switch (request.uri.path) {
        case '/api/auth/getRsaKey':
          return Reply({
            'code': 200,
            'data': {
              'key': base64Encode(List<int>.generate(32, (i) => i)),
              'keyId': 'key-id',
            },
          });
        case '/api/auth/userNoLogin':
          expect(request.uri.host, 'passport.aihaoke.net');
          final body = jsonDecode(request.body.toString());
          expect(body['userPassword'], 'ppVfAUQs2UpG5vwPWbA+HQ==');
          expect(body['tenantId'], 88);
          return Reply({
            'code': 200,
            'data': {'token': 'passport-token'},
          });
        case '/api/auth/getTicket':
          expect(
            request.headers.value('Authorization'),
            'Bearer passport-token',
          );
          return Reply({
            'code': 200,
            'data': {'data': 'entry-ticket'},
          });
        case '/api/auth/loginByTicket':
          expect(request.uri.host, 'tongji.aihaoke.net');
          expect(jsonDecode(request.body.toString())['ticket'], 'entry-ticket');
          return Reply({
            'code': 200,
            'data': {'token': 'platform-token'},
          });
        case '/api/auth/queryCurrentUserInfo':
          expect(
            request.headers.value('Authorization'),
            'Bearer platform-token',
          );
          return Reply({
            'code': 200,
            'data': {
              'token': 'fresh-token',
              'ticket': 'fresh-ticket',
              'userInfo': {'userId': 7},
            },
          });
        default:
          throw StateError('unexpected request');
      }
    });
    final client = PasswordLoginClient(httpClient: http);
    addTearDown(client.close);
    final pair = await client.login(
      'fixture-account',
      'test-password',
      'userno',
    );
    expect(pair.accountId, '7');
    expect(pair.pair.token, 'fresh-token');
    expect(pair.pair.ticket, 'fresh-ticket');
    expect(http.requests, hasLength(5));
    expect(
      http.requests.where((r) => r.body.toString().contains('test-password')),
      isEmpty,
    );
  });
  test('HTTP拒绝和验证码业务拒绝不混为网络超时，且不重复尝试密码', () async {
    for (final entry in [(403, 200), (200, 603), (200, 500)]) {
      final http = FakeHttpClient(
        (_) => Reply({'code': entry.$2}, status: entry.$1),
      );
      final client = PasswordLoginClient(httpClient: http);
      await expectLater(
        client.login('fixture', 'password', 'userno'),
        throwsA(isA<LoginFailure>().having((e) => e.retryable, 'retry', false)),
      );
      expect(http.requests, hasLength(1));
      client.close();
    }
  });
}
