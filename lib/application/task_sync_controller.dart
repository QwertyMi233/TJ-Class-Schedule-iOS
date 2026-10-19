import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/platform_credential_store.dart';
import '../data/canvas_session_manager.dart';
import '../data/platform_task_client.dart';
import '../data/schedule_database.dart';
import '../data/task_repository.dart';
import 'schedule_controller.dart';
import 'task_state.dart';
import '../notifications/notification_service.dart';
import '../notifications/task_sync_notifications.dart';

final taskSyncServiceProvider = FutureProvider<TaskSyncService>((ref) async {
  final database = await ref.watch(databaseProvider.future);
  var alive = true;
  final notifier = TaskSyncNotifications(
    database,
    ref.read(notificationServiceProvider),
  );
  final service = TaskSyncService(
    database,
    onAutomaticUpdate: notifier.updated,
    onAuthRequired: notifier.authRequired,
    onChanged: () {
      if (alive) ref.read(taskRevisionProvider.notifier).state++;
    },
  );
  ref.onDispose(() => alive = false);
  ref.onDispose(service.close);
  return service;
});

class TaskSyncService {
  TaskSyncService(
    this.database, {
    PlatformTaskClient? client,
    PlatformCredentialStore? credentials,
    CanvasSessionManager? canvasSession,
    this.backgroundTick = false,
    DateTime Function()? clock,
    this.onChanged,
    this.onAutomaticUpdate,
    this.onAuthRequired,
  }) : _clock = clock ?? DateTime.now,
       client = client ?? PlatformTaskClient(),
       credentials = credentials ?? PlatformCredentialStore(database),
       canvasSession = canvasSession ?? const CanvasSessionManager(),
       repository = TaskRepository(database.database);

  final void Function()? onChanged;
  final Future<void> Function(String platform, int count)? onAutomaticUpdate;
  final Future<void> Function(String platform)? onAuthRequired;

  final ScheduleDatabase database;
  final PlatformTaskClient client;
  final PlatformCredentialStore credentials;
  final CanvasSessionManager canvasSession;
  final bool backgroundTick;
  final DateTime Function() _clock;
  final TaskRepository repository;
  Future<Map<String, String>>? _running;
  bool _changing = false;
  String? _leaseOwner;

  // 登录维护与作业读取分别保留补试额度，进程重启后仍然有效。
  // 每轮正常检查最多补试两次；不会无限请求或反复轮换健康票据。
  static const haokeRetryDelay = Duration(minutes: 5);
  Future<Map<String, dynamic>?> _haokeRetry(String kind) async {
    try {
      final value = jsonDecode(
        await database.loadSetting('task_haoke_retry_$kind') ?? 'null',
      );
      if (value is Map<String, dynamic> &&
          value['failures'] is int &&
          value['failures'] >= 1 &&
          value['failures'] <= 3 &&
          DateTime.tryParse('${value['nextAt']}') != null) {
        return value;
      }
    } catch (_) {}
    return null;
  }

  Future<bool> hasPendingHaokeRetry() async {
    if (await database.loadSetting('task_auto_sync') != 'true' ||
        await database.loadSetting('task_haoke_login_blocked') == 'true' ||
        await credentials.activeAccount('haoke') == null) {
      return false;
    }
    for (final kind in ['login', 'read']) {
      final retry = await _haokeRetry(kind);
      if (retry != null && retry['failures'] < 3) return true;
    }
    return false;
  }

  String _haokeAttemptKey(String kind) =>
      kind == 'login' ? 'task_haoke_login_attempt' : 'task_haoke_attempt';

  Future<bool> _haokeDue(String kind, Duration interval) async {
    final retry = await _haokeRetry(kind);
    if (retry != null && retry['failures'] < 3) {
      return !_clock().isBefore(DateTime.parse(retry['nextAt']));
    }
    final last = DateTime.tryParse(
      await database.loadSetting(_haokeAttemptKey(kind)) ?? '',
    );
    return last == null || _clock().difference(last) >= interval;
  }

  Future<void> _beginHaokeAttempt(String kind, {bool manual = false}) async {
    final retry = await _haokeRetry(kind);
    if (manual || retry == null || retry['failures'] >= 3) {
      await database.deleteSetting('task_haoke_retry_$kind');
    }
    await database.saveSetting(
      _haokeAttemptKey(kind),
      _clock().toIso8601String(),
    );
  }

