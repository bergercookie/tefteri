/// The numbers of the weeks, and how a week compares with the ones before it.
///
/// Only counts: tasks, milestones and themes. Time is never measured.
library;

import 'package:flutter/foundation.dart' show immutable;

import '../../core/planning_models.dart' show dateKey;

/// The numbers of one week, as the server sends them.
@immutable
class WeekMetrics {
  /// Creates the numbers of a week.
  const WeekMetrics({
    required this.weekStart,
    required this.finished,
    this.hasPlan = false,
    this.committedTasks = 0,
    this.committedDone = 0,
    this.milestonesCommitted = 0,
    this.milestonesDone = 0,
    this.milestonesFinished = 0,
    this.tasksDone = 0,
    this.goalAligned = 0,
    this.maintenance = 0,
    this.offPlan = 0,
    this.themesActive = 0,
    this.completionPercent,
    this.goalAlignedPercent,
    this.hasData = false,
  });

  /// Reads a week of `GET /weekly/trends`.
  factory WeekMetrics.fromJson(Map<String, dynamic> j) {
    int n(String k) => (j[k] as num? ?? 0).toInt();
    return WeekMetrics(
      weekStart: DateTime.parse('${j['week_start']}'),
      finished: j['finished'] == true,
      hasPlan: j['has_plan'] == true,
      committedTasks: n('committed_tasks'),
      committedDone: n('committed_done'),
      milestonesCommitted: n('milestones_committed'),
      milestonesDone: n('milestones_done'),
      milestonesFinished: n('milestones_finished'),
      tasksDone: n('tasks_done'),
      goalAligned: n('goal_aligned'),
      maintenance: n('maintenance'),
      offPlan: n('off_plan'),
      themesActive: n('themes_active'),
      completionPercent: (j['completion_percent'] as num?)?.toInt(),
      goalAlignedPercent: (j['goal_aligned_percent'] as num?)?.toInt(),
      hasData: j['has_data'] == true,
    );
  }

  /// Monday of the week.
  final DateTime weekStart;

  /// The week has ended. The running week is not final.
  final bool finished;

  /// A plan was committed for the week.
  final bool hasPlan;

  /// Tasks in the committed plan.
  final int committedTasks;

  /// Committed tasks that were done.
  final int committedDone;

  /// Milestones in the committed plan.
  final int milestonesCommitted;

  /// Committed milestones that were done.
  final int milestonesDone;

  /// Milestones that became done in the week, committed or not.
  final int milestonesFinished;

  /// Tasks completed in the week, in the three work categories.
  final int tasksDone;

  /// Of those, the goal-aligned ones.
  final int goalAligned;

  /// Of those, the maintenance ones.
  final int maintenance;

  /// Of those, the off-plan ones.
  final int offPlan;

  /// Themes that had a completed task.
  final int themesActive;

  /// Committed tasks that were done, in whole percent; null with none.
  final int? completionPercent;

  /// The share of goal-aligned work in the three categories; null with none.
  final int? goalAlignedPercent;

  /// The week has something to compare.
  final bool hasData;

  /// The key of the week, `YYYY-MM-DD`.
  String get key => dateKey(weekStart);
}

/// Where a measure went compared with the weeks before.
enum Direction {
  /// Higher than the earlier weeks.
  up('up'),

  /// About the same.
  steady('steady'),

  /// Lower than the earlier weeks.
  down('down');

  const Direction(this.word);

  /// The word the user reads.
  final String word;
}

/// One measure of a week against the average of the weeks before it.
@immutable
class TrendLine {
  /// Creates a line.
  const TrendLine({
    required this.key,
    required this.label,
    required this.value,
    required this.baseline,
    required this.direction,
    required this.sentence,
  });

  /// Stable name of the measure.
  final String key;

  /// What is measured, for example `Completion`.
  final String label;

  /// The value of the week, as text.
  final String value;

  /// The average of the weeks before, as text.
  final String baseline;

  /// Up, steady or down.
  final Direction direction;

  /// The whole line in words.
  final String sentence;
}

/// A week compared with the weeks before it.
@immutable
class Comparison {
  /// Creates a comparison.
  const Comparison(
      {required this.week, this.lines = const [], this.before = 0});

  /// Monday of the week that is compared.
  final DateTime week;

  /// The measures. Empty when there are too few weeks before.
  final List<TrendLine> lines;

  /// How many earlier weeks with data were used.
  final int before;

