/// Data models of the annual review (`/api/v1/annual-review/...`, spec 008).
///
/// Unknown enum values map to a safe default and never throw: a review of an
/// old year must open even when the server adds a value later.
library;

import 'package:flutter/foundation.dart';

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> _maps(Object? v) => [
      for (final e in (v as List? ?? const []))
        if (e is Map) Map<String, dynamic>.from(e),
    ];

double _num(Object? v, [double fallback = 0]) =>
    v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? fallback);

double? _numOrNull(Object? v) => v is num ? v.toDouble() : null;

int _int(Object? v, [int fallback = 0]) =>
    v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? fallback);

String? _str(Object? v) => v == null ? null : '$v';

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v');

String _safe(Object? v, Set<String> allowed, String fallback) {
  final s = '${v ?? ''}';
  return allowed.contains(s) ? s : fallback;
}

/// One snapshot month of the review.
@immutable
class ReviewMonth {
  /// Creates a month.
  const ReviewMonth({
    required this.month,
    required this.status,
    this.version,
    this.takenAt,
    this.schemaVersion,
    this.action,
  });

  /// Parses one month.
  factory ReviewMonth.fromJson(Map<String, dynamic> j) => ReviewMonth(
        month: '${j['month'] ?? ''}',
        status: _safe(j['status'],
            const {'stored', 'missing', 'open', 'future'}, 'missing'),
        version: j['version'] == null ? null : _int(j['version']),
        takenAt: _date(j['taken_at']),
        schemaVersion:
            j['schema_version'] == null ? null : _int(j['schema_version']),
        action: _str(j['action']),
      );

  /// `YYYY-MM`.
  final String month;

  /// `stored`, `missing`, `open` or `future`.
  final String status;

  /// The current version of the snapshot.
  final int? version;

  /// When it was stored.
  final DateTime? takenAt;

  /// The payload schema version, or null.
  final int? schemaVersion;

  /// `open_monthly_review` for a missing or open month.
  final String? action;
}

/// How many months hold a snapshot.
@immutable
class ReviewCoverage {
  /// Creates the coverage.
  const ReviewCoverage(
      {required this.stored, required this.expected, this.missing = const []});

  /// Parses the coverage.
  factory ReviewCoverage.fromJson(Map<String, dynamic> j) => ReviewCoverage(
        stored: _int(j['stored']),
        expected: _int(j['expected']),
        missing: [for (final m in (j['missing'] as List? ?? const [])) '$m'],
      );

  /// Months with a snapshot.
  final int stored;

  /// Months expected by now.
  final int expected;

  /// The missing months.
  final List<String> missing;
}

/// Why the review has no data.
@immutable
class ReviewEmpty {
  /// Creates the state.
  const ReviewEmpty({required this.reason, this.actions = const []});

  /// Parses the state.
  factory ReviewEmpty.fromJson(Map<String, dynamic> j) => ReviewEmpty(
        reason: _safe(j['reason'],
            const {'no_snapshots', 'no_goals', 'future_year'}, 'no_snapshots'),
        actions: [for (final a in (j['actions'] as List? ?? const [])) '$a'],
      );

  /// `no_snapshots`, `no_goals` or `future_year`.
  final String reason;

  /// Inline actions.
  final List<String> actions;
}

/// A stored review note.
@immutable
class ReviewNote {
  /// Creates a note.
  const ReviewNote({required this.id, required this.body, this.updatedAt});

  /// Parses a note.
  factory ReviewNote.fromJson(Map<String, dynamic> j) => ReviewNote(
        id: '${j['id'] ?? ''}',
        body: '${j['body'] ?? ''}',
        updatedAt: _date(j['updated_at']),
      );

  /// Note id.
  final String id;

  /// The text.
  final String body;

  /// When it changed.
  final DateTime? updatedAt;
}

/// One target or deadline change of a key result.
@immutable
class ReviewChange {
  /// Creates a change.
  const ReviewChange(
      {required this.kind, this.field, this.oldValue, this.newValue, this.at});

  /// Parses a change.
  factory ReviewChange.fromJson(Map<String, dynamic> j) => ReviewChange(
        kind: '${j['kind'] ?? ''}',
        field: _str(j['field']),
        oldValue: _str(j['old_value']),
        newValue: _str(j['new_value']),
        at: _date(j['at']),
      );

  /// `key_result_edited`, `key_result_retired` or `key_result_restored`.
  final String kind;

  /// `target` or `deadline`.
  final String? field;

