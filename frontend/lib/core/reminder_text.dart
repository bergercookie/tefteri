/// Words for how long before the due time a reminder fires.
library;

/// `15 minutes before`, `1 hour before`, `2 days before`, or `at the due
/// time` for 0.
String reminderOffsetText(int minutes) {
  if (minutes == 0) return 'at the due time';
  String unit(int n, String one) => '$n ${n == 1 ? one : '${one}s'}';
  final text = minutes % 1440 == 0
      ? unit(minutes ~/ 1440, 'day')
      : minutes % 60 == 0
          ? unit(minutes ~/ 60, 'hour')
          : unit(minutes, 'minute');
  return '$text before';
}
