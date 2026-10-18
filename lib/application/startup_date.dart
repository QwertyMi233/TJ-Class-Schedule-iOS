import '../domain/schedule_engine.dart';

/// App 启动时要不要把选中日期自动挪到「第二天」。
///
/// 只判断今天一天：今天有安排，且全部安排的结束边界不晚于 [now]（也就是今天的
/// 课都上完了）时返回明天；否则返回 null，表示保持当前选中的日期不变。
///
/// 几个刻意的保守选择：
/// - 今天没有任何安排时不跳转（学期外的日期、节假日、本来就没课的一天都算），
///   避免在「本来就没课」的日子把界面从今天挪走；
/// - 「第二天」就是字面上的下一天，不跳过周末，也不顺延到下一个有课的日子，
///   哪怕那天同样没课也照常显示。
///
/// 只应在 App 启动时调用一次。调用方不要把结果反复写回选中日期，否则用户手动滑到
/// 别处后会被抢回。
DateTime? startupSelectedDate(ScheduleEngine engine, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final entries = engine.getEntriesForDate(today);
  if (entries.isEmpty) return null;
  // 开始时间最晚的安排不一定最晚结束，重叠事件也需要一起检查。
  if (entries.any((entry) => entry.endTime.isAfter(now))) return null;
  return DateTime(today.year, today.month, today.day + 1);
}