  /// The old value.
  final String? oldValue;

  /// The new value.
  final String? newValue;

  /// When it changed.
  final DateTime? at;
}

/// One month of the twelve point series.
@immutable
class SeriesPoint {
  /// Creates a point.
  const SeriesPoint(
      {required this.month,
      required this.status,
      this.value,
      this.notStored = false});

  /// Parses a point.
  factory SeriesPoint.fromJson(Map<String, dynamic> j) => SeriesPoint(
        month: '${j['month'] ?? ''}',
        status: _safe(j['status'],
            const {'stored', 'missing', 'open', 'future'}, 'missing'),
        value: _numOrNull(j['value']),
        notStored: j['not_stored'] == true,
      );

  /// `YYYY-MM`.
  final String month;

  /// The month status.
  final String status;

  /// The stored value, or null for a gap.
  final double? value;

  /// True when the snapshot has no entry for this key result.
  final bool notStored;
}

/// One active period of a theme link.
@immutable
class ThemeRange {
  /// Creates a range.
  const ThemeRange({required this.from, this.to, this.months = const []});

  /// Parses a range.
  factory ThemeRange.fromJson(Map<String, dynamic> j) => ThemeRange(
        from: _date(j['from']),
        to: _date(j['to']),
        months: [for (final m in (j['months'] as List? ?? const [])) '$m'],
      );

  /// Start day.
  final DateTime? from;

  /// End day, or null while active.
  final DateTime? to;

  /// The months the link was active.
  final List<String> months;
}

/// The movement of a key result over a theme link.
@immutable
class ThemeMovement {
  /// Creates a movement.
  const ThemeMovement(
      {required this.from,
      required this.to,
      required this.fraction,
      required this.months});

  /// Parses a movement.
  factory ThemeMovement.fromJson(Map<String, dynamic> j) => ThemeMovement(
        from: _num(j['from']),
        to: _num(j['to']),
        fraction: _num(j['fraction']),
        months: _int(j['months']),
      );

  /// Value at the start.
  final double from;

  /// Value at the end.
  final double to;

  /// Signed fraction of the start-to-target span.
  final double fraction;

  /// How many months the link covered.
  final int months;
}

/// One milestone under a theme.
@immutable
class ThemeMilestone {
  /// Creates a milestone.
  const ThemeMilestone(
      {required this.name,
      required this.doneOn,
      required this.month,
      this.inFocus = true});

  /// Parses a milestone.
  factory ThemeMilestone.fromJson(Map<String, dynamic> j) => ThemeMilestone(
        name: '${j['name'] ?? ''}',
        doneOn: _date(j['done_on']),
        month: '${j['month'] ?? ''}',
        inFocus: j['in_focus'] != false,
      );

  /// Its stored name.
  final String name;

  /// The day it was done.
  final DateTime? doneOn;

  /// The snapshot month.
  final String month;

  /// True when it was in the focus.
  final bool inFocus;
}

/// One theme linked to a key result.
@immutable
class ThemeContribution {
  /// Creates a contribution.
  const ThemeContribution({
    required this.projectId,
    required this.name,
    this.connectionName,
    this.label,
    this.orphaned,
    this.ranges = const [],
    this.shipped = 0,
    this.shippedOutsideFocus = 0,
    this.targetSum,
    this.monthsWithTarget = 0,
    this.movement,
    this.hint,
    this.milestones = const [],
  });

  /// Parses a contribution.
  factory ThemeContribution.fromJson(Map<String, dynamic> j) {
    final orphaned = _map(j['orphaned']);
    return ThemeContribution(
      projectId: _str(j['project_id']),
      name: '${j['name'] ?? ''}',
      connectionName: _str(j['connection_name']),
      label: _str(j['label']),
      orphaned: j['orphaned'] == null ? null : _str(orphaned['reason']),
      ranges: [for (final r in _maps(j['ranges'])) ThemeRange.fromJson(r)],
      shipped: _int(j['shipped']),
      shippedOutsideFocus: _int(j['shipped_outside_focus']),
      targetSum: j['target_sum'] == null ? null : _int(j['target_sum']),
      monthsWithTarget: _int(j['months_with_target']),
      movement: j['movement'] == null
          ? null
          : ThemeMovement.fromJson(_map(j['movement'])),
      hint: _str(j['hint']),
      milestones: [
        for (final m in _maps(j['milestones'])) ThemeMilestone.fromJson(m)
      ],
    );
  }