  Future<void> _recordHaokeFailure(
    String kind,
    PlatformRequestException error, {
    bool awaitingLogin = false,
  }) async {
    final key = kind == 'login'
        ? 'task_haoke_session_error'
        : 'task_haoke_error';
    final time = _clock();
    var message = error.requiresReauth ? '请重新登录好课' : '暂时无法更新，稍后再试';
    if (error.retryable || awaitingLogin) {
      final previous = await _haokeRetry(kind);
      final failures = ((previous?['failures'] as int?) ?? 0) + 1;
      await database.saveSetting(
        'task_haoke_retry_$kind',
        jsonEncode({
          'failures': failures.clamp(1, 3),
          'nextAt': time.add(haokeRetryDelay).toIso8601String(),
        }),
      );
      message = failures < 3 ? '网络不稳定，稍后自动重试' : '网络不稳定，稍后再试';
    } else {
      await database.deleteSetting('task_haoke_retry_$kind');
    }
    await database.saveSetting(key, message);
    await database.saveSetting('${key}_at', time.toIso8601String());
  }

  Future<bool> _takeLease() async {
    final now = DateTime.now();
    final owner = now.microsecondsSinceEpoch.toString();
    final claimed = await database.database.transaction((txn) async {
      final rows = await txn.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: ['task_sync_lease'],
      );
      if (rows.isNotEmpty) {
        final previous = int.tryParse(rows.single['value'] as String);
        if (previous != null &&
            now.difference(DateTime.fromMicrosecondsSinceEpoch(previous)) <
                const Duration(minutes: 5)) {
          return false;
        }
      }
      await txn.rawInsert(
        'INSERT OR REPLACE INTO app_settings (key,value) VALUES (?,?)',
        ['task_sync_lease', owner],
      );
      return true;
    });
    if (claimed) _leaseOwner = owner;
    return claimed;
  }

  Future<void> _releaseLease() async {
    final owner = _leaseOwner;
    if (owner == null) return;
    await database.database.delete(
      'app_settings',
      where: 'key = ? AND value = ?',
      whereArgs: ['task_sync_lease', owner],
    );
    _leaseOwner = null;
  }

  void _checkIdle() {
    if (_running != null || _changing) throw StateError('同步正在进行，请稍后操作连接');
  }

  Future<void> _claimCanvas({bool manual = false}) async {
    await database.database.transaction((txn) async {
      final rows = await txn.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: ['task_canvas_attempt'],
      );
      final last = rows.isEmpty
          ? null
          : DateTime.tryParse(rows.single['value'] as String);
      final now = DateTime.now();
      if (!manual &&
          last != null &&
          now.difference(last) < const Duration(minutes: 30)) {
        final minutes = (30 - now.difference(last).inSeconds / 60).ceil();
        throw PlatformRequestException('Canvas 自动同步将在 $minutes 分钟后刷新；可随时手动刷新');
      }
      await txn.rawInsert(
        'INSERT OR REPLACE INTO app_settings (key,value) VALUES (?,?)',
        ['task_canvas_attempt', now.toIso8601String()],
      );
    });
  }

  void close() => client.close();

  Future<bool> connectCanvas(
    String token, {
    required Future<bool> Function(String oldAccount, String newAccount)
    confirmSwitch,
  }) async {
    _checkIdle();
    _changing = true;
    try {
      if (!await _takeLease()) throw StateError('后台同步正在进行，请稍后操作连接');
      await _claimCanvas(manual: true);
      final batch = await client.collectCanvas(token);
      final old =
          await credentials.activeAccount('canvas') ??
          await database.loadSetting('task_canvas_last_account');
      if (old != null &&
          old != batch.accountId &&
          !await confirmSwitch(old, batch.accountId)) {
        return false;
      }
      await canvasSession.disable();
      await credentials.save('canvas', batch.accountId, token);
      await _saveBatch('canvas', batch);
      return true;
    } finally {
      await _releaseLease();
      _changing = false;
    }
  }

  Future<bool> connectCanvasSession(
    CanvasTokenOption option, {
    required Future<bool> Function(String oldAccount, String newAccount)
    confirmSwitch,
  }) async {
    _checkIdle();
    _changing = true;
    try {
      if (!await _takeLease()) throw StateError('后台同步正在进行，请稍后操作连接');
      final old =
          await credentials.activeAccount('canvas') ??
          await database.loadSetting('task_canvas_last_account');
      if (old != null &&
          old != option.accountId &&
          !await confirmSwitch(old, option.accountId)) {
        return false;
      }
      final token = await canvasSession.configure(option);
      // 原生层已验证账号并先安全保存；这里也先保存新值，防止后续读取失败丢票。
      await credentials.save('canvas', option.accountId, token);
      await database.saveSetting('task_canvas_session_error', '');
      await _claimCanvas(manual: true);
      final batch = await client.collectCanvas(token);
      if (batch.accountId != option.accountId) {
        throw const PlatformRequestException('平台账号已变化，请重新连接', 401, false, true);
      }
      await _saveBatch('canvas', batch);
      return true;
    } finally {
      await _releaseLease();
      _changing = false;
    }
  }

  Future<bool> connectHaoke(
    HaokeCredentials pair, {
    required Future<bool> Function(String oldAccount, String newAccount)
    confirmSwitch,
  }) async {
    _checkIdle();
    _changing = true;
    try {
      if (!await _takeLease()) throw StateError('后台同步正在进行，请稍后操作连接');
      final batch = await client.collectHaoke(pair.token);
      final old =
          await credentials.activeAccount('haoke') ??
          await database.loadSetting('task_haoke_last_account');
      if (old != null &&
          old != batch.accountId &&
          !await confirmSwitch(old, batch.accountId)) {
        return false;
      }
      await credentials.save('haoke', batch.accountId, _encodePair(pair));
      await credentials.clearHaokeCandidate(batch.accountId);
      await database.deleteSetting('task_haoke_login_blocked');
      await database.deleteSetting('task_haoke_session_error');
      await database.deleteSetting('task_haoke_session_error_at');
      await database.deleteSetting('task_haoke_retry_login');
      await database.deleteSetting('task_haoke_retry_read');
      await database.saveSetting(
        'task_haoke_login_attempt',
        DateTime.now().toIso8601String(),
      );
      await _saveBatch('haoke', batch);
      return true;
    } finally {
      await _releaseLease();
      _changing = false;
    }
  }

  Future<void> disconnect(String platform) async {
    _checkIdle();
    _changing = true;
    try {
      if (!await _takeLease()) throw StateError('后台同步正在进行，请稍后操作连接');
      if (platform == 'canvas') await canvasSession.clear();
      await credentials.remove(platform);
      if (platform == 'haoke') {
        for (final suffix in [
          'login_blocked',
          'session_error',
          'login_attempt',
          'login_success',
          'retry_login',
          'retry_read',
          'session_error_at',
          'error_at',
          'login_diagnostic',
          'read_diagnostic',
        ]) {
          await database.deleteSetting('task_haoke_$suffix');
        }
      }
      onChanged?.call();
    } finally {
      await _releaseLease();
      _changing = false;
    }
  }

  Future<Map<String, String>> refresh({bool manual = false}) =>
      _running ??= _refresh(manual: manual).whenComplete(() {
        _running = null;
        onChanged?.call();
      });

  Future<Map<String, String>> _refresh({required bool manual}) async {
    if (_changing) return {};
    if (!await _takeLease()) return manual ? {'同步': '后台同步正在进行，稍后重试即可'} : {};
    try {
      return await _collect(manual: manual);
    } finally {
      await _releaseLease();
    }
  }

  Future<Map<String, String>> _collect({required bool manual}) async {
    final results = <String, String>{};
    if (_changing) return results;
    if (!manual && await database.loadSetting('task_auto_sync') != 'true') {
      return results;
    }
    await Future.wait(
      ['canvas', 'haoke'].map((platform) async {
        final active = await credentials.activeAccount(platform);
        var secret = await credentials.read(platform);
        if (active == null || secret == null) return;
        var haokeLoginAttempted = false;
        if (platform == 'canvas') {
          try {
            final next = await canvasSession.prepare(active);
            if (next != null) {
              await credentials.save('canvas', active, next);
              secret = next;
              await database.saveSetting('task_canvas_session_error', '');
              await database.saveSetting('task_canvas_needs_auth', 'false');
              await database.deleteSetting('task_canvas_auth_notified');
            }
          } on CanvasSessionException catch (error) {
            // Cookie过期不等于Bearer已经失效；仍按原流程验证保存的凭证。
            await database.saveSetting(
              'task_canvas_session_error',
              error.message,
            );
          }
        }
        if (platform == 'haoke' && await _haokeLoginDue(manual: manual)) {
          haokeLoginAttempted = true;
          try {
            secret = _encodePair(
              await _maintainHaoke(
                active,
                _decodePair(secret!),
                manual: manual,
              ),
            );
          } on PlatformRequestException catch (error) {
            await _recordHaokeLoginError(error);
          } catch (_) {
            await _recordHaokeFailure(
              'login',
              const PlatformRequestException('登录维护未完成'),
            );
          }
        }
        if (!manual &&
            await database.loadSetting('task_${platform}_needs_auth') ==
                'true') {
          results[platform] = '需要重新登录';
          await _notifyAuth(platform);
          return;
        }
        try {
          PlatformTaskBatch batch;
          if (platform == 'canvas') {
            await _claimCanvas(manual: manual);
            batch = await client.collectCanvas(secret!);
          } else {
            if (!manual &&
                !await _haokeDue(
                  'read',
                  Duration(minutes: backgroundTick ? 30 : 1),
                )) {
              return;
            }
            await _beginHaokeAttempt('read', manual: manual);
            var pair = _decodePair(secret!);
            try {
              batch = await client.collectHaoke(pair.token);
            } on PlatformRequestException catch (error) {
              if (error.statusCode != 401 ||
                  pair.ticket.isEmpty ||
                  haokeLoginAttempted ||
                  (!manual &&
                      await database.loadSetting('task_haoke_login_blocked') ==
                          'true')) {
                rethrow;
              }
              haokeLoginAttempted = true;
              try {
                pair = await _maintainHaoke(active, pair, manual: manual);
              } on PlatformRequestException catch (loginError) {
                await _recordHaokeLoginError(loginError);
                rethrow;
              }
              batch = await client.collectHaoke(pair.token);
            }
          }
          if (batch.accountId != active) {
            results[platform] = '平台账号已变化，请重新连接并确认切换';
            await database.saveSetting('task_${platform}_needs_auth', 'true');
            await database.saveSetting(
              'task_${platform}_error',
              results[platform]!,
            );
            if (!manual) await _notifyAuth(platform);
            return;
          }
          final old = {
            for (final task in await repository.loadVisible())
              task.id: task.toRow(),
          };
          final changed = batch.tasks.where((task) {
            final previous = old[task.id];
            final next = task.toRow();
            return previous == null ||
                [
                  'title',
                  'course',
                  'due_at',
                  'url',
                  'note',
                  'submission_state',
                ].any((key) => previous[key] != next[key]) ||
                (previous['manual_completed'] == null &&
                    previous['completed'] != next['completed']);
          }).length;
          await _saveBatch(platform, batch);
          if (!manual && changed > 0) {
            try {
              await onAutomaticUpdate?.call(platform, changed);
            } catch (_) {
              // 通知失败不能把已成功的同步标成失败。
            }
          }
          results[platform] = batch.warnings.isEmpty
              ? '同步完成：${batch.tasks.length} 项作业'
              : '同步完成，${batch.warnings.length} 项需核对：${batch.warnings.join('；')}';
        } on PlatformRequestException catch (error) {
          // 新票据已保存但网络验证未完成时，旧票据401不等于必须用户登录。
          final loginRetry = platform == 'haoke' && error.statusCode == 401
              ? await _haokeRetry('login')
              : null;
          final awaitingLogin =
              loginRetry != null && loginRetry['failures'] < 3;
          if (platform == 'haoke' && error.statusCode == 403) {
            await database.saveSetting('task_haoke_login_blocked', 'true');
          }
          if ([401, 403].contains(error.statusCode) && !awaitingLogin) {
            await database.saveSetting(
              'task_${platform}_needs_auth',
              '${error.requiresReauth}',
            );
          }
          if (platform == 'haoke') {
            await _recordHaokeFailure(
              'read',
              error,
              awaitingLogin: awaitingLogin,
            );
            results[platform] = (await database.loadSetting(
              'task_haoke_error',
            ))!;
          } else {
            await database.saveSetting('task_${platform}_error', error.message);
            results[platform] = error.message;
          }
          if (!manual && error.requiresReauth && !awaitingLogin) {
            await _notifyAuth(platform);
          }
        } catch (_) {
          const message = '同步暂时失败，已保存的作业和连接不受影响';
          if (platform == 'haoke') {
            await _recordHaokeFailure(
              'read',
              const PlatformRequestException(message),
            );
            results[platform] = '暂时无法更新，稍后再试';
          } else {
            await database.saveSetting('task_${platform}_error', message);
            results[platform] = message;
          }
        }
      }),
    );
    return results;
  }

  Future<void> _notifyAuth(String platform) async {
    try {
      await onAuthRequired?.call(platform);
    } catch (_) {
      // 下次自动检查会重试未成功发送的失效提醒。
    }
  }

  Future<bool> _haokeLoginDue({required bool manual}) async {
    if (await database.loadSetting('task_haoke_login_blocked') == 'true') {
      return manual;
    }
    if (manual &&
        (await database.loadSetting('task_haoke_needs_auth') == 'true' ||
            (await database.loadSetting('task_haoke_session_error') ?? '')
                .isNotEmpty)) {
      return true;
    }
    return _haokeDue('login', const Duration(minutes: 15));
  }

  Future<void> _recordHaokeLoginError(PlatformRequestException error) async {
    await _recordHaokeFailure('login', error);
    if (error.statusCode == 403) {
      await database.saveSetting('task_haoke_login_blocked', 'true');
    }
  }

  Future<HaokeCredentials> _maintainHaoke(
    String account,
    HaokeCredentials current, {
    bool manual = false,
  }) async {
    await _beginHaokeAttempt('login', manual: manual);
    final pending = await credentials.readHaokeCandidate(account);
    var next = pending == null
        ? await client.renewHaoke(current)
        : _decodePair(pending);
    if (pending == null) {
      await credentials.saveHaokeCandidate(account, _encodePair(next));
    }
    String identity;
    try {
      identity = await client.verifyHaokeAccount(next.token);
    } on PlatformRequestException catch (error) {
      // 已保存候选本身过期时，仅用其配对票据再登录一次。
      if (pending == null || error.statusCode != 401) rethrow;
      next = await client.renewHaoke(next);
      await credentials.saveHaokeCandidate(account, _encodePair(next));
      identity = await client.verifyHaokeAccount(next.token);
    }
    if (identity != account) {
      await database.saveSetting('task_haoke_login_blocked', 'true');
      await database.saveSetting('task_haoke_needs_auth', 'true');
      throw const PlatformRequestException(
        '好课账号已变化，请重新连接并确认切换',
        401,
        false,
        true,
      );
    }
    await credentials.save('haoke', account, _encodePair(next));
    await credentials.clearHaokeCandidate(account);
    await database.deleteSetting('task_haoke_login_blocked');
    await database.deleteSetting('task_haoke_session_error');
    await database.deleteSetting('task_haoke_session_error_at');
    await database.deleteSetting('task_haoke_retry_login');
    return next;
  }

  Future<void> _saveBatch(String platform, PlatformTaskBatch batch) async {
    if (platform == 'haoke') {
      await database.deleteSetting('task_haoke_retry_read');
      await database.deleteSetting('task_haoke_error_at');
    }
    await repository.mergePlatform(batch.tasks);
    if (batch.warnings.isEmpty) {
      await database.saveSetting(
        'task_${platform}_last_success',
        batch.syncedAt.toIso8601String(),
      );
    }
    await database.saveSetting(
      'task_${platform}_error',
      batch.warnings.join('；'),
    );
    await database.saveSetting('task_${platform}_needs_auth', 'false');
    await database.deleteSetting('task_${platform}_auth_notified');
    onChanged?.call();
  }

  String _encodePair(HaokeCredentials value) =>
      jsonEncode({'version': 1, 'token': value.token, 'ticket': value.ticket});

  HaokeCredentials _decodePair(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map ||
        decoded['version'] != 1 ||
        decoded['token'] is! String ||
        decoded['ticket'] is! String) {
      throw const FormatException('本机好课连接格式无效');
    }
    return HaokeCredentials(
      token: decoded['token'] as String,
      ticket: decoded['ticket'] as String,
    );
  }
}
