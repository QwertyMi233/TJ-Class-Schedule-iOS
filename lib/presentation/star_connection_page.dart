import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/schedule_controller.dart';
import '../application/star_background_sync.dart';
import '../application/star_sync_service.dart';
import '../data/platform_credential_store.dart';
import '../data/schedule_database.dart';
import '../data/star_activity_client.dart';
import 'star_login_page.dart';

class StarConnectionPage extends ConsumerStatefulWidget {
  const StarConnectionPage({super.key});
  @override
  ConsumerState<StarConnectionPage> createState() => _StarConnectionPageState();
}

class _StarConnectionPageState extends ConsumerState<StarConnectionPage> {
  final _token = TextEditingController();
  bool _busy = false;
  bool _connected = false;
  bool _needsAuth = false;
  String? _lastSync;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = await ref.read(databaseProvider.future);
      final connected =
          await PlatformCredentialStore(db).activeAccount('star') != null;
      final last = DateTime.tryParse(
        await db.loadSetting('star_last_sync') ?? '',
      )?.toLocal();
      final needsAuth = await db.loadSetting('task_star_needs_auth') == 'true';
      final error = await db.loadSetting('star_error');
      if (!mounted) return;
      setState(() {
        _connected = connected;
        _needsAuth = needsAuth;
        _lastSync = last == null
            ? null
            : '${last.year}-${last.month.toString().padLeft(2, '0')}-'
                  '${last.day.toString().padLeft(2, '0')} ${last.hour.toString().padLeft(2, '0')}:'
                  '${last.minute.toString().padLeft(2, '0')}';
        _error = error;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取连接设置，请重新打开此页面');
    }
  }

  Future<void> _run(
    Future<void> Function(StarSyncService) action,
    String message,
  ) async {
    setState(() => _busy = true);
    ScheduleDatabase? database;
    String? actionError;
    try {
      database = await ref.read(databaseProvider.future);
      final service = await ref.read(starSyncServiceProvider.future);
      await action(service);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } on StarRequestException catch (error) {
      actionError = error.message;
    } catch (_) {
      actionError = '卓越星连接操作失败，请稍后重试';
    } finally {
      if (mounted) _token.clear();
      try {
        if (database != null) {
          await configureStarBackgroundSync(
            await database.loadSetting('star_enabled') == 'true',
          );
        }
        if (mounted) await _load();
      } catch (_) {
        actionError = '后台同步设置失败，请重新打开应用后重试';
      }
      if (mounted) {
        setState(() {
          _busy = false;
          if (actionError != null) _error = actionError;
        });
      }
    }
  }

  Future<bool> _confirmSwitch(String oldAccount, String newAccount) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('切换卓越星账号？'),
            content: const Text('将替换尚未开始的卓越星活动，已开始的记录和自建备忘录会保留。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('切换'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _login() async {
    setState(() => _busy = true);
    try {
      final session = await Navigator.push<StarSession>(
        context,
        MaterialPageRoute(builder: (_) => const StarLoginPage()),
      );
      if (!mounted || session == null) return;
      await _run(
        (service) =>
            service.connectSession(session, confirmSwitch: _confirmSwitch),
        '连接成功，已同步活动',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('卓越星活动同步')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('已报名活动会写入课表。平台变更会覆盖本机对这些活动的修改，断开连接后保留本地记录。'),
        const SizedBox(height: 12),
        Text(
          _needsAuth
              ? '登录已失效，请重新接入'
              : _connected
              ? '已连接卓越星'
              : '尚未连接卓越星',
        ),
        if (_lastSync != null) Text('上次成功同步：$_lastSync'),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : _login,
          icon: const Icon(Icons.login),
          label: const Text('官方网页登录'),
        ),
        const SizedBox(height: 20),
        ExpansionTile(
          key: const PageStorageKey<String>('star-manual-token'),
          tilePadding: EdgeInsets.zero,
          enabled: !_busy,
          title: const Text('手动令牌（备用）'),
          children: [
            TextField(
              key: const PageStorageKey<String>('star-refresh-token'),
              controller: _token,
              enabled: !_busy,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              decoration: const InputDecoration(
                labelText: 'Refresh Token',
                helperText: '仅填写刷新令牌，保存在本机系统安全存储中。',
                helperMaxLines: 3,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run(
                      (service) => service.connect(
                        _token.text,
                        confirmSwitch: _confirmSwitch,
                      ),
                      '连接成功，已同步活动',
                    ),
              icon: const Icon(Icons.link),
              label: const Text('连接并同步'),
            ),
          ],
        ),
        if (_connected) ...[
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () =>
                      _run((service) => service.refresh(manual: true), '活动已同步'),
            icon: const Icon(Icons.sync),
            label: const Text('立即同步'),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => _run((service) => service.disconnect(), '已断开连接，保留本地活动'),
            child: const Text('断开连接'),
          ),
        ],
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(12),
            child: LinearProgressIndicator(),
          ),
        const SizedBox(height: 20),
        const Text('自动检查：前台约 2 分钟，后台约 15 分钟，系统可能延后。'),
        const SizedBox(height: 8),
        const Text(
          '系列活动可能显示报名场次的签到时段，地点缺失时显示“地点待公布”。'
          '首次仅同步未结束且未签到完成的活动。',
        ),
      ],
    ),
  );

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }
}
