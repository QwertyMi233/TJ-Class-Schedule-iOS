/// Platform presentation boundary. Data/services are shared; iOS controls and
/// routes use Cupertino or actual UIKit instead of Material surfaces.
// ignore_for_file: curly_braces_in_flow_control_structures, use_super_parameters, no_logic_in_create_state
library;

import 'dart:math' as math;
import 'package:flutter/cupertino.dart' as c;
import 'package:flutter/material.dart' as m;
import 'package:flutter/services.dart';
import 'native_ui.dart';
import 'platform_support.dart';

export 'package:flutter/material.dart'
    hide
        AppBar,
        IconButton,
        FilledButton,
        OutlinedButton,
        TextButton,
        FloatingActionButton,
        PopupMenuButton,
        TextField,
        TextFormField,
        TabBar,
        AlertDialog,
        SegmentedButton,
        DropdownButtonFormField,
        DropdownButton,
        ChoiceChip,
        FilterChip,
        showDialog,
        showModalBottomSheet,
        showDatePicker,
        showTimePicker;

class AppBar extends m.StatelessWidget implements m.PreferredSizeWidget {
  const AppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.bottom,
    this.backgroundColor,
    this.surfaceTintColor,
    this.elevation,
    this.scrolledUnderElevation,
    this.centerTitle,
    this.automaticallyImplyLeading = true,
  });
  final m.Widget? title, leading;
  final List<m.Widget>? actions;
  final m.PreferredSizeWidget? bottom;
  final m.Color? backgroundColor, surfaceTintColor;
  final double? elevation, scrolledUnderElevation;
  final bool automaticallyImplyLeading;
  final bool? centerTitle;
  @override
  m.Size get preferredSize => m.Size.fromHeight(
    (isIOSDevice ? 44 : m.kToolbarHeight) + (bottom?.preferredSize.height ?? 0),
  );
  @override
  m.Widget build(m.BuildContext context) {
    if (!isIOSDevice)
      return m.AppBar(
        title: title,
        actions: actions,
        leading: leading,
        bottom: bottom,
        backgroundColor: backgroundColor,
        surfaceTintColor: surfaceTintColor,
        elevation: elevation,
        scrolledUnderElevation: scrolledUnderElevation,
        centerTitle: centerTitle,
        automaticallyImplyLeading: automaticallyImplyLeading,
      );
    final callbacks = <String, m.VoidCallback>{};
    final rows = <Map<String, Object?>>[];
    for (final (index, widget) in (actions ?? <m.Widget>[]).indexed) {
      final row = _navigationAction(context, widget, '$index', callbacks);
      if (row != null) rows.add(row);
    }
    final back = automaticallyImplyLeading && m.Navigator.canPop(context);
    callbacks['back'] = () => m.Navigator.maybePop(context);
    final bar = canHostNativeUI && leading == null && title is m.Text
        ? NativeUIControl(
            configuration: {
              'kind': 'navigation',
              'title': widgetLabel(title),
              'back': back,
              'actions': rows,
            },
            onAction: (id) => callbacks[id]?.call(),
          )
        : c.CupertinoNavigationBar(
            middle: title,
            leading: leading,
            automaticallyImplyLeading: automaticallyImplyLeading,
            border: null,
            backgroundColor: c.CupertinoColors.systemBackground
                .resolveFrom(context)
                .withValues(alpha: .88),
            trailing: actions == null
                ? null
                : m.Row(mainAxisSize: m.MainAxisSize.min, children: actions!),
          );
    return m.DecoratedBox(
      decoration: m.BoxDecoration(
        color:
            backgroundColor ??
            c.CupertinoColors.systemGroupedBackground.resolveFrom(context),
      ),
      child: m.Column(
        mainAxisSize: m.MainAxisSize.min,
        children: [
          if (canHostNativeUI && leading == null && title is m.Text)
            m.SafeArea(bottom: false, child: m.SizedBox(height: 44, child: bar))
          else
            bar,
          if (bottom != null) bottom!,
        ],
      ),
    );
  }
}

