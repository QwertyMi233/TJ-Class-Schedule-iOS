import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/platform_credential_store.dart';
import '../data/schedule_database.dart';
import '../data/star_activity_client.dart';
import '../domain/star_activity.dart';
import 'schedule_controller.dart';

final starSyncServiceProvider = FutureProvider<StarSyncService>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  var alive = true;
  final service = StarSyncService(
    db,
    onChanged: () async {
      if (alive) {
        await ref.read(scheduleControllerProvider.notifier).reloadMemos();
      }
    },
  );
  ref.onDispose(() {
    alive = false;
    service.close();
  });
  return service;
});

class StarSyncService {
  StarSyncService(
    this.database, {
    StarActivityClient? client,
    PlatformCredentialStore? credentials,
    DateTime Function()? clock,
    this.onChanged,
  }) : client = client ?? StarActivityClient(),
       credentials = credentials ?? PlatformCredentialStore(database),
       clock = clock ?? DateTime.now;

  final ScheduleDatabase database;
  final StarActivityClient client;
  final PlatformCredentialStore credentials;
  final DateTime Function() clock;
  final Future<void> Function()? onChanged;
  bool _busy = false;
  void close() => client.close();

  Future<void> connect(
    String refreshToken, {
    required Future<bool> Function(String oldAccount, String newAccount)
    confirmSwitch,
  }) => connectSession(
    StarSession(accessToken: '', refreshToken: refreshToken.trim()),
    confirmSwitch: confirmSwitch,
  );

  Future<void> connectSession(
    StarSession captured, {
    required Future<bool> Function(String oldAccount, String newAccount)
    confirmSwitch,
  }) => _exclusive(() async {
    if (captured.refreshToken.trim().isEmpty) {
      throw const StarRequestException('请填写 Refresh Token');
    }
    if (await database.loadTermSchedule(currentTermId) == null) {
      throw const StarRequestException('请先设置学期，再连接卓越星');
    }
    final old =
        await credentials.activeAccount('star') ??
        await database.loadSetting('task_star_last_account');
    var session = captured;
    var renewed = false;
    if (session.accessToken.isEmpty) {
      session = await client.renew(session.refreshToken);
      renewed = true;
    }
    String account;
    try {
      account = await client.account(session.accessToken);
    } on StarRequestException catch (error) {
      if (!error.needsAuth || renewed) rethrow;
      session = await client.renew(session.refreshToken);
      renewed = true;
      account = await client.account(session.accessToken);
    }
    if (old != null && old != account && !await confirmSwitch(old, account)) {
      throw const StarRequestException('已取消账号切换，原连接保持不变');
    }
    // 续期可能轮换刷新令牌，必须先安全落盘，列表失败后仍能重试。
    await credentials.save('star', account, session.encode());
    if (old != null && old != account) {
      await database.saveSetting('star_previous_account', old);
    }
    await database.saveSetting('star_enabled', 'true');
    await database.deleteSetting('star_last_attempt');
    try {
      List<StarActivity> activities;
      try {
        activities = await client.activities(session.accessToken);
      } on StarRequestException catch (error) {
        if (!error.needsAuth || renewed) rethrow;
        session = await client.renew(session.refreshToken);
        await credentials.save('star', account, session.encode());
        if (await client.account(session.accessToken) != account) {
          throw const StarRequestException(
            '卓越星账号已变化，请重新连接并确认切换',
            needsAuth: true,
          );
        }
        activities = await client.activities(session.accessToken);
      }
      await _save(account, activities, previousAccount: old);
    } on StarRequestException catch (error) {
      await _recordError(error);
      rethrow;
    }
  });

  Future<void> disconnect() => _exclusive(() async {
    await database.saveSetting('star_enabled', 'false');
    await credentials.remove('star');
    await database.deleteSetting('star_error');
  });

  Future<void> refresh({bool manual = false}) => _exclusive(() async {
    if (await database.loadSetting('star_enabled') != 'true') return;
    final now = clock();
    final last = DateTime.tryParse(
      await database.loadSetting('star_last_attempt') ?? '',
    );
    if (!manual &&
        last != null &&
        now.difference(last) < const Duration(minutes: 2)) {
      return;
    }
    if (!manual &&
        await database.loadSetting('task_star_needs_auth') == 'true') {
      return;
    }
    final account = await credentials.activeAccount('star');
    final saved = await credentials.read('star');
    if (account == null || saved == null) return;
    if (await database.loadTermSchedule(currentTermId) == null) return;
    await database.saveSetting('star_last_attempt', now.toIso8601String());
    try {
      var session = StarSession.decode(saved);
      Future<void> renew() async {
        session = await client.renew(session.refreshToken);
        await credentials.save('star', account, session.encode());
      }

      var renewed = false;
      final expires = session.expiresTime;
      if (expires != null && expires <= now.millisecondsSinceEpoch + 60000) {
        await renew();
        renewed = true;
      }
      List<StarActivity> activities;
      try {
        activities = await client.activities(session.accessToken);
      } on StarRequestException catch (error) {
        if (!error.needsAuth || renewed) rethrow;
        await renew();
        renewed = true;
        activities = await client.activities(session.accessToken);
      }
      if (renewed && await client.account(session.accessToken) != account) {
        throw const StarRequestException(
          '卓越星账号已变化，请重新连接并确认切换',
          needsAuth: true,
        );
      }
      await _save(account, activities);
    } on StarRequestException catch (error) {
      await _recordError(error);
      rethrow;
    } on FormatException {
      const error = StarRequestException('卓越星凭据无法读取，请重新连接', needsAuth: true);
      await _recordError(error);
      throw error;
    }
  });

