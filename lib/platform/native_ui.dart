import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as m;
import 'package:flutter/services.dart';

bool get canHostNativeUI => !kIsWeb && Platform.isIOS;

String widgetLabel(Widget? widget) {
  if (widget is Text) {
    return widget.data ?? widget.textSpan?.toPlainText() ?? '';
  }
  if (widget is m.Tooltip) return widget.message ?? widgetLabel(widget.child);
  if (widget is Row) {
    return widget.children
        .map(widgetLabel)
        .where((s) => s.isNotEmpty)
        .join(' ');
  }
  return '';
}

String? sfSymbol(Widget? icon) {
  final data = icon is Icon ? icon.icon : null;
  return switch (data) {
    m.Icons.more_horiz || m.Icons.more_vert => 'ellipsis',
    m.Icons.location_on_outlined => 'location',
    m.Icons.assignment_outlined => 'checklist',
    m.Icons.file_upload_outlined => 'square.and.arrow.up',
    m.Icons.add || m.Icons.add_rounded => 'plus',
    m.Icons.grid_view_rounded => 'calendar',
    m.Icons.refresh => 'arrow.clockwise',
    m.Icons.link => 'link',
    m.Icons.fit_screen_outlined => 'arrow.up.left.and.arrow.down.right',
    m.Icons.arrow_back || m.Icons.chevron_left => 'chevron.left',
    m.Icons.chevron_right => 'chevron.right',
    m.Icons.close => 'xmark',
    m.Icons.check || m.Icons.done => 'checkmark',
    m.Icons.edit_outlined || m.Icons.edit => 'pencil',
    m.Icons.delete_outline || m.Icons.delete_outline_rounded => 'trash',
    m.Icons.palette_outlined => 'paintpalette',
    m.Icons.save_outlined || m.Icons.save => 'square.and.arrow.down',
    _ => null,
  };
}

class NativeUIControl extends StatefulWidget {
  const NativeUIControl({
    super.key,
    required this.configuration,
    required this.onAction,
  });
  final Map<String, Object?> configuration;
  final ValueChanged<String> onAction;
  @override
  State<NativeUIControl> createState() => _NativeUIControlState();
}

class _NativeUIControlState extends State<NativeUIControl> {
  MethodChannel? _channel;
  String? _sent;
  Map<String, Object?> _configuration(BuildContext context) => {
    ...widget.configuration,
    'dark': m.Theme.of(context).brightness == Brightness.dark,
    'tint': CupertinoTheme.of(context).primaryColor.toARGB32(),
  };

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  void _update(Map<String, Object?> data) {
    final encoded = jsonEncode(data);
    if (_channel != null && encoded != _sent) {
      _sent = encoded;
      _channel!.invokeMethod<void>('update', data);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _configuration(context);
    _update(data);
    return UiKitView(
      viewType: 'offline_course_schedule/native_ui',
      creationParams: data,
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: (id) {
        if (!mounted) return;
        _channel = MethodChannel('offline_course_schedule/native_ui/$id');
        _channel!.setMethodCallHandler((call) async {
          if (mounted && call.method == 'action') {
            widget.onAction(call.arguments as String);
          }
        });
        _sent = jsonEncode(data);
        _update(_configuration(context));
      },
    );
  }
}
