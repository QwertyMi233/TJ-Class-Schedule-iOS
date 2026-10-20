import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../import/star_login_capture.dart';

class StarLoginPage extends StatefulWidget {
  const StarLoginPage({super.key});
  @override
  State<StarLoginPage> createState() => _StarLoginPageState();
}

class _StarLoginPageState extends State<StarLoginPage>
    with WidgetsBindingObserver {
  late final WebViewController _web;
  Timer? _timer;
  bool _reading = false;
  bool _foreground = true;
  bool _finished = false;
  int _navigation = 0;
  String? _error;

  bool get _active =>
      mounted &&
      _foreground &&
      !_finished &&
      ModalRoute.of(context)?.isCurrent == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) =>
              Uri.tryParse(request.url)?.scheme == 'https'
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onPageStarted: (_) {
            _navigation++;
          },
          onPageFinished: (_) => unawaited(_capture()),
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
              setState(() => _error = '官方登录页面加载失败，请检查网络后重新加载');
            }
          },
        ),
      )
      ..loadRequest(
        Uri.parse('https://star.tongji.edu.cn/app/pages/login/login'),
      );
    _startPolling();
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(milliseconds: 700),
      (_) => unawaited(_capture()),
    );
  }

  Future<void> _capture({bool manual = false}) async {
    if (!_active || _reading) return;
    _reading = true;
    try {
      final navigation = _navigation;
      final before = await _web.currentUrl();
      if (!_active ||
          navigation != _navigation ||
          !canReadStarCredentials(before)) {
        return;
      }
      final result = await _web.runJavaScriptReturningResult(
        starCredentialCaptureScript,
      );
      if (!_active) return;
      final after = await _web.currentUrl();
      if (!mounted ||
          !_active ||
          navigation != _navigation ||
          !canReadStarCredentials(after)) {
        return;
      }
      final session = decodeStarLoginCapture(result);
      if (session == null) {
        if (manual) setState(() => _error = '尚未读取到登录信息，请先在官方页面完成登录');
        return;
      }
      _finished = true;
      _timer?.cancel();
      Navigator.pop(context, session);
    } catch (_) {
      // 页面尚未加载或正在统一认证跳转时，等待下一次读取，不输出网页内容。
      if (_active && manual) {
        setState(() => _error = '读取暂未完成，请检查网络后重试');
      }
    } finally {
      _reading = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && !_finished) {
      _startPolling();
      unawaited(_capture());
    } else {
      _timer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('卓越星官方登录'),
      actions: [
        IconButton(
          tooltip: '重新加载',
          onPressed: () {
            _navigation++;
            setState(() => _error = null);
            unawaited(_web.reload());
          },
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            '在下方官方页面完成登录。登录后会自动保存连接并同步已报名活动，无需复制 Token。'
            '凭据仅保存在本机，不读取统一认证密码。',
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(child: WebViewWidget(controller: _web)),
        SafeArea(
          minimum: const EdgeInsets.all(12),
          child: TextButton(
            onPressed: () => unawaited(_capture(manual: true)),
            child: const Text('已登录？重试读取'),
          ),
        ),
      ],
    ),
  );

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(
      _web.loadRequest(Uri.parse('about:blank')).catchError((Object _) {}),
    );
    super.dispose();
  }
}
