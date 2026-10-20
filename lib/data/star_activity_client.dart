import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/star_activity.dart';

class StarRequestException implements Exception {
  const StarRequestException(this.message, {this.needsAuth = false});
  final String message;
  final bool needsAuth;
  @override
  String toString() => message;
}

class StarSession {
  const StarSession({
    required this.accessToken,
    required this.refreshToken,
    this.expiresTime,
  });
  final String accessToken;
  final String refreshToken;
  final int? expiresTime;

  String encode() => jsonEncode({
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresTime': expiresTime,
  });

  factory StarSession.decode(String value) {
    final data = jsonDecode(value);
    if (data is! Map ||
        data['accessToken'] is! String ||
        (data['accessToken'] as String).isEmpty ||
        data['refreshToken'] is! String ||
        (data['refreshToken'] as String).isEmpty ||
        (data['expiresTime'] != null && data['expiresTime'] is! int)) {
      throw const FormatException('卓越星凭据格式无效');
    }
    return StarSession(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
      expiresTime: data['expiresTime'] as int?,
    );
  }
}

/// 仅调用登录续期和查询接口；不包含报名、打卡或签到操作。
class StarActivityClient {
  StarActivityClient({HttpClient? httpClient})
    : _http = httpClient ?? HttpClient() {
    _http.connectionTimeout = const Duration(seconds: 15);
  }
  final HttpClient _http;
  void close() => _http.close(force: true);

  Future<StarSession> renew(String refreshToken) async {
    final data = await _request(
      'POST',
      '/system/auth/refresh-token',
      query: {'refreshToken': refreshToken},
    );
    if (data is! Map ||
        data['accessToken'] is! String ||
        (data['accessToken'] as String).isEmpty) {
      throw const StarRequestException('卓越星续期响应不完整，请重新连接');
    }
    return StarSession(
      accessToken: data['accessToken'] as String,
      refreshToken:
          data['refreshToken'] is String &&
              (data['refreshToken'] as String).isNotEmpty
          ? data['refreshToken'] as String
          : refreshToken,
      expiresTime: data['expiresTime'] is num
          ? (data['expiresTime'] as num).toInt()
          : null,
    );
  }

  Future<String> account(String accessToken) async {
    final data = await _request(
      'GET',
      '/system/member/get',
      token: accessToken,
    );
    final id = data is Map ? '${data['id'] ?? data['username'] ?? ''}' : '';
    if (id.isEmpty) throw const StarRequestException('卓越星账号信息不完整');
    return id;
  }

  Future<List<StarActivity>> activities(String accessToken) async {
    final tickets = <Map<String, dynamic>>[];
    int? expected;
    for (var page = 1; page <= 100; page++) {
      final data = await _request(
        'GET',
        '/activity/ticket/list',
        token: accessToken,
        query: {'pageNo': '$page', 'pageSize': '50'},
      );
      if (data is! Map || data['list'] is! List) {
        throw const StarRequestException('卓越星报名列表不完整，本地安排已保留');
      }
      final rows = data['list'] as List;
      final total = data['total'] is num
          ? (data['total'] as num).toInt()
          : null;
      expected ??= total;
      if (expected != total ||
          rows.length > 50 ||
          rows.any((row) => row is! Map<String, dynamic>)) {
        throw const StarRequestException('卓越星报名列表发生变化，请重试');
      }
      tickets.addAll(rows.cast<Map<String, dynamic>>());
      if (rows.length < 50 || tickets.length == expected) {
        if (expected != null && tickets.length != expected) {
          throw const StarRequestException('卓越星报名分页未读取完整，本地安排已保留');
        }
        final result = <StarActivity>[];
        final ids = <String>{};
        for (var ticket in tickets) {
          try {
            final status = ticket['status'];
            if (status == 1 || status == 3) continue;
            if (status != 0 && status != 2) {
              throw const FormatException('未知的报名审核状态');
            }
            final act = ticket['activity'];
            final sch = ticket['schedule'];
            if ((act is Map && act['deleted'] == true) ||
                (sch is Map && sch['deleted'] == true)) {
              continue;
            }
            // 部分入场券只带摘要，先查询报名详情补齐场次。
            try {
              StarActivity.fromTicket(ticket);
            } on FormatException {
              if (ticket['id'] != null) {
                final detail = await _request(
                  'GET',
                  '/activity/enroll/get',
                  token: accessToken,
                  query: {'id': '${ticket['id']}'},
                );
                if (detail is Map<String, dynamic>) {
                  ticket = {...ticket, ...detail};
                }
              }
            }
            final activity = StarActivity.fromTicket(ticket);
            if (!ids.add(activity.ticketId)) {
              throw const FormatException('分页包含重复入场券');
            }
            result.add(activity);
          } on FormatException {
            throw const StarRequestException('部分活动缺少名称或起止时间，本地安排已保留');
          }
        }
        return result;
      }
    }
    throw const StarRequestException('卓越星报名分页超过读取上限，本地安排已保留');
  }

  Future<Object?> _request(
    String method,
    String path, {
    String? token,
    Map<String, String>? query,
  }) async {
    try {
      final uri = Uri.https('star.tongji.edu.cn', '/api/app-api$path', query);
      final request = await _http
          .openUrl(method, uri)
          .timeout(const Duration(seconds: 20));
      request.followRedirects = false;
      request.headers.set('Accept', 'application/json');
      request.headers.set('platform', 'h5');
      request.headers.set('X-Request-Origin', 'https://star.tongji.edu.cn');
      if (token != null) request.headers.set('Authorization', 'Bearer $token');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const StarRequestException('卓越星登录已失效，请重新连接', needsAuth: true);
      }
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw const StarRequestException('卓越星服务暂时不可用，请稍后重试');
      }
      final text = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(text);
      if (data is! Map) throw const FormatException();
      final message = '${data['msg'] ?? ''}';
      if (data['code'] == 401 ||
          message.contains('无效的刷新令牌') ||
          message.contains('令牌已过期') ||
          message.contains('账号未登录')) {
        throw const StarRequestException('卓越星登录已失效，请重新连接', needsAuth: true);
      }
      if (data['code'] != 0) {
        // 不显示原始服务端文本：可能回显请求中的 refreshToken。
        throw const StarRequestException('卓越星请求未成功，本地安排已保留');
      }
      return data['data'];
    } on StarRequestException {
      rethrow;
    } on FormatException {
      throw const StarRequestException('卓越星响应格式无法识别，本地安排已保留');
    } catch (_) {
      throw const StarRequestException('无法连接卓越星，请检查网络后重试');
    }
  }
}
