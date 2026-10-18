import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../application/schedule_controller.dart';
import '../application/task_background_sync.dart';
import '../application/task_sync_controller.dart';
import '../data/canvas_session_manager.dart';
import '../data/platform_task_client.dart';
import 'magic_os_guide_page.dart';

class CanvasSessionPage extends ConsumerStatefulWidget {
  const CanvasSessionPage({required this.confirmSwitch, super.key});
  final Future<bool> Function(String oldAccount, String newAccount)
  confirmSwitch;

  @override
  ConsumerState<CanvasSessionPage> createState() => _CanvasSessionPageState();
}

class _CanvasSessionPageState extends ConsumerState<CanvasSessionPage> {
  final _manager = const CanvasSessionManager();
  List<CanvasTokenOption> _tokens = [];
  CanvasTokenOption? _selected;
  Map<Object?, Object?> _status = {};
  bool _busy = false, _consent = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _readStatus();
  }

  Future<void> _readStatus() async {
    try {
      final status = await _manager.status();
      if (mounted) setState(() => _status = status);
    } on CanvasSessionException catch (error) {
      if (mounted) setState(() => _message = error.message);
    }
  }

  Future<void> _list() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final tokens = await _manager.listTokens();
      if (mounted) {
        setState(() {
          _tokens = tokens;
          _selected = null;
          _consent = false;
          if (tokens.isEmpty) _message = '未找到可用令牌，请先在官方页面创建一枚课表专用令牌，再返回读取。';
        });
      }
    } on CanvasSessionException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enable() async {
    final option = _selected;
    if (!_consent || option == null || _busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final service = await ref.read(taskSyncServiceProvider.future);
      if (!await service.connectCanvasSession(
        option,
        confirmSwitch: widget.confirmSwitch,
      )) {
        return;
      }
      final db = await ref.read(databaseProvider.future);
      final previous = await db.loadSetting('task_auto_sync');
      await db.saveSetting('task_auto_sync', 'true');
      try {
        await configureTaskBackgroundSync(true);
        if (mounted) setState(() => _message = '已连接并开启自动同步。可以返回课表正常使用。');
      } catch (_) {
        await db.saveSetting('task_auto_sync', previous ?? 'false');
        if (mounted) {
          setState(() => _message = '连接已保存，但后台任务未能开启，请回到平台连接重新开启自动同步。');
        }
      }
    } on CanvasSessionException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } on PlatformRequestException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } on StateError catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) setState(() => _message = '连接暂未完成，已安全保存的新凭证会保留，请稍后重试。');
    } finally {
      await _readStatus();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disable() async {
    setState(() => _busy = true);
    try {
      await _manager.disable();
      if (mounted) setState(() => _message = '已停止自动续期，已同步的作业保留。');
    } on CanvasSessionException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      await _readStatus();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Canvas 自动续期')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          '在学校官方页面登录一次，选择仅供课表使用的令牌。登录状态仅保留在本机，令牌加密保存；课表不保存学校密码，也不经开发者服务器中转。',
        ),
        const SizedBox(height: 12),
        if (_status['enabled'] == true)
          Text('已开启 · ${_status['purpose'] ?? '课表专用令牌'}'),
        const Text('系统会定期维护连接；省电、强行停止或学校要求重新认证时，可能需要打开 App 或重新登录。'),
        if (_status['batteryOptimizationIgnored'] == false)
          const Text('当前系统仍限制电池优化，建议按后台设置教程调整；部分荣耀机型的“不允许”表示不允许优化。'),
        TextButton(
          onPressed: _busy
              ? null
              : () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(builder: (_) => const MagicOsGuidePage()),
                ),
          child: const Text('查看后台设置教程'),
        ),
        FilledButton.tonal(
          onPressed: _busy
              ? null
              : () async {
                  await Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const _CanvasOfficialLogin(),
                    ),
                  );
                  if (mounted) {
                    setState(() {
                      _tokens = [];
                      _selected = null;
                      _consent = false;
                    });
                  }
                },
          child: const Text('1. 打开学校登录 / 创建专用令牌'),
        ),
        const Text('在官方设置页创建令牌时，可命名为“课集自动同步”。不要选择其他软件正在使用的令牌。'),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _busy ? null : _list,
          child: const Text('2. 读取可选令牌'),
        ),
        if (_tokens.isNotEmpty)
          DropdownButtonFormField<CanvasTokenOption>(
            key: ValueKey(_tokens),
            isExpanded: true,
            decoration: const InputDecoration(labelText: '选择课表专用令牌'),
            items: _tokens
                .map(
                  (token) => DropdownMenuItem(
                    value: token,
                    child: Text(token.purpose, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: _busy
                ? null
                : (token) => setState(() {
                    _selected = token;
                    _consent = false;
                  }),
          ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('同意重新生成所选令牌并开启作业自动同步'),
          subtitle: const Text('重新生成后，所选令牌的旧值会失效。新值加密保存在本机，仅用于读取本人课程和作业。'),
          value: _consent,
          onChanged: _busy || _selected == null
              ? null
              : (value) => setState(() => _consent = value ?? false),
        ),
        FilledButton(
          onPressed: _busy || !_consent || _selected == null ? null : _enable,
          child: const Text('连接并开启自动同步'),
        ),
        if (_status['enabled'] == true)
          TextButton(
            onPressed: _busy ? null : _disable,
            child: const Text('停止自动续期'),
          ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(12),
            child: LinearProgressIndicator(),
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(_message!),
          ),
      ],
    ),
  );
}

class _CanvasOfficialLogin extends StatefulWidget {
  const _CanvasOfficialLogin();
  @override
  State<_CanvasOfficialLogin> createState() => _CanvasOfficialLoginState();
}

class _CanvasOfficialLoginState extends State<_CanvasOfficialLogin> {
  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) =>
            Uri.tryParse(request.url)?.scheme == 'https'
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
      ),
    )
    ..loadRequest(Uri.parse('https://canvas.tongji.edu.cn/profile/settings'));
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Canvas 官方页面'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('已登录，返回选择'),
        ),
      ],
    ),
    body: WebViewWidget(controller: _controller),
  );
}
