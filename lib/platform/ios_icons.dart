import 'package:flutter/cupertino.dart' as c;
import 'package:flutter/material.dart' as m;

/// Bundled glyphs: toolbar icons never depend on an incomplete SF Symbol map.
/// Unrecognised icons retain their supplied glyph instead of becoming “more”.
m.Widget iosIcon(m.Widget widget, {double? size}) {
  if (widget is! m.Icon) return widget;
  final data = switch (widget.icon) {
    m.Icons.desktop_windows_outlined => c.CupertinoIcons.desktopcomputer,
    m.Icons.phone_android_outlined => c.CupertinoIcons.device_phone_portrait,
    m.Icons.refresh || m.Icons.refresh_rounded => c.CupertinoIcons.arrow_clockwise,
    m.Icons.logout => c.CupertinoIcons.square_arrow_right,
    m.Icons.login => c.CupertinoIcons.square_arrow_left,
    m.Icons.location_on_outlined => c.CupertinoIcons.location,
    m.Icons.assignment_outlined => c.CupertinoIcons.list_bullet,
    m.Icons.file_upload || m.Icons.file_upload_outlined ||
    m.Icons.upload_file_outlined => c.CupertinoIcons.arrow_up_doc,
    m.Icons.download || m.Icons.save || m.Icons.save_outlined ||
    m.Icons.save_alt_rounded => c.CupertinoIcons.arrow_down_doc,
    m.Icons.add || m.Icons.add_rounded => c.CupertinoIcons.plus,
    m.Icons.grid_view_rounded => c.CupertinoIcons.square_grid_2x2,
    m.Icons.link => c.CupertinoIcons.link,
    m.Icons.fit_screen_outlined => c.CupertinoIcons.arrow_up_left_arrow_down_right,
    m.Icons.arrow_back || m.Icons.chevron_left => c.CupertinoIcons.chevron_left,
    m.Icons.chevron_right || m.Icons.chevron_right_rounded => c.CupertinoIcons.chevron_right,
    m.Icons.close || m.Icons.clear => c.CupertinoIcons.xmark,
    m.Icons.check || m.Icons.check_rounded || m.Icons.done ||
    m.Icons.done_rounded => c.CupertinoIcons.check_mark,
    m.Icons.edit_outlined || m.Icons.edit => c.CupertinoIcons.pencil,
    m.Icons.delete_outline || m.Icons.delete_outline_rounded => c.CupertinoIcons.trash,
    m.Icons.palette_outlined => c.CupertinoIcons.paintbrush,
    m.Icons.table_view_rounded => c.CupertinoIcons.table,
    m.Icons.settings_outlined => c.CupertinoIcons.gear,
    m.Icons.help_outline => c.CupertinoIcons.question_circle,
    m.Icons.info_outline => c.CupertinoIcons.info_circle,
    m.Icons.visibility_outlined => c.CupertinoIcons.eye,
    m.Icons.visibility_off_outlined => c.CupertinoIcons.eye_slash,
    m.Icons.search => c.CupertinoIcons.search,
    m.Icons.sort => c.CupertinoIcons.arrow_up_arrow_down,
    m.Icons.sync => c.CupertinoIcons.arrow_2_circlepath,
    m.Icons.folder_open => c.CupertinoIcons.folder,
    m.Icons.open_in_new => c.CupertinoIcons.arrow_up_right_square,
    m.Icons.more_horiz || m.Icons.more_vert => c.CupertinoIcons.ellipsis,
    _ => widget.icon,
  };
  return m.Icon(
    data,
    key: widget.key,
    size: size ?? widget.size,
    color: widget.color,
    semanticLabel: widget.semanticLabel,
    textDirection: widget.textDirection,
  );
}