  /// Too few weeks with data came before the week for an honest comparison.
  bool get notEnough => lines.isEmpty;
}

/// How many weeks before the week make the average.
const int baselineWeeks = 4;

/// How few earlier weeks still make a comparison.
const int minBaselineWeeks = 2;

/// The distance, in points, from which a share counts as moved.
const int percentThreshold = 5;

/// The distance, as a share of the average, from which a count counts as moved.
const double countThreshold = 0.2;

/// A number for a sentence: a share in whole percent, a count with at most one
/// decimal ("6.5 tasks").
String _num(double v, {bool whole = false}) => whole || v == v.roundToDouble()
    ? v.round().toString()
    : v.toStringAsFixed(1);

Direction _dir(double value, double base, {required bool percent}) {
  final diff = value - base;
  final limit = percent
      ? percentThreshold.toDouble()
      : (base * countThreshold < 1 ? 1.0 : base * countThreshold);
  if (diff >= limit) return Direction.up;
  if (diff <= -limit) return Direction.down;
  return Direction.steady;
}

TrendLine? _line({
  required String key,
  required String label,
  required double? value,
  required List<double> earlier,
  required bool percent,
  required String Function(String v) show,
  required String unit,
}) {
  if (value == null || earlier.length < minBaselineWeeks) return null;
  final base = earlier.reduce((a, b) => a + b) / earlier.length;
  final dir = _dir(value, base, percent: percent);
  final diff = (value - base).abs();
  String n(double v) => _num(v, whole: percent);
  final how = switch (dir) {
    Direction.steady => 'about the same as',
    Direction.up => '${n(diff)} $unit higher than',
    Direction.down => '${n(diff)} $unit lower than',
  };
  return TrendLine(
    key: key,
    label: label,
    value: show(n(value)),
    baseline: show(n(base)),
    direction: dir,
    sentence: '$label: ${show(n(value))}, $how the average of your '
        '${earlier.length} earlier ${earlier.length == 1 ? 'week' : 'weeks'} '
        '(${show(n(base))}).',
  );
}

/// Compares the week that starts on [week] with up to [baselineWeeks] weeks
/// with data before it. Only weeks that have ended count as earlier weeks.
/// Returns null when [weeks] does not hold [week] or the week has no data.
Comparison? compareWeek(List<WeekMetrics> weeks, DateTime week) {
  final i = weeks.indexWhere((w) => dateKey(w.weekStart) == dateKey(week));
  if (i < 0 || !weeks[i].hasData) return null;
  final latest = weeks[i];
  final earlier = [
    for (var k = i - 1; k >= 0 && k >= 0; k--)
      if (weeks[k].finished && weeks[k].hasData) weeks[k],
  ].take(baselineWeeks).toList();
  List<double> pick(num? Function(WeekMetrics) f) => [
        for (final w in earlier)
          if (f(w) != null) f(w)!.toDouble()
      ];
  final lines = [
    _line(
        key: 'completion',
        label: 'Completion of the committed tasks',
        value: latest.completionPercent?.toDouble(),
        earlier: pick((w) => w.completionPercent),
        percent: true,
        show: (v) => '$v%',
        unit: 'points'),
    _line(
        key: 'done',
        label: 'Tasks completed',
        value: latest.tasksDone.toDouble(),
        earlier: pick((w) => w.tasksDone),
        percent: false,
        show: (v) => v,
        unit: 'tasks'),
    _line(
        key: 'goal',
        label: 'Goal-aligned share of the work',
        value: latest.goalAlignedPercent?.toDouble(),
        earlier: pick((w) => w.goalAlignedPercent),
        percent: true,
        show: (v) => '$v%',
        unit: 'points'),
    _line(
        key: 'milestones',
        label: 'Milestones done',
        value: latest.milestonesDone.toDouble(),
        earlier: [
          for (final w in earlier)
            if (w.milestonesCommitted > 0) w.milestonesDone.toDouble(),
        ],
        percent: false,
        show: (v) => v,
        unit: 'milestones'),
  ].whereType<TrendLine>().toList();
  return Comparison(
      week: latest.weekStart, lines: lines, before: earlier.length);
}

/// The week to compare on the trends page: the newest week that has ended and
/// has data. Null when there is none.
DateTime? latestFinishedWeek(List<WeekMetrics> weeks) {
  for (final w in weeks.reversed) {
    if (w.finished && w.hasData) return w.weekStart;
  }
  return null;
}
