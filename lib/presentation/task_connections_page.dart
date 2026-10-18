import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'task_browser_page.dart';

import '../application/schedule_controller.dart';
import '../application/task_sync_controller.dart';
import '../application/task_background_sync.dart';
import '../application/task_state.dart';
import '../data/platform_task_client.dart';
import 'platform_login_page.dart';
import 'task_import_page.dart';
import 'task_guide_page.dart';
import 'canvas_session_page.dart';

/// 日常界面只显示一条行动提示；接口细节保留在本机诊断中。
String? haokeConnectionNotice(Map<String, String?> values) {
  if (values['task_haoke_needs_auth'] == 'true' ||
      values['task_haoke_login_blocked'] == 'true') {
    return '请重新登录好课';
  }
  final errors = [
    values['task_haoke_error'],
    values['task_haoke_session_error'],
  ].whereType<String>().where((value) => value.isNotEmpty).toList();
  if (errors.isEmpty) return null;
  if (errors.any((value) => value == '网络不稳定，稍后自动重试')) {
    return '网络不稳定，稍后自动重试';
  }
  return '暂时无法更新，稍后再试';
}

String _shortTime(String? value) {
  final time = DateTime.tryParse(value ?? '')?.toLocal();
  if (time == null) return '暂无';
  String two(int value) => '$value'.padLeft(2, '0');
  return '${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
}

String? _latestHaokeAttempt(Map<String, String?> values) {
  final times =
      [values['task_haoke_error_at'], values['task_haoke_session_error_at']]
          .map((value) => DateTime.tryParse(value ?? ''))
          .whereType<DateTime>()
          .toList()
        ..sort();
  return times.isEmpty ? null : times.last.toIso8601String();
}

class TaskConnectionsPage extends ConsumerStatefulWidget {
  const TaskConnectionsPage({super.key});

  @override
  ConsumerState<TaskConnectionsPage> createState() =>
      _TaskConnectionsPageState();
}