Map<String, Object?>? _navigationAction(
  m.BuildContext context,
  m.Widget widget,
  String id,
  Map<String, m.VoidCallback> callbacks,
) {
  if (widget is m.IconButton) {
    if (widget.onPressed != null) callbacks[id] = widget.onPressed!;
    return {
      'id': id,
      'title': widget.tooltip ?? '',
      'symbol': sfSymbol(widget.icon),
      'enabled': widget.onPressed != null,
    };
  }
  if (widget is m.ButtonStyleButton) {
    if (widget.onPressed != null) callbacks[id] = widget.onPressed!;
    return {
      'id': id,
      'title': widgetLabel(widget.child),
      'enabled': widget.onPressed != null,
    };
  }
  if (widget is PopupMenuButton) {
    return {
      'id': id,
      'title': widget.tooltip ?? '更多',
      'symbol': 'ellipsis',
      'menu': widget.menu(context, id, callbacks),
    };
  }
  return null;
}

class IconButton extends m.IconButton {
  const IconButton({
    super.key,
    required super.icon,
    required super.onPressed,
    super.tooltip,
    super.iconSize,
    super.color,
    super.padding,
    super.constraints,
    super.style,
    super.visualDensity,
  });
  static m.ButtonStyle styleFrom({m.Color? backgroundColor}) =>
      m.IconButton.styleFrom(backgroundColor: backgroundColor);
  @override
  m.Widget build(m.BuildContext context) => !isIOSDevice
      ? super.build(context)
      : m.Semantics(
          label: tooltip,
          button: true,
          enabled: onPressed != null,
          child: c.CupertinoButton(
            padding: padding ?? const m.EdgeInsets.all(8),
            minimumSize: const m.Size(40, 40),
            onPressed: onPressed,
            child: m.IconTheme(
              data: m.IconThemeData(
                size: iconSize ?? 23,
                color: color ?? c.CupertinoTheme.of(context).primaryColor,
              ),
              child: icon,
            ),
          ),
        );
}

m.Widget _iosButton(
  m.BuildContext context,
  m.ButtonStyleButton button, {
  bool filled = false,
}) {
  if (context.findAncestorWidgetOfExactType<c.CupertinoAlertDialog>() != null) {
    return c.CupertinoDialogAction(
      onPressed: button.onPressed,
      isDefaultAction: filled,
      child: button.child ?? const m.SizedBox(),
    );
  }
  final child = button.child ?? const m.SizedBox();
  return filled
      ? c.CupertinoButton.filled(
          onPressed: button.onPressed,
          padding: const m.EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: child,
        )
      : c.CupertinoButton(
          onPressed: button.onPressed,
          padding: const m.EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: child,
        );
}

m.Widget _buttonLabel(m.Widget icon, m.Widget label) => m.Row(
  mainAxisSize: m.MainAxisSize.min,
  children: [
    icon,
    const m.SizedBox(width: 6),
    m.Flexible(child: label),
  ],
);

class FilledButton extends m.FilledButton {
  const FilledButton({
    super.key,
    required super.onPressed,
    required super.child,
    super.style,
  });
  const FilledButton.tonal({
    super.key,
    required super.onPressed,
    required super.child,
    super.style,
  }) : super.tonal();
  FilledButton.icon({
    super.key,
    required super.onPressed,
    required m.Widget icon,
    required m.Widget label,
    super.style,
  }) : super(child: _buttonLabel(icon, label));
  @override
  m.State<m.ButtonStyleButton> createState() => _IOSButtonState(filled: true);
}

class OutlinedButton extends m.OutlinedButton {
  const OutlinedButton({
    super.key,
    required super.onPressed,
    required super.child,
    super.style,
  });
  OutlinedButton.icon({
    super.key,
    required super.onPressed,
    required m.Widget icon,
    required m.Widget label,
    super.style,
  }) : super(child: _buttonLabel(icon, label));
  @override
  m.State<m.ButtonStyleButton> createState() => _IOSButtonState();
}

class TextButton extends m.TextButton {
  const TextButton({
    super.key,
    required super.onPressed,
    required super.child,
    super.style,
  });
  TextButton.icon({
    super.key,
    required super.onPressed,
    required m.Widget icon,
    required m.Widget label,
    super.style,
  }) : super(child: _buttonLabel(icon, label));
  @override
  m.State<m.ButtonStyleButton> createState() => _IOSButtonState();
}

