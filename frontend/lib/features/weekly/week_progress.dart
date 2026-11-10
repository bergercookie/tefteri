/// How far the committed plan of one week has come: done per day, what is
/// left, the cadence and the burndown.
library;

import 'weekly_models.dart';

/// Progress of the tasks a week was committed to.
///
/// Built from the plan alone, so it is plain arithmetic and easy to test.
class WeekProgress {
  const WeekProgress._({
    required this.monday,
    required this.committed,
    required this.doneByDay,
    required this.doneBefore,
    required this.doneUndated,
    required this.doneAfter,
    required this.daysElapsed,
    required this.daysLeft,
  });

  /// Reads the progress of [plan] (the plan of the week that starts on
  /// [monday]) as of [today].
  factory WeekProgress.of(WeeklyPlan plan, DateTime monday, DateTime today) {
    final start = DateTime(monday.year, monday.month, monday.day);
    final end = DateTime(start.year, start.month, start.day + 7);
    final day = DateTime(today.year, today.month, today.day);
    final byDay = List<int>.filled(7, 0);
    var before = 0, undated = 0, after = 0, committed = 0;
    for (final p in plan.projects) {
      for (final t in p.committedTasks) {
        committed++;
        if (!t.done) continue;
        final d = t.completedDay;
        if (d == null) {
          undated++;
        } else {
          final local = DateTime(d.year, d.month, d.day);
          if (local.isBefore(start)) {
            before++;
          } else if (!local.isBefore(end)) {
            after++;
          } else {
            byDay[local.difference(start).inDays]++;
          }
        }
      }
    }
    final elapsed = day.isBefore(start)
        ? 0
        : day.isBefore(end)
            ? day.difference(start).inDays + 1
            : 7;
    return WeekProgress._(
      monday: start,
      committed: committed,
      doneByDay: byDay,
      doneBefore: before,
      doneUndated: undated,
      doneAfter: after,
      daysElapsed: elapsed,
      daysLeft: day.isBefore(start)
          ? 7
          : day.isBefore(end)
              ? 7 - day.difference(start).inDays
              : 0,
    );
  }

  /// Monday of the week.
  final DateTime monday;

  /// Tasks the week was committed to.
  final int committed;

  /// Tasks completed on each day, Monday first.
  final List<int> doneByDay;

  /// Committed tasks that were already done before the week began.
  final int doneBefore;

  /// Done tasks whose completion day the task app does not tell.
  final int doneUndated;

  /// Done tasks completed after the week ended (a past week finished late).
  final int doneAfter;

  /// Days of the week that have begun, counting today: 0 to 7.
  final int daysElapsed;

  /// Tasks completed during the week.
  int get doneInWeek => doneByDay.fold(0, (a, b) => a + b);

  /// Committed tasks that are done now, whenever they were completed.
  int get done => doneInWeek + doneBefore + doneUndated + doneAfter;

  /// Committed tasks still open.
  int get left => committed - done;

  /// Fraction done, 0 to 1 (1 for a plan without tasks).
  double get fraction => committed == 0 ? 1 : done / committed;

  /// Days of the week still to come, counting today; 0 once it is over.
  final int daysLeft;

  /// Tasks completed per day so far this week, or null before it has begun.
  double? get cadence => daysElapsed == 0 ? null : doneInWeek / daysElapsed;

  /// Tasks per day that the rest of the week needs, counting today, or null
  /// when nothing is left or the week is over.
  double? get neededPerDay =>
      left == 0 || daysLeft == 0 ? null : left / daysLeft;

  /// True when the work needed per day is no more than the cadence.
  bool get onTrack {
    if (left == 0) return true;
    final c = cadence, need = neededPerDay;
    if (c == null || need == null) return false;
    return c >= need;
  }

  /// Open tasks at the end of each day (Monday first), or null for days that
  /// have not begun. The count starts from what the week really holds: tasks
  /// done before it or without a day are not part of the burn.
  List<int?> get remainingByDay {
    var left = committed - doneBefore - doneUndated;
    return [
      for (var i = 0; i < 7; i++)
        if (i < daysElapsed) left -= doneByDay[i] else null,
    ];
  }

  /// The straight line from the tasks to burn at Monday morning to zero on
  /// Sunday night: its value at the end of each day (Monday first).
  List<double> get idealByDay {
    final start = committed - doneBefore - doneUndated;
    return [for (var i = 1; i <= 7; i++) start * (7 - i) / 7];
  }

  /// Tasks to burn at the start of the week.
  int get scope => committed - doneBefore - doneUndated;
}

/// Short name of weekday [d] (`Mon` .. `Sun`) for chart labels.
String weekdayShort(int index) =>
    const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][index];