  Future<void> _recordError(StarRequestException error) async {
    await database.saveSetting('star_error', error.message);
    if (error.needsAuth) {
      await database.saveSetting('task_star_needs_auth', 'true');
    }
  }

  Future<void> _save(
    String account,
    List<StarActivity> activities, {
    String? previousAccount,
  }) async {
    final now = clock().toUtc();
    previousAccount ??= await database.loadSetting('star_previous_account');
    await database.database.transaction((txn) async {
      final terms = await txn.query(
        'terms',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [currentTermId],
      );
      if (terms.isEmpty) throw const StarRequestException('请先设置学期，再同步卓越星活动');
      final existing = await txn.query(
        'memos',
        where: 'term_id = ? AND source = ?',
        whereArgs: [currentTermId, 'star'],
      );
      final rows = {for (final row in existing) row['id'] as String: row};
      final desired = <String>{};
      final present = <String>{};
      for (final activity in activities) {
        present.add(activity.memoPrefix(account));
        if (activity.completed &&
            !rows.keys.any(
              (id) => id.startsWith(activity.memoPrefix(account)),
            )) {
          continue;
        }
        final memos = activity.toMemos(account);
        for (final memo in memos) {
          final old = rows[memo.id];
          // 首次仅导入尚未结束的安排；已有记录继续保留并跟随平台更新。
          if (old == null &&
              (activity.completed || !activity.end.isAfter(now))) {
            continue;
          }
          desired.add(memo.id);
          final values = {
            'id': memo.id,
            'term_id': currentTermId,
            'title': memo.title,
            'location': memo.location,
            'color_value': old?['color_value'] ?? memo.colorValue,
            'source': 'star',
            'date': memo.date!.toIso8601String().substring(0, 10),
            'start_minutes': memo.startMinutes,
            'end_minutes': memo.endMinutes,
            'weekday': null,
            'start_period': null,
            'end_period': null,
            'start_week': null,
            'end_week': null,
            'week_type': null,
            'explicit_weeks': null,
          };
          if (old == null) {
            await txn.insert('memos', values);
          } else {
            await txn.update(
              'memos',
              values,
              where: 'id = ?',
              whereArgs: [memo.id],
            );
          }
        }
      }
      for (final row in existing) {
        final id = row['id'] as String;
        final owned =
            id.startsWith(StarActivity.accountPrefix(account)) ||
            (previousAccount != null &&
                id.startsWith(StarActivity.accountPrefix(previousAccount)));
        if (!owned || desired.contains(id)) continue;
        if (row['date'] == null) continue;
        final date = DateTime.parse(row['date'] as String);
        final start = DateTime.utc(date.year, date.month, date.day)
            .add(Duration(minutes: row['start_minutes'] as int))
            .subtract(const Duration(hours: 8));
        final stillEnrolled = present.any(id.startsWith);
        // 改期时删除旧分段；取消报名只移除尚未开始的备忘录。
        if (stillEnrolled || start.isAfter(now)) {
          await txn.delete('memos', where: 'id = ?', whereArgs: [id]);
        }
      }
      await txn.rawInsert(
        'INSERT OR REPLACE INTO app_settings (key, value) VALUES (?, ?)',
        ['star_last_sync', now.toIso8601String()],
      );
      await txn.rawInsert(
        'INSERT OR REPLACE INTO app_settings (key, value) VALUES (?, ?)',
        ['star_last_attempt', now.toIso8601String()],
      );
      await txn.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: ['star_error'],
      );
      await txn.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: ['star_previous_account'],
      );
      await txn.rawInsert(
        'INSERT OR REPLACE INTO app_settings (key, value) VALUES (?, ?)',
        ['task_star_needs_auth', 'false'],
      );
    });
    await onChanged?.call();
  }

  /// 前台与 Workmanager 使用同一个短期数据库租约，避免同时轮换 refreshToken。
  Future<void> _exclusive(Future<void> Function() action) async {
    if (_busy) throw const StarRequestException('卓越星正在同步，请稍后重试');
    _busy = true;
    final owner = DateTime.now().microsecondsSinceEpoch.toString();
    var claimed = false;
    try {
      claimed = await database.database.transaction((txn) async {
        final rows = await txn.query(
          'app_settings',
          where: 'key = ?',
          whereArgs: ['star_sync_lease'],
        );
        if (rows.isNotEmpty) {
          final previous = int.tryParse(rows.single['value'] as String);
          if (previous != null &&
              DateTime.now().difference(
                    DateTime.fromMicrosecondsSinceEpoch(previous),
                  ) <
                  const Duration(minutes: 5)) {
            return false;
          }
        }
        await txn.rawInsert(
          'INSERT OR REPLACE INTO app_settings (key, value) VALUES (?, ?)',
          ['star_sync_lease', owner],
        );
        return true;
      });
      if (!claimed) throw const StarRequestException('卓越星正在后台同步，请稍后重试');
      await action();
    } finally {
      if (claimed) {
        await database.database.delete(
          'app_settings',
          where: 'key = ? AND value = ?',
          whereArgs: ['star_sync_lease', owner],
        );
      }
      _busy = false;
    }
  }
}
