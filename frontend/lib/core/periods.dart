/// Date helpers for year, month and week periods. Weeks start on Monday.
library;

/// Returns the Monday of the week that holds [d].
DateTime weekStartOf(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - 1));

/// Returns every day in `[start, endExclusive)`.
List<DateTime> daysBetween(DateTime start, DateTime endExclusive) {
  final days = <DateTime>[];
  var d = DateTime(start.year, start.month, start.day);
  while (d.isBefore(endExclusive)) {
    days.add(d);
    d = DateTime(d.year, d.month, d.day + 1);
  }
  return days;
}

/// One period that the user can choose, such as a month in a filter.
class PeriodChoice {
  /// Creates a choice.
  const PeriodChoice(
      {required this.label, required this.type, required this.start});

  /// Text for the user.
  final String label;

  /// `year`, `month` or `week`.
  final String type;

  /// First day, `YYYY-MM-DD`.
  final String start;
}

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Short name of month number [month] (1 to 12).
String monthName(int month) => _monthNames[month - 1];

/// Short label for a period, such as `2026`, `Nov 2026` or
/// `Week of 2026-11-02`.
String periodLabel(String type, String start) {
  final s = DateTime.parse(start);
  return switch (type) {
    'year' => '${s.year}',
    'month' => '${monthName(s.month)} ${s.year}',
    _ => 'Week of $start',
  };
}