class _IOSButtonState extends m.State<m.ButtonStyleButton> {
  _IOSButtonState({this.filled = false});
  final bool filled;
  @override
  m.Widget build(m.BuildContext context) => isIOSDevice
      ? _iosButton(context, widget, filled: filled)
      : widget is OutlinedButton
      ? m.OutlinedButton(
          onPressed: widget.onPressed,
          style: widget.style,
          child: widget.child ?? const m.SizedBox(),
        )
      : widget is TextButton
      ? m.TextButton(
          onPressed: widget.onPressed,
          style: widget.style,
          child: widget.child ?? const m.SizedBox(),
        )
      : m.FilledButton(
          onPressed: widget.onPressed,
          style: widget.style,
          child: widget.child ?? const m.SizedBox(),
        );
}

class FloatingActionButton extends m.FloatingActionButton {
  const FloatingActionButton.extended({
    super.key,
    required super.onPressed,
    super.heroTag,
    required m.Widget label,
    m.Widget? icon,
  }) : nativeLabel = label,
       nativeIcon = icon,
       super.extended(label: label, icon: icon);
  final m.Widget nativeLabel;
  final m.Widget? nativeIcon;
  @override
  m.Widget build(m.BuildContext context) {
    if (!isIOSDevice)
      return m.FloatingActionButton.extended(
        onPressed: onPressed,
        heroTag: heroTag,
        label: nativeLabel,
        icon: nativeIcon,
      );
    // The material superclass stores extended content in child; retain its label.
    final title = widgetLabel(nativeLabel);
    final icon = nativeIcon;
    final painter = m.TextPainter(
      text: m.TextSpan(text: title, style: const m.TextStyle(fontSize: 17)),
      textDirection: m.TextDirection.ltr,
      textScaler: m.MediaQuery.textScalerOf(context),
    )..layout();
    final width = math.min(
      (m.MediaQuery.sizeOf(context).width - 48) / 2,
      math.max(112.0, painter.width + 64),
    );
    painter.layout(maxWidth: math.max(40, width - 56));
    return m.SizedBox(
      width: width,
      height: math.max(52, painter.height + 24),
      child: canHostNativeUI
          ? NativeUIControl(
              configuration: {
                'kind': 'button',
                'title': title,
                'symbol': sfSymbol(icon),
                'prominent': false,
                'enabled': onPressed != null,
              },
              onAction: (_) => onPressed?.call(),
            )
          : c.CupertinoButton.filled(
              onPressed: onPressed,
              borderRadius: m.BorderRadius.circular(30),
              padding: const m.EdgeInsets.symmetric(horizontal: 12),
              child: m.Text(title),
            ),
    );
  }
}

class PopupMenuButton<T> extends m.StatelessWidget {
  const PopupMenuButton({
    super.key,
    required this.itemBuilder,
    this.onSelected,
    this.icon,
    this.tooltip,
    this.enabled = true,
    this.child,
  });
  final m.PopupMenuItemBuilder<T> itemBuilder;
  final m.PopupMenuItemSelected<T>? onSelected;
  final m.Widget? icon, child;
  final String? tooltip;
  final bool enabled;
  List<Map<String, Object?>> menu(
    m.BuildContext context,
    String prefix,
    Map<String, m.VoidCallback> callbacks,
  ) {
    final rows = <Map<String, Object?>>[];
    for (final (index, entry) in itemBuilder(context).indexed) {
      if (entry is! m.PopupMenuItem<T>) continue;
      final id = '$prefix:$index';
      callbacks[id] = () {
        entry.onTap?.call();
        if (entry.value != null) onSelected?.call(entry.value as T);
      };
      final label = widgetLabel(entry.child);
      rows.add({
        'id': id,
        'title': label,
        'enabled': entry.enabled,
        'destructive': label.startsWith('删除') || label.startsWith('撤销'),
      });
    }
    return rows;
  }

