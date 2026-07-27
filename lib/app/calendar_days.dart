/// 「日历日」算术：跨夏令时（DST）也稳定的天数差与按天推进。
///
/// **为什么不能直接用 `Duration`**：`DateTime.difference` / `DateTime.add` 算的是
/// **绝对时间**，而夏令时地区的某一天可能只有 23 小时或长达 25 小时：
/// - `end.difference(start).inDays` 跨过「春季拨快」会**少算一天**
///   （America/Los_Angeles 的 2026-03-01 → 03-10 实际只隔 8 小时 23 分不足 9 天，得 8）；
/// - `date.add(const Duration(days: 1))` 跨过切换日会偏移一小时，落到相邻日的
///   23:00 或 01:00——用作「次日零点」这类边界时，会连带多算/漏掉一小时内的交易。
///
/// 这些偏差在无夏令时的地区（含中国）与 UTC 下都不显现，因此 CI 恒绿、只在
/// 欧美时区的开发机或用户手机上暴露。本模块的两个函数在**任何本地时区下结果一致**，
/// 新增日期算术一律走它们，不要再裸用 `Duration(days:)`。
library;

/// [from] 到 [to] 相隔的**日历天数**（[to] 更晚为正），忽略两者的时分秒。
///
/// 经 UTC 构造再相减：UTC 没有夏令时，每天恒为 24 小时，故结果只取决于两个
/// 日历日期本身。
int calendarDaysBetween(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

/// 在 [date] 上推进 [days] 个**日历日**（可为负），保留其一天内的时刻。
///
/// 走 `DateTime` 构造函数的日期溢出规则（`day` 超出当月天数会自动进位到下月），
/// 按本地日历推进，因此跨夏令时切换也恒好落在目标日的同一时刻。
DateTime addCalendarDays(DateTime date, int days) {
  return DateTime(
    date.year,
    date.month,
    date.day + days,
    date.hour,
    date.minute,
    date.second,
    date.millisecond,
    date.microsecond,
  );
}