  /// The project id.
  final String? projectId;

  /// Its stored name.
  final String name;

  /// The task connection name.
  final String? connectionName;

  /// The current label.
  final String? label;

  /// `missing` or `archived`, or null.
  final String? orphaned;

  /// The active ranges.
  final List<ThemeRange> ranges;

  /// Milestones shipped inside the ranges.
  final int shipped;

  /// Milestones shipped outside the focus.
  final int shippedOutsideFocus;

  /// The sum of the theme targets.
  final int? targetSum;

  /// How many months held a target.
  final int monthsWithTarget;

  /// The movement, or null.
  final ThemeMovement? movement;

  /// `much_shipped_little_movement`, `movement_not_from_theme` or null.
  final String? hint;

  /// The milestones.
  final List<ThemeMilestone> milestones;
}

/// The "reached by deadline" line.
@immutable
class DeadlineLine {
  /// Creates a line.
  const DeadlineLine({required this.state, this.value, this.month});

  /// Parses a line.
  factory DeadlineLine.fromJson(Map<String, dynamic> j) => DeadlineLine(
        state: _safe(j['state'],
            const {'reached', 'not_reached', 'open', 'no_value'}, 'no_value'),
        value: _numOrNull(j['value']),
        month: _str(j['month']),
      );

  /// `reached`, `not_reached`, `open` or `no_value`.
  final String state;

  /// The value at the deadline.
  final double? value;

  /// The month of that value.
  final String? month;
}

/// One key result of a goal.
@immutable
class ReviewKeyResult {
  /// Creates a key result.
  const ReviewKeyResult({
    required this.id,
    required this.metric,
    required this.startValue,
    required this.target,
    required this.outcome,
    required this.currentValue,
    this.direction = 'up',
    this.deadline = '',
    this.lastValue,
    this.lastMonth,
    this.lastAt,
    this.deadlineLine,
    this.series = const [],
    this.peakValue,
    this.peakMonth,
    this.movedAfterSnapshot,
    this.retiredAt,
    this.changes = const [],
    this.themes = const [],
    this.flags = const [],
  });

  /// Parses a key result.
  factory ReviewKeyResult.fromJson(Map<String, dynamic> j) {
    final peak = _map(j['peak']);
    final moved = _map(j['moved_after_snapshot']);
    return ReviewKeyResult(
      id: '${j['id'] ?? ''}',
      metric: '${j['metric'] ?? ''}',
      startValue: _num(j['start_value']),
      target: _num(j['target']),
      direction: _safe(j['direction'], const {'up', 'down'}, 'up'),
      deadline: '${j['deadline'] ?? ''}',
      outcome: _safe(
          j['outcome'],
          const {'hit', 'missed', 'no_value', 'retired', 'in_progress'},
          'no_value'),
      lastValue: _numOrNull(j['last_value']),
      lastMonth: _str(j['last_month']),
      lastAt: _date(j['last_at']),
      deadlineLine: j['deadline_line'] == null
          ? null
          : DeadlineLine.fromJson(_map(j['deadline_line'])),
      series: [for (final p in _maps(j['series'])) SeriesPoint.fromJson(p)],
      peakValue: _numOrNull(peak['value']),
      peakMonth: _str(peak['month']),
      movedAfterSnapshot:
          j['moved_after_snapshot'] == null ? null : _num(moved['value']),
      retiredAt: _date(j['retired_at']),
      currentValue: _num(j['current_value']),
      changes: [for (final c in _maps(j['changes'])) ReviewChange.fromJson(c)],
      themes: [
        for (final t in _maps(j['themes'])) ThemeContribution.fromJson(t)
      ],
      flags: [for (final f in _maps(j['flags'])) '${f['code'] ?? ''}'],
    );
  }

  /// The key result id.
  final String id;

  /// What is measured.
  final String metric;

  /// The value at the start.
  final double startValue;

  /// The target.
  final double target;

  /// `up` or `down`.
  final String direction;

  /// The deadline, `YYYY-MM-DD`.
  final String deadline;

  /// `hit`, `missed`, `no_value`, `retired` or `in_progress`.
  final String outcome;

  /// The last stored value, or null.
  final double? lastValue;

  /// The month it came from.
  final String? lastMonth;

  /// When it was stored.
  final DateTime? lastAt;

  /// The deadline line.
  final DeadlineLine? deadlineLine;

  /// Twelve points.
  final List<SeriesPoint> series;