  @override
  m.Widget build(m.BuildContext context) {
    if (!isIOSDevice)
      return m.PopupMenuButton<T>(
        itemBuilder: itemBuilder,
        onSelected: onSelected,
        icon: icon,
        tooltip: tooltip,
        enabled: enabled,
        child: child,
      );
    final callbacks = <String, m.VoidCallback>{};
    final rows = menu(context, 'menu', callbacks);
    if (canHostNativeUI)
      return m.SizedBox(
        width: 44,
        height: 44,
        child: NativeUIControl(
          configuration: {
            'kind': 'menu',
            'symbol': 'ellipsis',
            'label': tooltip ?? '更多',
            'menu': rows,
            'enabled': enabled,
          },
          onAction: (id) => callbacks[id]?.call(),
        ),
      );
    return c.CupertinoButton(
      padding: const m.EdgeInsets.all(8),
      onPressed: !enabled
          ? null
          : () => c.showCupertinoModalPopup<void>(
              context: context,
              builder: (sheet) => c.CupertinoActionSheet(
                actions: rows
                    .map(
                      (row) => c.CupertinoActionSheetAction(
                        isDestructiveAction: row['destructive'] == true,
                        onPressed: () {
                          m.Navigator.pop(sheet);
                          callbacks[row['id']]?.call();
                        },
                        child: m.Text(row['title'] as String),
                      ),
                    )
                    .toList(),
                cancelButton: c.CupertinoActionSheetAction(
                  onPressed: () => m.Navigator.pop(sheet),
                  child: const m.Text('取消'),
                ),
              ),
            ),
      child: icon ?? const m.Icon(c.CupertinoIcons.ellipsis),
    );
  }
}

class TabBar extends m.StatefulWidget implements m.PreferredSizeWidget {
  const TabBar({super.key, required this.tabs});
  final List<m.Widget> tabs;
  @override
  m.Size get preferredSize => m.Size.fromHeight(isIOSDevice ? 48 : 48);
  @override
  m.State<TabBar> createState() => _TabBarState();
}

class _TabBarState extends m.State<TabBar> {
  @override
  m.Widget build(m.BuildContext context) {
    if (!isIOSDevice) return m.TabBar(tabs: widget.tabs);
    final controller = m.DefaultTabController.of(context);
    return m.AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final labels = widget.tabs
            .map((t) => t is m.Tab ? t.text ?? '' : widgetLabel(t))
            .toList();
        return m.Padding(
          padding: const m.EdgeInsets.fromLTRB(18, 3, 18, 5),
          child: m.Center(
            child: m.SizedBox(
              width: 320,
              height: 40,
              child: canHostNativeUI
                  ? NativeUIControl(
                      configuration: {
                        'kind': 'segmented',
                        'titles': labels,
                        'selected': controller.index,
                      },
                      onAction: (id) {
                        final index = int.tryParse(id);
                        if (index != null &&
                            index >= 0 &&
                            index < labels.length)
                          controller.animateTo(index);
                      },
                    )
                  : c.CupertinoSlidingSegmentedControl<int>(
                      groupValue: controller.index,
                      children: {
                        for (var i = 0; i < labels.length; i++)
                          i: m.Padding(
                            padding: const m.EdgeInsets.symmetric(
                              horizontal: 20,
                            ),
                            child: m.Text(labels[i]),
                          ),
                      },
                      onValueChanged: (index) {
                        if (index != null) controller.animateTo(index);
                      },
                    ),
            ),
          ),
        );
      },
    );
  }
}

class AlertDialog extends m.StatelessWidget {
  const AlertDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.scrollable = false,
  });
  final m.Widget? title, content;
  final List<m.Widget>? actions;
  final bool scrollable;
  @override
  m.Widget build(m.BuildContext context) => isIOSDevice
      ? c.CupertinoAlertDialog(
          title: title,
          content: content,
          actions: actions ?? [],
        )
      : m.AlertDialog(
          title: title,
          content: content,
          actions: actions,
          scrollable: scrollable,
        );
}

