import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'platform_task_client.dart' show HaokeCredentials;

class HaokePasswordCredentials {
  const HaokePasswordCredentials({
    required this.username,
    required this.password,
    required this.mode,
  });
  final String username;
  final String password;
  final String mode;

  Map<String, String> toJson() => {
    'username': username,
    'password': password,
    'mode': mode,
  };

  factory HaokePasswordCredentials.fromJson(Object? value) {
    if (value is! Map ||
        value['username'] is! String ||
        (value['username'] as String).isEmpty ||
        value['password'] is! String ||
        (value['password'] as String).isEmpty ||
        !['userno', 'username'].contains(value['mode'])) {
      throw const FormatException('好课自动登录信息不完整');
    }
    return HaokePasswordCredentials(
      username: value['username'],
      password: value['password'],
      mode: value['mode'],
    );
  }
}

String encryptHaokePassword(String password, String key) {
  final cipher = PaddedBlockCipher('AES/ECB/PKCS7')
    ..init(
      true,
      PaddedBlockCipherParameters(
        KeyParameter(base64Decode(key.split(',').first)),
        null,
      ),
    );
  return base64Encode(
    cipher.process(Uint8List.fromList(utf8.encode(password))),
  );
}

class LoginFailure implements Exception {
  const LoginFailure(
    this.phase,
    this.code, {
    this.httpStatus,
    this.retryable = false,
  });
  final String phase;
  final Object code;
  final int? httpStatus;
  final bool retryable;
}

class PasswordLoginClient {
  PasswordLoginClient({HttpClient? httpClient})
    : _http = httpClient ?? HttpClient() {
    _http.connectionTimeout = const Duration(seconds: 15);
  }
  final HttpClient _http;
  void close() => _http.close(force: true);

  String _requestId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<Map> _post(String host, String path, Map body, {String? token}) async {
    final phase = path.split('/').last;
    HttpClientRequest? request;
    try {
      return await (() async {
        request = await _http.openUrl('POST', Uri.https(host, path));
        final req = request!;
        req.followRedirects = false;
        req.headers.contentType = ContentType.json;
        req.headers.set('Accept', 'application/json');
        req.headers.set('Origin', 'https://$host');
        req.headers.set('X-Language', 'zh-CN');
        if (token != null) req.headers.set('Authorization', 'Bearer $token');
        req.write(jsonEncode({...body, 'requestId': _requestId()}));
        final response = await req.close();
        if (response.statusCode != 200) {
          throw LoginFailure(
            phase,
            response.statusCode,
            httpStatus: response.statusCode,
            retryable: [429, 502, 503, 504].contains(response.statusCode),
          );
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 65536) {
            throw LoginFailure(phase, 'response_limit');
          }
          bytes.addAll(chunk);
        }
        final value = jsonDecode(utf8.decode(bytes));
        if (value is! Map) throw LoginFailure(phase, 'invalid_response');
        if (value['code'] != 200) {
          throw LoginFailure(
            phase,
            value['code'] is int ? value['code'] : 'invalid_response',
            httpStatus: 200,
            retryable: value['code'] == 429,
          );
        }
        if (value['data'] is! Map) {
          throw LoginFailure(phase, 'invalid_response');
        }
        return value['data'] as Map;
      })().timeout(const Duration(seconds: 20));
    } on LoginFailure {
      rethrow;
    } on TimeoutException {
      throw LoginFailure(phase, 'timeout', retryable: true);
    } on HandshakeException {
      throw LoginFailure(phase, 'tls', retryable: true);
    } on SocketException {
      throw LoginFailure(phase, 'connection', retryable: true);
    } on HttpException {
      throw LoginFailure(phase, 'connection', retryable: true);
    } on FormatException {
      throw LoginFailure(phase, 'invalid_response');
    } finally {
      request?.abort();
    }
  }

  Future<({String accountId, HaokeCredentials pair})> login(
    String account,
    String password,
    String mode,
  ) async {
    if (account.isEmpty ||
        password.isEmpty ||
        !['userno', 'username'].contains(mode)) {
      throw const LoginFailure('input', 'invalid_input');
    }
    const center = 'passport.aihaoke.net';
    const school = 'tongji.aihaoke.net';
    final key = await _post(center, '/api/auth/getRsaKey', {'encType': 'aes'});
    String encrypted;
    try {
      encrypted = encryptHaokePassword(password, key['key'] as String);
    } catch (_) {
      throw const LoginFailure('encrypt', 'invalid_key');
    }
    final login = await _post(
      center,
      mode == 'userno' ? '/api/auth/userNoLogin' : '/api/auth/userNameLogin',
      {
        'autoLogin': false,
        'keyId': key['keyId'],
        'userPassword': encrypted,
        'deviceType': 'pc',
        'encType': 'aes',
        'validate': '',
        'tenantId': 88,
        if (mode == 'userno') 'userNo': account else 'userName': account,
      },
    );
    final passportToken = login['token'];
    if (passportToken is! String || passportToken.isEmpty) {
      throw const LoginFailure('login', 'missing_token');
    }
    final entry = await _post(center, '/api/auth/getTicket', {
      'deviceType': 'pc',
    }, token: passportToken);
    if (entry['data'] is! String || (entry['data'] as String).isEmpty) {
      throw const LoginFailure('getTicket', 'missing_ticket');
    }
    final entered = await _post(school, '/api/auth/loginByTicket', {
      'ticket': entry['data'],
    });
    final schoolToken = entered['token'];
    if (schoolToken is! String || schoolToken.isEmpty) {
      throw const LoginFailure('loginByTicket', 'missing_token');
    }
    final value = await _post(
      school,
      '/api/auth/queryCurrentUserInfo',
      {},
      token: schoolToken,
    );
    final user = value['userInfo'];
    if (user is! Map ||
        (user['userId'] is! String && user['userId'] is! int) ||
        '${user['userId']}'.isEmpty ||
        value['token'] is! String ||
        (value['token'] as String).isEmpty ||
        (value['token'] as String).length > 4096 ||
        value['ticket'] is! String ||
        (value['ticket'] as String).isEmpty ||
        (value['ticket'] as String).length > 4096) {
      throw const LoginFailure('queryCurrentUserInfo', 'incomplete_credential');
    }
    return (
      accountId: '${user['userId']}',
      pair: HaokeCredentials(token: value['token'], ticket: value['ticket']),
    );
  }
}
