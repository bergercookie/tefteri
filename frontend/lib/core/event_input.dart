/// Reads the day, the time and the length of an event that the user types.
///
/// The day is `YYYYMMDD`; the day and time together are `YYYYMMDDTHHmm`. The
/// time is `HHmm`. The length is minutes or hours, for example `90`, `45m`,
/// `1h` or `1h30`. Every form also accepts the separators that people tend to
/// type (`2026-11-04`, `13:15`, `1:30`).
library;

import 'package:flutter/material.dart';

import 'planning_models.dart';

/// The longest event that the dialog accepts.
const Duration maxEventLength = Duration(days: 14);

final _dayAndTime =
    RegExp(r'^(\d{4})-?(\d{2})-?(\d{2})(?:[Tt ](\d{1,2}):?(\d{2}))?$');

/// A day, and a time when the text had one.
typedef DayAndTime = ({DateTime day, TimeOfDay? time});

/// Reads `YYYYMMDD` or `YYYYMMDDTHHmm` (also `YYYY-MM-DD` and
/// `YYYY-MM-DDTHH:mm`). Returns null for text that is not a real day or time,
/// such as `20260230`.
DayAndTime? parseDayAndTime(String text) {
  final m = _dayAndTime.firstMatch(text.trim());
  if (m == null) return null;
  final y = int.parse(m[1]!);
  final mo = int.parse(m[2]!);
  final d = int.parse(m[3]!);
  final day = DateTime(y, mo, d);
  if (day.year != y || day.month != mo || day.day != d) return null;
  if (m[4] == null) return (day: day, time: null);
  final time = _time(int.parse(m[4]!), int.parse(m[5]!));
  return time == null ? null : (day: day, time: time);
}

/// True when [text] is a complete `YYYYMMDDTHHmm`, so it sets day and time.
bool isFullDayAndTime(String text) {
  final p = parseDayAndTime(text);
  return p != null && p.time != null;
}

/// Reads a day: `YYYYMMDD` or `YYYY-MM-DD`. A text that also has a time is
/// read as its day.
DateTime? parseDay(String text) => parseDayAndTime(text)?.day;

TimeOfDay? _time(int h, int m) =>
    h < 24 && m < 60 ? TimeOfDay(hour: h, minute: m) : null;

/// Reads a time: `HHmm`, `HH:mm`, `H:mm`, `Hmm` (`930`) or an hour alone
/// (`9`). A text with a day and a time is read as its time.
TimeOfDay? parseTime(String text) {
  final t = text.trim();
  final full = parseDayAndTime(t);
  if (full != null && t.length > 8) return full.time;
  final colon = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(t);
  if (colon != null) {
    return _time(int.parse(colon[1]!), int.parse(colon[2]!));
  }
  if (!RegExp(r'^\d{1,4}$').hasMatch(t)) return null;
  if (t.length <= 2) return _time(int.parse(t), 0);
  return _time(int.parse(t.substring(0, t.length - 2)),
      int.parse(t.substring(t.length - 2)));
}

/// Formats [t] as `HH:mm`.
String formatTime(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Reads a length: `90` (minutes), `45m`, `1h`, `1h30`, `1h30m`, `1.5h` or
/// `1:30`. Returns null for text that is not a length, and for zero.
Duration? parseEventLength(String text) {
  final t = text.trim().toLowerCase().replaceAll(' ', '');
  int? minutes;
  RegExpMatch? m;
  if ((m = RegExp(r'^(\d+)$').firstMatch(t)) != null) {
    minutes = int.parse(m![1]!);
  } else if ((m = RegExp(r'^(\d+)m(?:in)?$').firstMatch(t)) != null) {
    minutes = int.parse(m![1]!);
  } else if ((m = RegExp(r'^(\d+)h(?:(\d{1,2})m?(?:in)?)?$').firstMatch(t)) !=
      null) {
    final extra = int.tryParse(m![2] ?? '') ?? 0;
    if (extra >= 60) return null;
    minutes = int.parse(m[1]!) * 60 + extra;
  } else if ((m = RegExp(r'^(\d+):(\d{2})$').firstMatch(t)) != null) {
    if (int.parse(m![2]!) >= 60) return null;
    minutes = int.parse(m[1]!) * 60 + int.parse(m[2]!);
  } else if ((m = RegExp(r'^(\d+(?:[.,]\d+)?)h$').firstMatch(t)) != null) {
    final hours = double.parse(m![1]!.replaceAll(',', '.'));
    minutes = (hours * 60).round();
  }
  if (minutes == null || minutes <= 0) return null;
  final length = Duration(minutes: minutes);
  return length > maxEventLength ? null : length;
}

/// Formats [d] the way the user types it: `45m`, `1h` or `1h30`.
String formatEventLength(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h${m.toString().padLeft(2, '0')}';
}

/// Formats [d] as a day, for a field: `2026-11-04`.
String formatDay(DateTime d) => dateKey(d);

/// The next full hour after [now]: where a new event starts when the user
/// gives no time.
DateTime nextFullHour(DateTime now) =>
    DateTime(now.year, now.month, now.day, now.hour + 1);