class _TaskConnectionsPageState extends ConsumerState<TaskConnectionsPage>
    with WidgetsBindingObserver {
  late Future<Map<String, String?>> _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _load();
  }

  void _load() => setState(() {
    _status = _readStatus();
  });

  Future<Map<String, String?>> _readStatus() async {
    final db = await ref.read(databaseProvider.future);
    final values = <String, String?>{};
    for (final key in [
      'task_auto_sync',
      'task_canvas_session_error',
      'task_haoke_session_error',
      'task_haoke_login_success',
      'task_haoke_login_blocked',
      'task_haoke_error_at',
      'task_haoke_session_error_at',
      for (final platform in ['canvas', 'haoke']) ...[
        'task_${platform}_account',
        'task_${platform}_last_success',
        'task_${platform}_error',
        'task_${platform}_needs_auth',
      ],
    ]) {
      values[key] = await db.loadSetting(key);
    }
    return values;
  }

  Future<bool> _confirmAccountSwitch(
    String oldAccount,
    String newAccount,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('检测到不同账号'),
          content: Text(
            '当前账号：$oldAccount\n新账号：$newAccount\n切换后列表只显示新账号的同步作业；旧数据保留在本机。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认切换'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _connect(String platform) async {
    final result = await Navigator.push<PlatformLoginResult>(
      context,
      MaterialPageRoute(builder: (_) => PlatformLoginPage(platform: platform)),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final service = await ref.read(taskSyncServiceProvider.future);
      final saved = platform == 'canvas'
          ? await service.connectCanvas(
              result.token,
              confirmSwitch: _confirmAccountSwitch,
            )
          : await service.connectHaoke(
              HaokeCredentials(token: result.token, ticket: result.ticket!),
              confirmSwitch: _confirmAccountSwitch,
            );
      if (saved && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('连接已加密保存，作业已同步到本机')));
      }
    } on PlatformRequestException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('连接失败；已有作业和连接不会被清除')));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _load();
      }
    }
  }

  Future<void> _disconnect(String platform) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('断开平台连接？'),
        content: const Text('将删除这台手机保存的平台凭证，已同步作业仍保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('断开'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await (await ref.read(
        taskSyncServiceProvider.future,
      )).disconnect(platform);
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _load();
      }
    }
  }

  Future<void> _setAuto(bool enabled) async {
    if (_busy) return;
    setState(() => _busy = true);
    final db = await ref.read(databaseProvider.future);
    final previous = await db.loadSetting('task_auto_sync');
    try {
      await db.saveSetting('task_auto_sync', '$enabled');
      await configureTaskBackgroundSync(enabled);
    } catch (_) {
      await db.saveSetting('task_auto_sync', previous ?? 'false');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法更改后台同步设置，请重试')));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _load();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(taskRevisionProvider, (_, __) => _load());
    return Scaffold(
      appBar: AppBar(
        title: const Text('平台连接'),
        actions: [
          IconButton(
            tooltip: 'Token 导入教程',
            icon: const Icon(Icons.help_outline),
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(builder: (_) => const TaskGuidePage()),
            ),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, String?>>(
        future: _status,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final values = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('连接仅保存在本机，离线也能查看已同步作业。'),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('自动检查作业（含后台）'),
                subtitle: const Text('约每 30 分钟更新，省电模式下可能延后。'),
                value: values['task_auto_sync'] == 'true',
                onChanged: _busy ? null : _setAuto,
              ),
              for (final (platform, title, url) in [
                (
                  'canvas',
                  'Canvas',
                  'https://canvas.tongji.edu.cn/profile/settings',
                ),
                ('haoke', '好课平台', 'https://tongji.aihaoke.net/student/course'),
              ])
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          values['task_${platform}_account'] == null
                              ? '尚未连接'
                              : '已连接 · 本机加密保存',
                        ),
                        if (values['task_${platform}_last_success'] != null)
                          Text(
                            '最近更新：${_shortTime(values['task_${platform}_last_success'])}',
                          ),
                        if (platform == 'haoke' &&
                            haokeConnectionNotice(values) != null)
                          Text(haokeConnectionNotice(values)!),
                        if (platform == 'haoke' &&
                            haokeConnectionNotice(values) != null &&
                            _latestHaokeAttempt(values) != null)
                          Text(
                            '上次尝试：${_shortTime(_latestHaokeAttempt(values))}',
                          ),
                        if (platform != 'haoke' &&
                            values['task_${platform}_needs_auth'] == 'true')
                          const Text('需要重新登录或更新令牌'),
                        if (platform != 'haoke' &&
                            (values['task_${platform}_error'] ?? '').isNotEmpty)
                          Text('提示：${values['task_${platform}_error']}'),
                        if (platform == 'canvas' &&
                            (values['task_canvas_session_error'] ?? '')
                                .isNotEmpty)
                          Text('续期提示：${values['task_canvas_session_error']}'),
                        Wrap(
                          spacing: 8,
                          children: [
                            if (platform == 'canvas')
                              OutlinedButton(
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        await Navigator.push<void>(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => CanvasSessionPage(
                                              confirmSwitch:
                                                  _confirmAccountSwitch,
                                            ),
                                          ),
                                        );
                                        if (mounted) _load();
                                      },
                                child: const Text('自动续期设置'),
                              ),
                            FilledButton(
                              onPressed: _busy
                                  ? null
                                  : () => _connect(platform),
                              child: Text(
                                values['task_${platform}_account'] == null
                                    ? '连接'
                                    : values['task_${platform}_needs_auth'] ==
                                          'true'
                                    ? platform == 'haoke'
                                          ? '重新登录'
                                          : '重新加载 Token'
                                    : '更新连接',
                              ),
                            ),
                            if (values['task_${platform}_account'] != null)
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _disconnect(platform),
                                child: const Text('断开'),
                              ),
                            TextButton(
                              onPressed: () => Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      TaskBrowserPage(url: url, title: title),
                                ),
                              ),
                              child: const Text('打开官方页面'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text('其他平台', style: Theme.of(context).textTheme.titleMedium),
              const Text(
                '学习通、Polymas、课程 OJ 暂未实现官方接口自动同步。可在官方页面采集可见作业，核对后导入；也可导入采集 JSON；课程 OJ 需可访问校园内网。',
              ),
              for (final (title, url) in [
                ('学习通', 'https://i.chaoxing.com/base?ws=1'),
                (
                  'Polymas',
                  'https://hike-teaching-center.polymas.com/stu-hike/agent-course-hike/ai-course-center',
                ),
                ('课程 OJ', 'http://192.168.180.213:18080/d/gaocheng2026fall/'),
              ])
                ListTile(
                  title: Text(title),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TaskBrowserPage(url: url, title: title),
                    ),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(builder: (_) => const TaskImportPage()),
                ),
                icon: const Icon(Icons.file_upload),
                label: const Text('导入页面采集 JSON'),
              ),
            ],
          );
        },
      ),
    );
  }
}
