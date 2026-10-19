import '../domain/schedule_engine.dart';

/// 启动时，今天有安排且已全部结束就选中明天，否则返回 null。
/// 明天按自然日计算，不跳过无课日；只在启动时调用，避免覆盖用户的日期选择。
DateTime? startupSelectedDate(ScheduleEngine engine, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final entries = engine.getEntriesForDate(today);
  if (entries.isEmpty) return null;
  // 开始时间最晚的安排不一定最晚结束，重叠事件也需要一起检查。
  if (entries.any((entry) => entry.endTime.isAfter(now))) return null;
  return DateTime(today.year, today.month, today.day + 1);
}
