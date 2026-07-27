import 'dart:convert';

/// 记账提醒配置：是否开启 + 每日提醒的时分。存 KV（`verifin.reminder.v1`），
/// 不进 JSON 备份（设备本地偏好）。
class ReminderSettings {
  const ReminderSettings({
    this.enabled = false,
    this.hour = 21,
    this.minute = 0,
  });

  /// 是否开启每日记账提醒。
  final bool enabled;

  /// 提醒时刻（24 小时制）。
  final int hour;
  final int minute;

  static const ReminderSettings disabled = ReminderSettings();

  ReminderSettings copyWith({bool? enabled, int? hour, int? minute}) {
    return ReminderSettings(
      enabled: enabled ?? this.enabled,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
    );
  }

  /// 展示用的 `HH:mm` 文案。
  String get timeLabel =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// 从 [from] 起下一次触发时刻：今天该时刻若已过则顺延到明天。
  ///
  /// 顺延按「日历日 +1」构造而非 `add(Duration(days: 1))`——后者是绝对 24 小时，
  /// 跨夏令时切换会把提醒推到次日的 hour±1，用户设 21:00 却在 20:00/22:00 响。
  DateTime nextFireTime(DateTime from) {
    final candidate = DateTime(from.year, from.month, from.day, hour, minute);
    if (candidate.isAfter(from)) {
      return candidate;
    }
    return DateTime(from.year, from.month, from.day + 1, hour, minute);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'enabled': enabled,
    'hour': hour,
    'minute': minute,
  };

  factory ReminderSettings.fromJson(Map<String, dynamic> json) {
    final rawHour = (json['hour'] as num?)?.toInt() ?? 21;
    final rawMinute = (json['minute'] as num?)?.toInt() ?? 0;
    return ReminderSettings(
      enabled: json['enabled'] as bool? ?? false,
      hour: rawHour.clamp(0, 23),
      minute: rawMinute.clamp(0, 59),
    );
  }

  String encode() => jsonEncode(toJson());

  static ReminderSettings decode(String? raw) {
    if (raw == null || raw.isEmpty) {
      return disabled;
    }
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) {
        return ReminderSettings.fromJson(json);
      }
    } catch (_) {
      // 解析失败按未开启处理。
    }
    return disabled;
  }

  @override
  bool operator ==(Object other) =>
      other is ReminderSettings &&
      other.enabled == enabled &&
      other.hour == hour &&
      other.minute == minute;

  @override
  int get hashCode => Object.hash(enabled, hour, minute);
}
