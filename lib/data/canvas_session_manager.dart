import 'dart:async';

import 'package:flutter/services.dart';

class CanvasSessionException implements Exception {
  const CanvasSessionException(this.code);
  final String code;
  String get message => switch (code) {
    'login_required' || 'login_or_web_timeout' => '请打开 Canvas 自动续期设置，重新完成学校登录',
    'account_changed' || 'bearer_account_changed' => '学校账号已变化，请重新连接并确认切换',
    'permanent_expiry_requires_action' => '这枚令牌的永久期限已到，请在官方页面创建新的专用令牌',
    'wrong_test_token' ||
    'rotation_identity_or_scope_changed' => '令牌归属或权限已变化，已停止本次续期',
    'busy' => '连接维护正在进行，请稍后重试',
    'unavailable' => '当前设备暂不支持 Canvas 自动续期',
    _ => 'Canvas 自动续期暂未完成，已保存的作业和凭证保留；可稍后重试',
  };
}

class CanvasTokenOption {
  const CanvasTokenOption({
    required this.id,
    required this.purpose,
    required this.accountId,
  });
  final String id, purpose, accountId;
}

class CanvasSessionManager {
  const CanvasSessionManager();
  static const channel = MethodChannel(
    'offline_course_schedule/canvas_session',
  );
  Future<T?> _call<T>(String method, [Map<String, Object?>? arguments]) async {
    try {
      return await channel
          .invokeMethod<T>(method, arguments)
          .timeout(const Duration(seconds: 145));
    } on MissingPluginException {
      if (method == 'status' ||
          method == 'prepare' ||
          method == 'disable' ||
          method == 'clear') {
        return null;
      }
      throw const CanvasSessionException('unavailable');
    } on PlatformException catch (error) {
      throw CanvasSessionException(error.code);
    } on TimeoutException {
      throw const CanvasSessionException('login_or_web_timeout');
    }
  }

  Future<Map<Object?, Object?>> status() async =>
      await _call<Map<Object?, Object?>>('status') ?? {};
  Future<List<CanvasTokenOption>> listTokens() async {
    final value = await _call<Map<Object?, Object?>>('list');
    final account = value?['accountId']?.toString();
    final tokens = value?['tokens'];
    if (account == null || tokens is! List) {
      throw const CanvasSessionException('invalid_list');
    }
    return tokens.map((entry) {
      final row = entry as Map;
      return CanvasTokenOption(
        id: row['id'].toString(),
        purpose: row['purpose'] as String,
        accountId: account,
      );
    }).toList();
  }

  String _credential(Map<Object?, Object?> value, String account) {
    if (value['accountId']?.toString() != account ||
        value['token'] is! String ||
        (value['token'] as String).isEmpty) {
      throw const CanvasSessionException('account_changed');
    }
    return value['token'] as String;
  }

  Future<String?> prepare(String account) async {
    final value = await _call<Map<Object?, Object?>>('prepare', {
      'accountId': account,
    });
    return value == null ? null : _credential(value, account);
  }

  Future<String> configure(CanvasTokenOption token) async {
    final value = await _call<Map<Object?, Object?>>('configure', {
      'accountId': token.accountId,
      'tokenId': token.id,
      'purpose': token.purpose,
    });
    if (value == null) throw const CanvasSessionException('unavailable');
    return _credential(value, token.accountId);
  }

  Future<void> disable() async => _call<void>('disable');
  Future<void> clear() async => _call<void>('clear');
}