class TextField extends m.StatelessWidget {
  const TextField({
    super.key,
    this.controller,
    this.focusNode,
    this.decoration = const m.InputDecoration(),
    this.keyboardType,
    this.obscureText = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.autofocus = false,
    this.enabled,
    this.readOnly = false,
    this.maxLength,
    this.maxLines = 1,
    this.minLines,
    this.onChanged,
    this.onSubmitted,
    this.inputFormatters,
    this.textInputAction,
    this.autofillHints,
  });
  final m.TextEditingController? controller;
  final m.FocusNode? focusNode;
  final m.InputDecoration? decoration;
  final m.TextInputType? keyboardType;
  final bool obscureText, autocorrect, enableSuggestions, autofocus, readOnly;
  final bool? enabled;
  final int? maxLength, maxLines, minLines;
  final m.ValueChanged<String>? onChanged, onSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final m.TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  @override
  m.Widget build(m.BuildContext context) {
    if (!isIOSDevice)
      return m.TextField(
        controller: controller,
        focusNode: focusNode,
        decoration: decoration,
        keyboardType: keyboardType,
        obscureText: obscureText,
        autocorrect: autocorrect,
        enableSuggestions: enableSuggestions,
        autofocus: autofocus,
        enabled: enabled,
        readOnly: readOnly,
        maxLength: maxLength,
        maxLines: maxLines,
        minLines: minLines,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        inputFormatters: inputFormatters,
        textInputAction: textInputAction,
        autofillHints: autofillHints,
      );
    return m.Column(
      crossAxisAlignment: m.CrossAxisAlignment.start,
      mainAxisSize: m.MainAxisSize.min,
      children: [
        if (decoration?.labelText != null)
          m.Padding(
            padding: const m.EdgeInsets.only(left: 4, bottom: 6),
            child: m.Text(
              decoration!.labelText!,
              style: const m.TextStyle(fontSize: 14),
            ),
          ),
        c.CupertinoTextField(
          controller: controller,
          focusNode: focusNode,
          placeholder: decoration?.hintText,
          keyboardType: keyboardType,
          obscureText: obscureText,
          autocorrect: autocorrect,
          enableSuggestions: enableSuggestions,
          autofocus: autofocus,
          enabled: enabled ?? true,
          readOnly: readOnly,
          maxLength: maxLength,
          maxLines: maxLines,
          minLines: minLines,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          inputFormatters: inputFormatters,
          textInputAction: textInputAction,
          autofillHints: autofillHints,
          prefix: decoration?.prefixIcon,
          suffix: decoration?.suffixIcon,
          padding: const m.EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: m.BoxDecoration(
            color: c.CupertinoColors.tertiarySystemFill.resolveFrom(context),
            borderRadius: m.BorderRadius.circular(12),
          ),
        ),
        if (decoration?.helperText != null)
          m.Text(
            decoration!.helperText!,
            style: m.Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}

class SegmentedButton<T extends Object> extends m.StatelessWidget {
  const SegmentedButton({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
    this.showSelectedIcon = true,
  });
  final bool showSelectedIcon;
  final List<m.ButtonSegment<T>> segments;
  final Set<T> selected;
  final m.ValueChanged<Set<T>>? onSelectionChanged;
  @override
  m.Widget build(m.BuildContext context) => !isIOSDevice
      ? m.SegmentedButton<T>(
          segments: segments,
          selected: selected,
          onSelectionChanged: onSelectionChanged,
          showSelectedIcon: showSelectedIcon,
        )
      : c.CupertinoSlidingSegmentedControl<T>(
          groupValue: selected.firstOrNull,
          children: {
            for (final s in segments)
              s.value: s.label ?? s.icon ?? const m.SizedBox(),
          },
          onValueChanged: (value) {
            if (value != null) onSelectionChanged?.call({value});
          },
        );
}

class DropdownButtonFormField<T> extends m.StatelessWidget {
  const DropdownButtonFormField({
    super.key,
    this.initialValue,
    required this.items,
    required this.onChanged,
    this.decoration = const m.InputDecoration(),
    this.isExpanded = false,
  });
  final T? initialValue;
  final List<m.DropdownMenuItem<T>>? items;
  final m.ValueChanged<T?>? onChanged;
  final m.InputDecoration decoration;
  final bool isExpanded;
  @override
  m.Widget build(m.BuildContext context) => !isIOSDevice
      ? m.DropdownButtonFormField<T>(
          initialValue: initialValue,
          items: items,
          onChanged: onChanged,
          decoration: decoration,
          isExpanded: isExpanded,
        )
      : _iosDropdown(
          context,
          initialValue,
          items,
          onChanged,
          decoration.labelText,
        );
}

class DropdownButton<T> extends m.StatelessWidget {
  const DropdownButton({
    super.key,
    this.value,
    required this.items,
    required this.onChanged,
    this.isExpanded = false,
    this.underline,
  });
  final T? value;
  final List<m.DropdownMenuItem<T>>? items;
  final m.ValueChanged<T?>? onChanged;
  final bool isExpanded;
  final m.Widget? underline;
  @override
  m.Widget build(m.BuildContext context) => !isIOSDevice
      ? m.DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          isExpanded: isExpanded,
          underline: underline,
        )
      : _iosDropdown(context, value, items, onChanged, null);
}

m.Widget _iosDropdown<T>(
  m.BuildContext context,
  T? value,
  List<m.DropdownMenuItem<T>>? items,
  m.ValueChanged<T?>? changed,
  String? title,
) {
  final selected = items?.where((item) => item.value == value).firstOrNull;
  return c.CupertinoButton(
    padding: const m.EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    onPressed: changed == null
        ? null
        : () => c.showCupertinoModalPopup<void>(
            context: context,
            builder: (sheet) => c.CupertinoActionSheet(
              title: title == null ? null : m.Text(title),
              actions: (items ?? [])
                  .map(
                    (item) => c.CupertinoActionSheetAction(
                      onPressed: () {
                        m.Navigator.pop(sheet);
                        changed(item.value);
                      },
                      child: item.child,
                    ),
                  )
                  .toList(),
              cancelButton: c.CupertinoActionSheetAction(
                onPressed: () => m.Navigator.pop(sheet),
                child: const m.Text('取消'),
              ),
            ),
          ),
    child: m.Row(
      mainAxisSize: m.MainAxisSize.min,
      children: [
        if (title != null) ...[m.Text(title), const m.SizedBox(width: 10)],
        m.Flexible(child: selected?.child ?? const m.Text('请选择')),
        const m.SizedBox(width: 6),
        const m.Icon(c.CupertinoIcons.chevron_down, size: 14),
      ],
    ),
  );
}

Future<T?> showDialog<T>({
  required m.BuildContext context,
  required m.WidgetBuilder builder,
  bool? barrierDismissible,
  bool useRootNavigator = true,
}) => m.showAdaptiveDialog<T>(
  context: context,
  builder: builder,
  barrierDismissible: barrierDismissible ?? !isIOSDevice,
  useRootNavigator: useRootNavigator,
);

Future<T?> showModalBottomSheet<T>({
  required m.BuildContext context,
  required m.WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  bool showDragHandle = true,
  m.Color? backgroundColor,
  m.ShapeBorder? shape,
}) {
  if (!isIOSDevice)
    return m.showModalBottomSheet<T>(
      context: context,
      builder: builder,
      isScrollControlled: isScrollControlled,
      useSafeArea: useSafeArea,
      showDragHandle: showDragHandle,
      backgroundColor: backgroundColor,
      shape: shape,
    );
  return c.showCupertinoSheet<T>(
    context: context,
    scrollableBuilder: (sheet, controller) => m.Material(
      type: m.MaterialType.transparency,
      child: c.CupertinoPageScaffold(
        child: m.SafeArea(
          top: false,
          child: m.Column(
            children: [
              m.Align(
                alignment: m.Alignment.centerRight,
                child: c.CupertinoButton(
                  onPressed: () => m.Navigator.pop(sheet),
                  child: const m.Text('完成'),
                ),
              ),
              m.Expanded(
                child: m.MediaQuery.removePadding(
                  context: sheet,
                  removeTop: true,
                  child: builder(sheet),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<DateTime?> showDatePicker({
  required m.BuildContext context,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTime? initialDate,
  String? helpText,
}) {
  if (!isIOSDevice)
    return m.showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
  var value = initialDate ?? DateTime.now();
  return _picker<DateTime>(
    context,
    (sheet) => c.CupertinoDatePicker(
      mode: c.CupertinoDatePickerMode.date,
      initialDateTime: value,
      minimumDate: firstDate,
      maximumDate: lastDate,
      onDateTimeChanged: (date) => value = date,
    ),
    () => value,
  );
}

Future<m.TimeOfDay?> showTimePicker({
  required m.BuildContext context,
  required m.TimeOfDay initialTime,
  String? helpText,
}) {
  if (!isIOSDevice)
    return m.showTimePicker(context: context, initialTime: initialTime);
  var value = DateTime(2000, 1, 1, initialTime.hour, initialTime.minute);
  return _picker<m.TimeOfDay>(
    context,
    (sheet) => c.CupertinoDatePicker(
      mode: c.CupertinoDatePickerMode.time,
      initialDateTime: value,
      use24hFormat: true,
      onDateTimeChanged: (date) => value = date,
    ),
    () => m.TimeOfDay.fromDateTime(value),
  );
}

Future<T?> _picker<T>(
  m.BuildContext context,
  m.WidgetBuilder picker,
  T Function() value,
) => c.showCupertinoModalPopup<T>(
  context: context,
  builder: (sheet) => c.CupertinoPopupSurface(
    child: m.SafeArea(
      top: false,
      child: m.SizedBox(
        height: 300,
        child: m.Column(
          children: [
            m.Row(
              mainAxisAlignment: m.MainAxisAlignment.spaceBetween,
              children: [
                c.CupertinoButton(
                  onPressed: () => m.Navigator.pop(sheet),
                  child: const m.Text('取消'),
                ),
                c.CupertinoButton(
                  onPressed: () => m.Navigator.pop(sheet, value()),
                  child: const m.Text('完成'),
                ),
              ],
            ),
            m.Expanded(child: picker(sheet)),
          ],
        ),
      ),
    ),
  ),
);

class ChoiceChip extends m.StatelessWidget {
  // Keep the stable key on the actual platform control, not the adapter.
  // ignore: use_key_in_widget_constructors
  const ChoiceChip({
    m.Key? key,
    required this.label,
    required this.selected,
    this.onSelected,
  }) : controlKey = key;
  final m.Key? controlKey;
  final m.Widget label;
  final bool selected;
  final m.ValueChanged<bool>? onSelected;
  @override
  m.Widget build(m.BuildContext context) {
    if (!isIOSDevice) {
      return this is FilterChip
          ? m.FilterChip(
              key: controlKey,
              label: label,
              selected: selected,
              onSelected: onSelected,
            )
          : m.ChoiceChip(
              key: controlKey,
              label: label,
              selected: selected,
              onSelected: onSelected,
            );
    }
    final color = c.CupertinoTheme.of(context).primaryColor;
    return m.Semantics(
      key: controlKey,
      selected: selected,
      button: true,
      child: c.CupertinoButton(
        minimumSize: const m.Size(44, 36),
        borderRadius: m.BorderRadius.circular(22),
        padding: const m.EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        color: selected
            ? color.withValues(alpha: .15)
            : c.CupertinoColors.tertiarySystemFill.resolveFrom(context),
        onPressed: onSelected == null ? null : () => onSelected!(!selected),
        child: m.DefaultTextStyle(
          style: m.TextStyle(
            fontSize: 15,
            color: selected
                ? color
                : c.CupertinoColors.label.resolveFrom(context),
          ),
          child: label,
        ),
      ),
    );
  }
}

class FilterChip extends ChoiceChip {
  const FilterChip({
    super.key,
    required super.label,
    required super.selected,
    super.onSelected,
  });
}

class TextFormField extends m.StatelessWidget {
  const TextFormField({
    super.key,
    this.initialValue,
    this.controller,
    this.decoration = const m.InputDecoration(),
    this.onChanged,
    this.keyboardType,
    this.maxLines = 1,
    this.maxLength,
    this.validator,
  });
  final String? initialValue;
  final m.TextEditingController? controller;
  final m.InputDecoration decoration;
  final m.ValueChanged<String>? onChanged;
  final m.TextInputType? keyboardType;
  final int? maxLines;
  final int? maxLength;
  final m.FormFieldValidator<String>? validator;
  @override
  m.Widget build(m.BuildContext context) => !isIOSDevice
      ? m.TextFormField(
          initialValue: initialValue,
          controller: controller,
          decoration: decoration,
          onChanged: onChanged,
          keyboardType: keyboardType,
          maxLines: maxLines,
          maxLength: maxLength,
          validator: validator,
        )
      : c.CupertinoTextFormFieldRow(
          initialValue: initialValue,
          controller: controller,
          prefix: decoration.labelText == null
              ? null
              : m.Text(decoration.labelText!),
          placeholder: decoration.hintText,
          onChanged: onChanged,
          keyboardType: keyboardType,
          maxLines: maxLines,
          maxLength: maxLength,
          validator: validator,
        );
}
