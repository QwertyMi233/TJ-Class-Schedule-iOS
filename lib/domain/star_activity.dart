import 'dart:convert';

import 'schedule_models.dart';

/// 平台时间以绝对时间保存，显示时固定使用活动所在地的北京时间。
class StarActivity {
  const StarActivity({
    required this.ticketId,
    required this.title,
    required this.location,
    required this.start,
    required this.end,
    this.completed = false,
  });

  final String ticketId;
  final String title;
  final String location;
  final DateTime start;
  final DateTime end;
  final bool completed;

  factory StarActivity.fromTicket(Map<String, dynamic> ticket) {
    final activity = ticket['activity'] is Map
        ? ticket['activity'] as Map
        : const {};
    final schedule = ticket['schedule'] is Map
        ? ticket['schedule'] as Map
        : const {};
    final id = '${ticket['id'] ?? ''}';
    var title = '${activity['title'] ?? ''}'.trim();
    var start = _timestamp(
      schedule['activityStartTime'] ?? activity['activityStartTime'],
    );
    var end = _timestamp(
      schedule['activityEndTime'] ?? activity['activityEndTime'],
    );
    // 系列活动只有总周期；按用户选择，使用其报名场次的签到窗口并明确标注。
    if (schedule['activityStartTime'] == null &&
        start != null &&
        end != null &&
        end.difference(start) > const Duration(days: 1)) {
      final signStart = _timestamp(schedule['signInStartTime']);
      final signEnd = _timestamp(schedule['signInEndTime']);
      if (signStart != null && signEnd != null && signEnd.isAfter(signStart)) {
        start = signStart;
        end = signEnd;
        final subtitle = '${schedule['title'] ?? ''}'.trim();
        if (subtitle.isNotEmpty && subtitle != title) {
          title = '$title · $subtitle';
        }
        title = '$title（签到时段）';
      }
    }
    if (id.isEmpty ||
        title.isEmpty ||
        start == null ||
        end == null ||
        !end.isAfter(start)) {
      throw const FormatException('入场券缺少编号、名称或有效起止时间');
    }
    return StarActivity(
      ticketId: id,
      title: title,
      location: '${schedule['addr'] ?? activity['addr'] ?? ''}'.trim().isEmpty
          ? '地点待公布'
          : '${schedule['addr'] ?? activity['addr']}'.trim(),
      start: start,
      end: end,
      completed: ticket['signInStatus'] == 2,
    );
  }

  static String accountPrefix(String account) =>
      'star:${base64Url.encode(utf8.encode(account))}:';

  String memoPrefix(String account) =>
      '${accountPrefix(account)}${Uri.encodeComponent(ticketId)}:';

  List<Memo> toMemos(String account) {
    final localStart = start.toUtc().add(const Duration(hours: 8));
    final localEnd = end.toUtc().add(const Duration(hours: 8));
    final result = <Memo>[];
    var day = DateTime.utc(localStart.year, localStart.month, localStart.day);
    while (day.isBefore(localEnd)) {
      final next = day.add(const Duration(days: 1));
      final from = localStart.isAfter(day)
          ? localStart.difference(day).inMinutes
          : 0;
      final to = localEnd.isBefore(next)
          ? (localEnd.difference(day).inSeconds / 60).ceil()
          : 1440;
      result.add(
        Memo(
          id: '${memoPrefix(account)}${day.toIso8601String().substring(0, 10)}',
          title: title,
          location: location,
          colorValue: 0xFFB09ACB,
          source: 'star',
          date: DateTime(day.year, day.month, day.day),
          startMinutes: from,
          endMinutes: to,
        ),
      );
      day = next;
    }
    return result;
  }
}

DateTime? _timestamp(Object? value) {
  final milliseconds = value is num ? value.toInt() : int.tryParse('$value');
  if (milliseconds == null || milliseconds <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
}