  /// The best value, when it differs from the last.
  final double? peakValue;

  /// The month of the peak.
  final String? peakMonth;

  /// A live value entered after the last snapshot.
  final double? movedAfterSnapshot;

  /// When it was retired.
  final DateTime? retiredAt;

  /// The live value of the plan.
  final double currentValue;

  /// Target and deadline changes.
  final List<ReviewChange> changes;

  /// The linked themes.
  final List<ThemeContribution> themes;

  /// Flag codes such as `no_usable_theme`.
  final List<String> flags;
}

/// One goal of the year.
@immutable
class ReviewGoal {
  /// Creates a goal.
  const ReviewGoal({
    required this.id,
    required this.title,
    required this.status,
    this.retiredAt,
    this.retiredReason,
    this.note,
    this.counts = const {},
    this.keyResults = const [],
    this.flags = const [],
  });

  /// Parses a goal.
  factory ReviewGoal.fromJson(Map<String, dynamic> j) => ReviewGoal(
        id: '${j['id'] ?? ''}',
        title: '${j['title'] ?? ''}',
        status: _safe(j['status'], const {'active', 'retired'}, 'active'),
        retiredAt: _date(j['retired_at']),
        retiredReason: _str(j['retired_reason']),
        note: j['note'] == null ? null : ReviewNote.fromJson(_map(j['note'])),
        counts: _map(j['counts']),
        keyResults: [
          for (final k in _maps(j['key_results'])) ReviewKeyResult.fromJson(k)
        ],
        flags: [for (final f in _maps(j['flags'])) '${f['code'] ?? ''}'],
      );

  /// The goal id.
  final String id;

  /// The sentence.
  final String title;

  /// `active` or `retired`.
  final String status;

  /// When it was retired.
  final DateTime? retiredAt;

  /// Why it was retired.
  final String? retiredReason;

  /// The note of the goal.
  final ReviewNote? note;

  /// Outcome counts.
  final Map<String, dynamic> counts;

  /// The key results.
  final List<ReviewKeyResult> keyResults;

  /// Flag codes.
  final List<String> flags;
}

/// One category count triple.
@immutable
class ReviewCounts {
  /// Creates counts.
  const ReviewCounts(
      {this.goalAligned = 0, this.maintenance = 0, this.offPlan = 0});

  /// Parses counts.
  factory ReviewCounts.fromJson(Map<String, dynamic> j) => ReviewCounts(
        goalAligned: _int(j['goal_aligned']),
        maintenance: _int(j['maintenance']),
        offPlan: _int(j['off_plan']),
      );

  /// Goal-aligned tasks.
  final int goalAligned;

  /// Maintenance tasks.
  final int maintenance;

  /// Off-plan tasks.
  final int offPlan;

  /// The sum of the three work categories.
  int get total => goalAligned + maintenance + offPlan;

  /// True when all three are zero.
  bool get isZero => total == 0;
}

/// One month row of the year split.
@immutable
class SplitMonth {
  /// Creates a row.
  const SplitMonth(
      {required this.month,
      required this.status,
      this.counts,
      this.hidden = 0,
      this.percentages,
      this.notStored = false});

  /// Parses a row.
  factory SplitMonth.fromJson(Map<String, dynamic> j) => SplitMonth(
        month: '${j['month'] ?? ''}',
        status: _safe(j['status'],
            const {'stored', 'missing', 'open', 'future'}, 'missing'),
        counts: j['counts'] == null
            ? null
            : ReviewCounts.fromJson(_map(j['counts'])),
        hidden: _int(j['hidden']),
        percentages: j['percentages'] == null
            ? null
            : ReviewCounts.fromJson(_map(j['percentages'])),
        notStored: j['not_stored'] == true,
      );

  /// `YYYY-MM`.
  final String month;

  /// The month status.
  final String status;

  /// Stored counts, or null.
  final ReviewCounts? counts;

  /// Hidden tasks.
  final int hidden;

  /// Stored percentages.
  final ReviewCounts? percentages;

  /// True when the snapshot has no category counts.
  final bool notStored;
}

/// The year split.
@immutable
class ReviewSplit {
  /// Creates the split.
  const ReviewSplit({
    required this.monthsCovered,
    required this.counts,
    required this.total,
    required this.hidden,
    required this.percentages,
    this.months = const [],
  });

