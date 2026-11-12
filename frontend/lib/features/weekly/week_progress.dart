/// How far the committed plan of one week has come: done per day, what is
/// left, the cadence and the burndown.
library;

/// Progress of the tasks a week was committed to.
///
/// The server works every number out (`progress` of `GET /statistics`). This
/// class only holds them, so every client shows the same cadence and the same
/// verdict. The three small getters at the end only subtract or add numbers
/// for display.
class WeekProgress {
  /// Creates the progress.
  const WeekProgress({
    required this.committed,
    required this.done,
    required this.doneBefore,
    required this.doneUndated,
    required this.doneAfter,
    required this.doneByDay,
    required this.daysElapsed,
    required this.daysLeft,
    required this.cadence,
    required this.neededPerDay,
    required this.onTrack,
    required this.remainingByDay,
    required this.idealByDay,
    required this.scope,
  });

  /// Reads the `progress` object of `GET /statistics`.
  factory WeekProgress.fromJson(Map<String, dynamic> j) {
    List<T> list<T>(String key, T Function(Object? v) read) =>
        [for (final v in (j[key] as List? ?? const [])) read(v)];
    int n(String key) => (j[key] as num? ?? 0).toInt();
    return WeekProgress(
      committed: n('committed'),
      done: n('done'),
      doneBefore: n('done_before'),
      doneUndated: n('done_undated'),
      doneAfter: n('done_after'),
      doneByDay: list('done_by_day', (v) => (v as num).toInt()),
      daysElapsed: n('days_elapsed'),
      daysLeft: n('days_left'),
      cadence: (j['cadence'] as num?)?.toDouble(),
      neededPerDay: (j['needed_per_day'] as num?)?.toDouble(),
      onTrack: j['on_track'] as bool? ?? false,
      remainingByDay: list(
          'remaining_by_day', (v) => v == null ? null : (v as num).toInt()),
      idealByDay: list('ideal_by_day', (v) => (v as num).toDouble()),
      scope: n('scope'),
    );
  }

  /// Tasks the week was committed to.
  final int committed;

  /// Committed tasks that are done now, whenever they were completed.
  final int done;

  /// Committed tasks that were already done before the week began.
  final int doneBefore;

  /// Done tasks whose completion day the task app does not tell.
  final int doneUndated;

  /// Done tasks completed after the week ended (a past week finished late).
  final int doneAfter;

  /// Committed tasks completed on each day, Monday first.
  final List<int> doneByDay;

  /// Days of the week that have begun, counting today: 0 to 7.
  final int daysElapsed;

  /// Days of the week still to come, counting today; 0 once it is over.
  final int daysLeft;

  /// Tasks completed per day so far, or null before the week has begun.
  final double? cadence;

  /// Tasks per day that the rest of the week needs, or null when nothing is
  /// left or the week is over.
  final double? neededPerDay;

  /// The cadence is enough for what is left.
  final bool onTrack;

  /// Open tasks at the end of each day (Monday first), null for days that
  /// have not begun.
  final List<int?> remainingByDay;

  /// The straight line from the tasks to burn to zero: its value at the end of
  /// each day.
  final List<double> idealByDay;

  /// Tasks to burn at the start of the week.
  final int scope;

  /// Committed tasks still open (display only).
  int get left => committed - done;

  /// Fraction done, 0 to 1, for the bar (display only).
  double get fraction => committed == 0 ? 1 : done / committed;

  /// Committed tasks completed during the week (display only).
  int get doneInWeek => doneByDay.fold(0, (a, b) => a + b);
}

/// Short name of weekday [d] (`Mon` .. `Sun`) for chart labels.
String weekdayShort(int index) =>
    const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][index];
