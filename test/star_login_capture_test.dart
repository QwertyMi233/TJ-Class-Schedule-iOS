import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_course_schedule/import/star_login_capture.dart';

void main() {
  final fixture =
      jsonDecode(File('test/fixtures/star-login-cache.json').readAsStringSync())
          as Map;
  final pair = {
    'origin': 'https://star.tongji.edu.cn',
    'accessToken': 'fixture-access-token',
    'refreshToken': 'fixture-refresh-token',
  };
  test('兼容 WebView 直接字符串与二次 JSON 编码，完整读取两个令牌', () {
    final raw = jsonEncode({
      'origin': pair['origin'],
      'snapshots': [fixture['encrypted']],
    });
    for (final value in [raw, jsonEncode(raw)]) {
      final session = decodeStarLoginCapture(value)!;
      expect(session.accessToken, pair['accessToken']);
      expect(session.refreshToken, pair['refreshToken']);
    }
  });
  test('读取官网 AES-CTR 加密且带 PKCS7 填充的真实结构缓存', () {
    for (final snapshot in [
      jsonEncode(fixture['valid']),
      fixture['encrypted'],
    ]) {
      final raw = jsonEncode({
        'origin': pair['origin'],
        'snapshots': [snapshot],
      });
      for (final result in [raw, jsonEncode(raw)]) {
        final session = decodeStarLoginCapture(result);
        expect(session?.accessToken, pair['accessToken']);
        expect(session?.refreshToken, pair['refreshToken']);
      }
    }
  });
  test('过期、损坏或部分写入的加密快照不接入，不拼接不同快照', () {
    final partial = {
      'value': {
        'ACCESS_TOKEN__': {'value': pair['accessToken']},
      },
    };
    final other = {
      'value': {
        'REFRESH_TOKEN__': {'value': pair['refreshToken']},
      },
    };
    for (final snapshots in [
      [fixture['expiredEncrypted']],
      ['not-ciphertext'],
      [jsonEncode(partial), jsonEncode(other)],
      [
        jsonEncode({
          'value': {
            'ACCESS_TOKEN__': {'value': pair['accessToken'], 'time': 1},
            'REFRESH_TOKEN__': {'value': pair['refreshToken']},
          },
        }),
      ],
    ]) {
      expect(
        decodeStarLoginCapture(
          jsonEncode({'origin': pair['origin'], 'snapshots': snapshots}),
        ),
        isNull,
      );
    }
  });
  test('跳过旧版本的损坏快照后仍能读取当前有效加密快照', () {
    expect(
      decodeStarLoginCapture(
        jsonEncode({
          'origin': pair['origin'],
          'snapshots': ['broken-json', fixture['encrypted']],
        }),
      )?.refreshToken,
      pair['refreshToken'],
    );
  });
  test('其他域名、缺失令牌和坏消息不会接入', () {
    for (final value in [
      '',
      'bad-json',
      jsonEncode({'origin': pair['origin']}),
      jsonEncode({...pair, 'origin': 'https://iam.tongji.edu.cn'}),
      jsonEncode({...pair, 'refreshToken': ''}),
    ]) {
      expect(decodeStarLoginCapture(value), isNull);
    }
  });
  test('只在卓越星 HTTPS 默认端口读取，统一认证跳转不读取', () {
    expect(canReadStarCredentials('https://star.tongji.edu.cn/app/'), isTrue);
    for (final url in [
      null,
      'http://star.tongji.edu.cn/app/',
      'https://star.tongji.edu.cn:444/',
      'https://star.tongji.edu.cn.evil.org/',
      'https://iam.tongji.edu.cn/',
      'https://user@star.tongji.edu.cn/',
    ]) {
      expect(canReadStarCredentials(url), isFalse);
    }
  });
}
