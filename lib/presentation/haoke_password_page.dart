import '../platform/platform_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/schedule_controller.dart';
import '../application/task_background_sync.dart';
import '../application/task_sync_controller.dart';
import '../data/haoke_password_login.dart';
import '../data/platform_task_client.dart';
import '../data/schedule_database.dart';

class HaokePasswordPage extends ConsumerStatefulWidget {
  const HaokePasswordPage({required this.confirmSwitch, super.key});
  final Future<bool> Function(String oldAccount, String newAccount)
  confirmSwitch;

  @override
  ConsumerState<HaokePasswordPage> createState() => _HaokePasswordPageState();
}

class _HaokePasswordPageState extends ConsumerState<HaokePasswordPage> {
  final _account = TextEditingController();
  final _password = TextEditingController();
  String _mode = 'userno';
  bool _consent = false;
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    if (_busy) return;
    if (_account.text.trim().isEmpty || _password.text.isEmpty || !_consent) {
      setState(() => _error = '请填写账号密码，并勾选本机加密保存');
      return;
    }
    final login = HaokePasswordCredentials(
      username: _account.text.trim(),
      password: _password.text,
      mode: _mode,
    );
    _password.clear();
    setState(() {
      _busy = true;
      _error = null;
    });
    ScheduleDatabase? db;
    var saved = false;
    try {
      db = await ref.read(databaseProvider.future);
      if (!mounted) return;
      final service = await ref.read(taskSyncServiceProvider.future);
      if (!mounted) return;
      saved = await service.connectHaokePassword(
        login,
        confirmSwitch: (oldAccount, newAccount) => mounted
            ? widget.confirmSwitch(oldAccount, newAccount)
            : Future.value(false),
      );
      if (!saved && mounted) setState(() => _error = '已取消账号切换，原连接保留');
    } on PlatformRequestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on StateError catch (error) {
      if (mounted) setState(() => _error = error.message.toString());
    } catch (_) {
      if (mounted) setState(() => _error = '连接未完成，已有作业和连接会保留');
    } finally {
      try {
        if (db != null) {
          await configureTaskBackgroundSync(
            await db.loadSetting('task_auto_sync') == 'true',
          );
        }
      } catch (_) {
        saved = false;
        if (mounted) setState(() => _error = '连接已保存，但后台安排未完成，请重新打开应用');
      }
      if (mounted) setState(() => _busy = false);
    }
    if (saved && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('好课自动同步')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _mode,
          decoration: const InputDecoration(labelText: '官网登录方式'),
          items: const [
            DropdownMenuItem(
              value: 'userno',
              child: Text(
                '同济大学学号',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DropdownMenuItem(
              value: 'username',
              child: Text(
                '手机号登录',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          onChanged: _busy ? null : (value) => setState(() => _mode = value!),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _account,
          enabled: !_busy,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: '好课账号'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          enabled: !_busy,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          onSubmitted: (_) => _save(),
          decoration: const InputDecoration(labelText: '密码'),
        ),
        CheckboxListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('加密保存到本机，用于自动同步'),
          value: _consent,
          onChanged: _busy
              ? null
              : (value) => setState(() => _consent = value!),
        ),
        const Text(
          '此密码仅在本机加密保存，并提交好课官方账号中心。'
          '遇到验证码或密码失效时，请重新登录。',
        ),
        const SizedBox(height: 16),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: const Icon(Icons.login),
          label: const Text('保存并启用自动同步'),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(12),
            child: LinearProgressIndicator(),
          ),
      ],
    ),
  );

  @override
  void dispose() {
    _account.dispose();
    _password.dispose();
    super.dispose();
  }
}