  /// Parses the split.
  factory ReviewSplit.fromJson(Map<String, dynamic> j) => ReviewSplit(
        monthsCovered: _int(j['months_covered']),
        counts: ReviewCounts.fromJson(_map(j['counts'])),
        total: _int(j['total']),
        hidden: _int(j['hidden']),
        percentages: ReviewCounts.fromJson(_map(j['percentages'])),
        months: [for (final m in _maps(j['months'])) SplitMonth.fromJson(m)],
      );

  /// Months with counts.
  final int monthsCovered;

  /// The summed counts.
  final ReviewCounts counts;

  /// Their total.
  final int total;

  /// Hidden tasks.
  final int hidden;

  /// Whole percentages.
  final ReviewCounts percentages;

  /// Twelve rows.
  final List<SplitMonth> months;
}

/// What annual planning offers for the next year.
@immutable
class NextYear {
  /// Creates the summary.
  const NextYear({
    required this.year,
    required this.fromYear,
    required this.available,
    required this.hasPlan,
    required this.unmetKeyResults,
    required this.links,
  });

  /// Parses the summary.
  factory NextYear.fromJson(Map<String, dynamic> j) => NextYear(
        year: _int(j['year']),
        fromYear: _int(j['from_year']),
        available: j['available'] != false,
        hasPlan: j['has_plan'] == true,
        unmetKeyResults: _int(j['unmet_key_results']),
        links: _int(j['links']),
      );

  /// The new year.
  final int year;

  /// The reviewed year.
  final int fromYear;

  /// False for a future year.
  final bool available;

  /// True when the reviewed year has a plan.
  final bool hasPlan;

  /// Key results that planning offers again.
  final int unmetKeyResults;

  /// Links that planning offers again.
  final int links;
}

/// The stored period review of the year.
@immutable
class StoredPeriodReview {
  /// Creates the entry.
  const StoredPeriodReview({required this.planId, required this.periodStart});

  /// Parses the entry.
  factory StoredPeriodReview.fromJson(Map<String, dynamic> j) =>
      StoredPeriodReview(
          planId: '${j['plan_id'] ?? ''}',
          periodStart: '${j['period_start'] ?? ''}');

  /// The plan id.
  final String planId;

  /// The first day of the year.
  final String periodStart;
}

/// The whole review of one year.
@immutable
class AnnualReview {
  /// Creates a review.
  const AnnualReview({
    required this.year,
    required this.state,
    required this.inProgress,
    required this.months,
    required this.coverage,
    required this.split,
    required this.nextYear,
    this.empty,
    this.goals = const [],
    this.milestonesShipped = 0,
    this.yearNote,
    this.storedPeriodReview,
  });

  /// Parses a review.
  factory AnnualReview.fromJson(Map<String, dynamic> j) {
    final shipped = _map(j['milestones_shipped']);
    return AnnualReview(
      year: _int(j['year']),
      state: _safe(j['state'], const {'past', 'current', 'future'}, 'past'),
      inProgress: j['in_progress'] == true,
      months: [for (final m in _maps(j['months'])) ReviewMonth.fromJson(m)],
      coverage: ReviewCoverage.fromJson(_map(j['coverage'])),
      empty: j['empty'] == null ? null : ReviewEmpty.fromJson(_map(j['empty'])),
      goals: [for (final g in _maps(j['goals'])) ReviewGoal.fromJson(g)],
      milestonesShipped: _int(shipped['count']),
      split: ReviewSplit.fromJson(_map(j['split'])),
      nextYear: NextYear.fromJson(_map(j['next_year'])),
      yearNote: j['year_note'] == null
          ? null
          : ReviewNote.fromJson(_map(j['year_note'])),
      storedPeriodReview: j['stored_period_review'] == null
          ? null
          : StoredPeriodReview.fromJson(_map(j['stored_period_review'])),
    );
  }

  /// The planning year.
  final int year;

  /// `past`, `current` or `future`.
  final String state;

  /// True for the current year.
  final bool inProgress;

  /// The twelve months.
  final List<ReviewMonth> months;

  /// The coverage.
  final ReviewCoverage coverage;

  /// Why there is no data, or null.
  final ReviewEmpty? empty;

  /// The goals, active first.
  final List<ReviewGoal> goals;

  /// Distinct milestones over the year.
  final int milestonesShipped;

  /// The year split.
  final ReviewSplit split;

  /// The next year summary.
  final NextYear nextYear;

  /// The note of the year.
  final ReviewNote? yearNote;

  /// A stored period review of the year.
  final StoredPeriodReview? storedPeriodReview;
}
