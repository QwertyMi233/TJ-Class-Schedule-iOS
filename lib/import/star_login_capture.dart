import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../data/star_activity_client.dart';

bool canReadStarCredentials(String? url) {
  final uri = Uri.tryParse(url ?? '');
  return uri?.scheme == 'https' &&
      uri?.host == 'star.tongji.edu.cn' &&
      uri?.port == 443 &&
      uri?.userInfo.isEmpty == true;
}

StarSession? decodeStarLoginCapture(Object raw) {
  try {
    Object? value = raw;
    // Android WebView 可能把 JavaScript 返回的 JSON 再编码为字符串。
    for (var i = 0; i < 2 && value is String; i++) {
      if (value.isEmpty) return null;
      value = jsonDecode(value);
    }
    if (value is! Map || value['origin'] != 'https://star.tongji.edu.cn') {
      return null;
    }
    final snapshots = value['snapshots'];
    if (snapshots is! List) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final raw in snapshots) {
      if (raw is! String || raw.length > 2 * 1024 * 1024) continue;
      try {
        final cache = _decodeStarCache(raw);
        if (cache is! Map ||
            (cache['expire'] is num && cache['expire'] < now)) {
          continue;
        }
        final records = cache['value'];
        if (records is! Map) continue;
        Object? token(String key) {
          final record = records[key];
          if (record is! Map ||
              (record['time'] is num && record['time'] < now)) {
            return null;
          }
          return record['value'];
        }

        final session = _starTokenPair(
          token('ACCESS_TOKEN__'),
          token('REFRESH_TOKEN__'),
        );
        if (session != null) return session;
      } catch (_) {
        // 损坏、过期或尚未完整写入的快照不影响读取其他版本的缓存。
      }
    }
    return null;
  } on FormatException {
    return null;
  }
}

StarSession? _starTokenPair(Object? access, Object? refresh) {
  final token = RegExp(r'^[A-Za-z0-9._~-]{16,4096}$');
  if (access is! String ||
      refresh is! String ||
      !token.hasMatch(access) ||
      !token.hasMatch(refresh)) {
    return null;
  }
  return StarSession(accessToken: access, refreshToken: refresh);
}

Object? _decodeStarCache(String raw) {
  if (raw.trimLeft().startsWith('{')) return jsonDecode(raw);
  // 与官网公开前端一致：UTF-8 固定 key/iv、AES-CTR、PKCS7 填充。
  final cipher = PaddedBlockCipher('AES/CTR/PKCS7')
    ..init(
      false,
      PaddedBlockCipherParameters(
        ParametersWithIV(
          KeyParameter(Uint8List.fromList(utf8.encode('_11111000001111@'))),
          Uint8List.fromList(utf8.encode('@11111000001111_')),
        ),
        null,
      ),
    );
  return jsonDecode(utf8.decode(cipher.process(base64Decode(raw))));
}

/// 只读卓越星自身的缓存快照，不访问表单、Cookie 或其他网站的存储。
const starCredentialCaptureScript = r'''(() => {
  if (location.origin !== 'https://star.tongji.edu.cn') return '';
  try {
    const snapshots = [];
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i);
      if (!key || !key.startsWith('TONGJI_EXCELLENCE_STAR_APP__PRODUCTION__') ||
          !key.endsWith('__COMMON__LOCAL__KEY__')) continue;
      const stored = localStorage.getItem(key);
      if (stored && stored.length <= 2 * 1024 * 1024) snapshots.push(stored);
    }
    return snapshots.length ? JSON.stringify({ origin: location.origin, snapshots }) : '';
  } catch (_) {}
  return '';
})()''';
