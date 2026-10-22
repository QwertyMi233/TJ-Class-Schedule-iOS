import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../platform/platform_ui.dart';
import '../application/schedule_controller.dart';
import '../application/task_state.dart';
import '../widget/next_course_widget_service.dart';
import '../widget/task_widget_service.dart';

class WidgetStatusPage extends ConsumerStatefulWidget {
  const WidgetStatusPage({super.key});
  @override
  ConsumerState<WidgetStatusPage> createState() => _WidgetStatusPageState();
}

class _WidgetStatusPageState extends ConsumerState<WidgetStatusPage> {
  static const _channel = MethodChannel('offline_course_schedule/widget');
  Map<String, dynamic>? _status;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    try {
      final status = await _channel.invokeMapMethod<String, dynamic>(
        'widgetStatus',
      );
      if (mounted) setState(() => _status = status);
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _sync() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final schedule = await ref.read(scheduleControllerProvider.future);
      final color = await ref.read(widgetColorProvider.future);
      final refresh = await ref.read(widgetRefreshModeProvider.future);
      await const NextCourseWidgetService().sync(
        schedule,
        colorValue: color,
        refreshMode: refresh,
      );
      final repository = await ref.read(taskRepositoryProvider.future);
      await const TaskWidgetService().sync(await repository.loadVisible());
      await _channel.invokeMethod<void>('reloadWidgets');
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _error = error.message ?? '小组件同步失败，请检查签名共享权限');
      }
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取课表或作业，请稍后重试');
    } finally {
      await _read();
      if (mounted) setState(() => _busy = false);
    }
  }

  String _date(dynamic value) {
    if (value is! num || value == 0) return '尚未写入';
    final date = DateTime.fromMillisecondsSinceEpoch((value * 1000).round());
    String two(int v) => v.toString().padLeft(2, '0');
    return '${date.month}月${date.day}日 ${two(date.hour)}:${two(date.minute)}:${two(date.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final available = _status?['containerAvailable'] == true;
    return Scaffold(
      appBar: AppBar(title: const Text('小组件同步')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            _status == null
                ? '正在检查小组件共享权限'
                : available
                ? '共享容器已连接'
                : '小组件共享权限未授权',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (_status != null && !available)
            const Text('当前签名没有给主应用和小组件授权同一个 App Group。仅重新打开 App 无法解决这个权限问题。'),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('未来课程与安排：${_status?['courseCount'] ?? 0} 项'),
                  Text('写入时间：${_date(_status?['coursesUpdated'])}'),
                  const SizedBox(height: 12),
                  Text('未完成作业：${_status?['taskCount'] ?? 0} 项'),
                  Text('写入时间：${_date(_status?['tasksUpdated'])}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _sync,
            child: Text(_busy ? '正在同步…' : '立即同步课表与作业'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 20),
          const Text(
            '手动签名时，请保留 TJWidgets.appex，并为主应用和该扩展配置同一个、由描述文件授权的 App Group。签名工具和证书需要支持 App Groups。',
          ),
          const SizedBox(height: 10),
          SelectableText(
            '工程共享标识：${_status?['configuredGroup'] ?? 'group.icu.tjschedule.classschedule'}',
          ),
          if (available) SelectableText('当前使用：${_status?['resolvedGroup']}'),
          const SizedBox(height: 20),
          const Text(
            '写入成功后会请求 iOS 刷新两个小组件。系统决定实际刷新时间；倒计时由系统绘制，后台同步也受 iOS 调度限制。',
          ),
        ],
      ),
    );
  }
}
